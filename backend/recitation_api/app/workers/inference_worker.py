"""Inference worker: consumes recitation jobs from Redis Streams.

This worker runs as a separate process (or sidecar) that:
1. Reads jobs from the `qari:recitation:jobs` Redis Stream.
2. Loads the audio file from disk.
3. Runs the ML inference pipeline (delegates to the ML engine service).
4. Stores per-word results in Redis and publishes them via Pub/Sub.
5. Updates the session status in Redis.

In production, the actual ML inference call would be an HTTP/gRPC request
to the ML engine service. Here we implement the full stream consumption
loop with a pluggable inference callback.
"""

import asyncio
import json
import os
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Optional

import redis.asyncio as redis

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

# Result Redis key helpers (kept in sync with the route layer).
SESSION_KEY = "qari:recitation:session:{session_id}"
RESULT_KEY = "qari:recitation:result:{session_id}"

# Confidence threshold below which the mobile shows NO red marks (spec §3 trust principle).
LOW_CONFIDENCE_FALLBACK = 0.5


# ---------------------------------------------------------------------------
# Inference callback type
# ---------------------------------------------------------------------------

InferenceCallback = Callable[[dict], "asyncio.Future"]


# ---------------------------------------------------------------------------
# Reference-store resolution (expected Quran words + tajweed positions)
# ---------------------------------------------------------------------------

_reference_store = None


def _get_reference_store():
    """Lazily build a file-backed ReferenceStore from ``reference_data_dir``.

    Falls back to an empty store; missing ayahs are resolved on demand from
    core_api (see ``_ensure_reference``).
    """
    global _reference_store
    if _reference_store is None:
        try:
            from ml.tajweed.reference_store import ReferenceStore
            data_dir = settings.reference_data_dir or None
            _reference_store = ReferenceStore(data_dir)
            logger.info("worker.refstore_loaded", entries=len(_reference_store))
        except Exception as exc:  # pragma: no cover - ml deps optional in dev
            logger.warning("worker.refstore_unavailable", error=str(exc))
            _reference_store = None
    return _reference_store


def _normalize_arabic(text: str) -> str:
    """Normalize Arabic text for alignment (strip harakat)."""
    try:
        from ml.inference.asr import normalize_arabic
        return normalize_arabic(text)
    except Exception:
        # Minimal diacritic strip (Arabic harakat + superscript alef).
        import re
        return re.sub(r"[\u064B-\u065F\u0670]", "", text or "")


def _ensure_reference(surah: int, ayah: int, qari_id: Optional[str]) -> bool:
    """Make sure ``(surah, ayah)`` exists in the reference store.

    Tries the file-backed store first, then lazily fetches the word list and
    tajweed spans from core_api and caches it in memory. Returns True if a
    reference is available.
    """
    store = _get_reference_store()
    if store is not None and store.has(surah, ayah):
        return True
    if store is None:
        return False

    try:
        import httpx
        from ml.tajweed.reference_store import (
            AyahReference,
            WordReference,
            TajweedAnnotation,
        )

        url = (
            f"{settings.core_api_base_url}/v1/surahs/{surah}/ayahs"
            f"?from={ayah}&to={ayah}"
        )
        resp = httpx.get(url, timeout=10)
        resp.raise_for_status()
        payload = resp.json()
        # The corpus route returns a bare list of ayahs.
        ayahs = payload if isinstance(payload, list) else (
            payload.get("ayahs") or payload.get("data") or []
        )
        if not ayahs:
            return False
        ayah_obj = ayahs[0]
        words = []
        for w in ayah_obj.get("words", []):
            spans = w.get("tajweed_spans") or []
            tajweed_checks = [
                TajweedAnnotation(
                    rule=s.get("rule", ""),
                    letter=s.get("letter", ""),
                    position=int(s.get("char_start", 0)),
                    expected_duration_ms=0,
                )
                for s in spans
            ]
            words.append(WordReference(
                word=_normalize_arabic(w.get("text_arabic", "")),
                phonemes=[],
                tajweed_checks=tajweed_checks,
                ref_start_ms=0,
                ref_end_ms=0,
            ))
        ref = AyahReference(
            surah=surah,
            ayah=ayah,
            text=ayah_obj.get("text_arabic", ""),
            normalized_text=_normalize_arabic(ayah_obj.get("text_arabic", "")),
            words=words,
            reference_audio_url=ayah_obj.get("audio_url", ""),
            reference_qari="",
        )
        store.add(ref)
        logger.info("worker.ref_fetched", surah=surah, ayah=ayah, words=len(words))
        return True
    except Exception as exc:
        logger.warning("worker.ref_fetch_failed", surah=surah, ayah=ayah, error=str(exc))
        return False


def _build_reference_audio_url(surah: int, ayah: int) -> str:
    """Synthesise a reachable Qari reference audio URL for an ayah.

    The reference data often ships without an ``audio_url`` (the recitation
    corpus leaves it empty), which left the mobile's "Reference (Qari)" track
    silent. We fall back to the same CDN the Flutter app already uses for
    reciter playback so it is reliably reachable.
    """
    base = settings.reference_audio_base_url.rstrip("/")
    reciter = settings.reference_audio_reciter
    return f"{base}/{reciter}/{surah:03d}{ayah:03d}.mp3"


def _load_audio(audio_path: str) -> tuple:
    """Load a WAV file as a (float32 ndarray, sample_rate) tuple."""
    try:
        import soundfile as sf
        audio, sr = sf.read(audio_path, dtype="float32", always_2d=False)
        if audio.ndim > 1:
            audio = audio.mean(axis=1)
        return audio, int(sr)
    except Exception:
        pass
    # Fallback: stdlib wave reader + numpy.
    import wave
    import numpy as np
    with wave.open(audio_path, "rb") as wf:
        sr = wf.getframerate()
        n = wf.getnframes()
        raw = wf.readframes(n)
        dtype = np.int16 if wf.getsampwidth() == 2 else np.int32
        audio = np.frombuffer(raw, dtype=dtype).astype(np.float32)
        peak = np.iinfo(dtype).max
        audio = audio / peak
        if wf.getnchannels() > 1:
            audio = audio.reshape(-1, wf.getnchannels()).mean(axis=1)
    return audio, int(sr)


# ---------------------------------------------------------------------------
# Inference callbacks
# ---------------------------------------------------------------------------

async def _default_inference(job: dict) -> dict:
    """Deterministic stub used when ``QARI_ML_USE_STUB=true`` (local dev).

    Emits the same mobile-shaped result contract as the real engine so the
    client flow can be exercised without GPU/model weights. It never marks a
    word incorrect (no false reds).
    """
    await asyncio.sleep(1)
    surah = int(job.get("surah_number", 1))
    ayah_from = int(job.get("ayah_from", 1))
    ayah_to = int(job.get("ayah_to", 1))

    word_verdicts = []
    idx = 0
    for ayah in range(ayah_from, ayah_to + 1):
        for pos in range(1, 6):
            word_verdicts.append({
                "word": f"word_{surah}_{ayah}_{pos}",
                "word_index": idx,
                "is_correct": True,
                "confidence": 0.95,
                "expected_text": f"word_{surah}_{ayah}_{pos}",
                "actual_text": f"word_{surah}_{ayah}_{pos}",
                "error_type": None,
                "error_description": None,
                "reference_audio_url": None,
                "user_audio_url": None,
                "phoneme_errors": [],
            })
            idx += 1

    return _build_result_dict(
        job=job,
        session_id=job.get("session_id", ""),
        surah=surah,
        ayah=ayah_from,
        overall=1.0,
        pronunciation=1.0,
        tajweed=1.0,
        fluency=1.0,
        accuracy=1.0,
        word_verdicts=word_verdicts,
        reference_audio_url=None,
        user_audio_url=job.get("audio_path"),
        feedback="Stub mode — connect the ML engine for real feedback.",
        feedback_urdu=None,
        duration_seconds=int(float(job.get("audio_duration_sec", 0))),
        confidence=1.0,
    )


async def run_ml_inference(job: dict) -> dict:
    """Real recitation inference: Whisper ASR + Wav2Vec2 alignment + scoring.

    Lazily imports the ``ml`` package so the worker process starts without GPU
    dependencies, and degrades gracefully (no red marks) when a reference or
    model is unavailable — per the spec's trust principle (§3).
    """
    from ml.pipeline import RecitationPipeline

    session_id = job.get("session_id", "")
    surah = int(job.get("surah_number", 1))
    ayah_from = int(job.get("ayah_from", 1))
    ayah_to = int(job.get("ayah_to", 1))
    qari_id = job.get("qari_id")
    audio_path = job.get("audio_path")

    # The user's recording lives on the server filesystem; the mobile app can
    # only play an HTTP URL, so publish the served endpoint instead of the
    # local path (otherwise A/B playback is silent).
    public_base = settings.recitation_api_public_url.rstrip("/")
    if public_base:
        user_audio_url = f"{public_base}/v1/recitations/{session_id}/audio"
    else:
        user_audio_url = job.get("audio_path")
    duration_sec = int(float(job.get("audio_duration_sec", 0)))

    if not audio_path or not os.path.exists(audio_path):
        raise ValueError(f"Audio file missing for session {session_id}")

    audio, sr = _load_audio(audio_path)

    # Build the pipeline once; ReferenceStore is resolved per ayah.
    store = _get_reference_store()
    pipeline = RecitationPipeline(reference_store=store) if store is not None else None
    if pipeline is None:
        raise ValueError("Reference store unavailable — cannot run inference")

    word_verdicts: list[dict] = []
    global_idx = 0
    fluency_total = 0.0
    tajweed_total = 0.0
    overall_total = 0.0
    evaluated = 0
    evaluated_ayahs = 0
    reference_audio_url: Optional[str] = None

    def _resolve_reference_url(ayah: int) -> str:
        # Prefer the reference's own audio URL; fall back to the CDN so the
        # mobile always has a playable "Reference (Qari)" track.
        if ml_result.reference_audio_url:
            return ml_result.reference_audio_url
        return _build_reference_audio_url(surah, ayah)

    for ayah in range(ayah_from, ayah_to + 1):
        # Resolve reference; skip ayahs we cannot evaluate (no false reds).
        if not _ensure_reference(surah, ayah, qari_id):
            logger.warning("worker.skip_ayah_no_ref", session_id=session_id, surah=surah, ayah=ayah)
            continue

        try:
            ml_result = await asyncio.to_thread(
                pipeline.analyze, audio, sr, surah, ayah, session_id,
                user_audio_url=user_audio_url,
            )
        except Exception as exc:
            logger.error("worker.analyze_failed", session_id=session_id, surah=surah, ayah=ayah, error=str(exc))
            continue

        evaluated_ayahs += 1
        if reference_audio_url is None:
            reference_audio_url = _resolve_reference_url(ayah)
        fluency_total += ml_result.scores.fluency
        tajweed_total += ml_result.scores.tajweed
        overall_total += ml_result.scores.overall

        for wr in ml_result.words:
            verdict = wr.verdict
            is_correct = verdict == "correct"
            error_type = None if is_correct else verdict
            error_description = _describe_errors(wr.tajweed_issues) if not is_correct else None
            word_verdicts.append({
                "word": wr.word or wr.reference or "",
                "word_index": global_idx,
                "is_correct": is_correct,
                "confidence": wr.confidence,
                "expected_text": wr.reference,
                "actual_text": wr.hypothesis,
                "error_type": error_type,
                "error_description": error_description,
                "reference_audio_url": _resolve_reference_url(ayah),
                "user_audio_url": user_audio_url,
                "phoneme_errors": [],
            })
            global_idx += 1
        evaluated += 1

    if evaluated_ayahs == 0:
        # Nothing could be evaluated — return a low-confidence result so the
        # mobile shows the "we couldn't analyse" state (no red marks).
        return _build_result_dict(
            job=job, session_id=session_id, surah=surah, ayah=ayah_from,
            overall=0.0, pronunciation=0.0, tajweed=0.0, fluency=0.0, accuracy=0.0,
            word_verdicts=[], reference_audio_url=None, user_audio_url=user_audio_url,
            feedback="We couldn't analyse this recitation with enough confidence.",
            feedback_urdu=None, duration_seconds=duration_sec,
            confidence=0.0,
        )

    n = evaluated_ayahs
    confidence = 1.0 if evaluated_ayahs >= (ayah_to - ayah_from + 1) else 0.4
    return _build_result_dict(
        job=job, session_id=session_id, surah=surah, ayah=ayah_from,
        overall=overall_total / n / 100.0,
        pronunciation=fluency_total / n / 100.0,
        tajweed=tajweed_total / n / 100.0,
        fluency=fluency_total / n / 100.0,
        accuracy=fluency_total / n / 100.0,
        word_verdicts=word_verdicts,
        reference_audio_url=reference_audio_url,
        user_audio_url=user_audio_url,
        feedback="AI feedback complete. Tap red words to compare your recitation.",
        feedback_urdu=None,
        duration_seconds=duration_sec,
        confidence=confidence,
    )


def _describe_errors(tajweed_issues: list) -> Optional[str]:
    """Build a short human-readable error hint from tajweed issues."""
    if not tajweed_issues:
        return "Pronunciation differs from the reference. Listen and try again."
    parts = []
    for issue in tajweed_issues[:2]:
        rule = issue.get("rule") or issue.get("check_type") or "tajweed"
        parts.append(f"Check your {rule}.")
    return " ".join(parts) if parts else None


def _build_result_dict(
    *,
    job: dict,
    session_id: str,
    surah: int,
    ayah: int,
    overall: float,
    pronunciation: float,
    tajweed: float,
    fluency: float,
    accuracy: float,
    word_verdicts: list,
    reference_audio_url: Optional[str],
    user_audio_url: Optional[str],
    feedback: Optional[str],
    feedback_urdu: Optional[str],
    duration_seconds: int,
    confidence: float,
    pronunciation_available: bool = False,
    tajweed_available: bool = False,
    fluency_available: bool = False,
) -> dict:
    """Assemble the mobile-shaped result dict (RecitationAnalysisResult)."""
    return {
        "session_id": session_id,
        "surah_number": surah,
        "ayah_number": ayah,
        "overall_score": round(overall, 4),
        "pronunciation_score": round(pronunciation, 4),
        "tajweed_score": round(tajweed, 4),
        "fluency_score": round(fluency, 4),
        "accuracy_score": round(accuracy, 4),
        "pronunciation_available": pronunciation_available,
        "tajweed_available": tajweed_available,
        "fluency_available": fluency_available,
        "word_verdicts": word_verdicts,
        "reference_audio_url": reference_audio_url,
        "user_audio_url": user_audio_url,
        "feedback": feedback,
        "feedback_urdu": feedback_urdu,
        "duration_seconds": duration_seconds,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "confidence": round(confidence, 4),
    }


class InferenceWorker:
    """Redis Streams consumer for recitation inference jobs.

    Usage::

        worker = InferenceWorker()
        await worker.start()
        # ... runs until cancelled
        await worker.stop()
    """

    def __init__(
        self,
        *,
        inference_callback: Optional[InferenceCallback] = None,
        consumer_name: Optional[str] = None,
    ):
        self._redis: Optional[redis.Redis] = None
        self._inference = inference_callback or _select_default_inference()
        self._consumer_name = consumer_name or settings.recitation_consumer_name
        self._group = settings.recitation_consumer_group
        self._stream = settings.recitation_stream
        self._running = False
        self._processed = 0
        self._errors = 0

    async def start(self) -> None:
        """Start the worker loop."""
        self._redis = redis.from_url(settings.redis_url, decode_responses=True)
        self._running = True

        # Ensure consumer group exists
        await self._ensure_consumer_group()

        logger.info(
            "worker.started",
            stream=self._stream,
            group=self._group,
            consumer=self._consumer_name,
        )

        try:
            await self._consume_loop()
        finally:
            await self.stop()

    async def stop(self) -> None:
        """Stop the worker and close Redis connection."""
        self._running = False
        if self._redis:
            await self._redis.aclose()
            self._redis = None
        logger.info("worker.stopped", processed=self._processed, errors=self._errors)

    async def _ensure_consumer_group(self) -> None:
        """Create the consumer group if it doesn't exist."""
        try:
            await self._redis.xgroup_create(
                self._stream,
                self._group,
                id="0",
                mkstream=True,
            )
            logger.info("worker.group_created", group=self._group)
        except redis.ResponseError as exc:
            if "BUSYGROUP" in str(exc):
                logger.info("worker.group_exists", group=self._group)
            else:
                raise

    async def _consume_loop(self) -> None:
        """Main consumption loop reading from the Redis Stream."""
        while self._running:
            try:
                # Read new messages
                response = await self._redis.xreadgroup(
                    groupname=self._group,
                    consumername=self._consumer_name,
                    streams={self._stream: ">"},
                    count=1,
                    block=settings.poll_timeout_ms,
                )

                if not response:
                    # No new messages — check for pending messages
                    await self._process_pending()
                    continue

                for stream_name, messages in response:
                    for msg_id, fields in messages:
                        await self._process_message(msg_id, fields)

            except asyncio.CancelledError:
                logger.info("worker.cancelled")
                break
            except Exception as exc:
                logger.error("worker.loop_error", error=str(exc))
                self._errors += 1
                await asyncio.sleep(settings.worker_poll_interval_sec)

    async def _process_pending(self) -> None:
        """Reclaim and process pending messages from crashed workers."""
        try:
            response = await self._redis.xautoclaim(
                self._stream,
                self._group,
                self._consumer_name,
                min_idle_time=60000,  # 60s before reclaiming
                start_id="0-0",
                count=1,
            )
            if response and response[1]:
                for msg_id, fields in response[1]:
                    logger.info("worker.reclaimed", msg_id=msg_id)
                    await self._process_message(msg_id, fields)
        except Exception as exc:
            logger.debug("worker.no_pending", error=str(exc))

    async def _process_message(self, msg_id: str, fields: dict) -> None:
        """Process a single recitation job message."""
        session_id = fields.get("session_id", "")
        logger.info("worker.processing", msg_id=msg_id, session_id=session_id)
        self._processed += 1

        try:
            # --- Update session status to processing ---
            await self._redis.hset(
                f"qari:recitation:session:{session_id}",
                mapping={
                    "status": "processing",
                    "processing_started_at": datetime.now(timezone.utc).isoformat(),
                },
            )

            # Publish progress
            await self._publish_progress(session_id, {
                "session_id": session_id,
                "status": "processing",
                "progress_pct": 0.0,
                "processed_words": 0,
            })

            # --- Run inference (returns a mobile-shaped result dict) ---
            result = await self._inference(fields)

            # --- Persist the full analysis result blob ---
            now = datetime.now(timezone.utc).isoformat()
            await self._redis.set(
                RESULT_KEY.format(session_id=session_id),
                json.dumps(result, default=str),
                ex=86400,
            )

            word_verdicts = result.get("word_verdicts", [])
            await self._redis.hset(
                f"qari:recitation:session:{session_id}",
                mapping={
                    "status": "completed",
                    "completed_at": now,
                },
            )

            # --- Publish final result ---
            await self._publish_progress(session_id, {
                "session_id": session_id,
                "status": "completed",
                "progress_pct": 100.0,
                "processed_words": len(word_verdicts),
                "total_words": len(word_verdicts),
                "word_verdicts": word_verdicts,
                "result": result,
            })

            # --- Acknowledge the message ---
            await self._redis.xack(self._stream, self._group, msg_id)

            logger.info(
                "worker.completed",
                msg_id=msg_id,
                session_id=session_id,
                words=len(word_verdicts),
                overall_score=result.get("overall_score"),
            )

        except Exception as exc:
            logger.error("worker.processing_error", msg_id=msg_id, session_id=session_id, error=str(exc))
            self._errors += 1

            # --- Mark session as failed ---
            await self._redis.hset(
                f"qari:recitation:session:{session_id}",
                mapping={
                    "status": "failed",
                    "error_message": str(exc)[:500],
                    "completed_at": datetime.now(timezone.utc).isoformat(),
                },
            )

            # --- Publish failure ---
            await self._publish_progress(session_id, {
                "session_id": session_id,
                "status": "failed",
                "error_message": str(exc)[:500],
            })

            # --- Acknowledge to avoid reprocessing ---
            await self._redis.xack(self._stream, self._group, msg_id)

    async def _publish_progress(self, session_id: str, data: dict) -> None:
        """Publish a progress update to the session's Pub/Sub channel."""
        channel = settings.recitation_results_channel.format(session_id=session_id)
        try:
            await self._redis.publish(channel, json.dumps(data, default=str))
        except Exception as exc:
            logger.warning("worker.publish_failed", session_id=session_id, error=str(exc))


# ---------------------------------------------------------------------------
# Entry point for running the worker as a standalone process
# ---------------------------------------------------------------------------

def _select_default_inference() -> InferenceCallback:
    """Pick the default inference callback.

    Uses the real ML pipeline unless ``QARI_ML_USE_STUB=true`` (local dev
    without GPU/model weights).
    """
    if settings.ml_use_stub:
        logger.info("worker.using_stub")
        return _default_inference
    return run_ml_inference


async def run_worker() -> None:
    """Run the inference worker. Entry point for `python -m app.workers.inference_worker`."""
    worker = InferenceWorker()
    try:
        await worker.start()
    except KeyboardInterrupt:
        await worker.stop()


if __name__ == "__main__":
    asyncio.run(run_worker())
