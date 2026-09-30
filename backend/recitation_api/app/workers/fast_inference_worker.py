"""Fast production worker for uploaded Quran recitation analysis.

The original research pipeline lazily downloads/loads Hugging Face Whisper,
Silero VAD and a Wav2Vec2 forced aligner. On a CPU VPS that can take several
minutes (or stall completely when outbound model downloads are unavailable),
while the mobile client gives up polling after two minutes.

This worker keeps the same Redis job/result contract but uses the local
CTranslate2 INT8 verification model already deployed for live recitation. It
uses a network-free RMS speech gate and retains the independent recognizer's
word timestamps without loading the prototype forced-alignment model.

Production scoring is intentionally conservative:
* only rows backed by an expected Quran reference word are returned;
* ASR-only insertions/hallucinations never increase the displayed word count;
* the overall score is the reference-word match ratio, not the research
  pipeline's provisional tajweed-weighted score;
* pronunciation, fluency and tajweed are explicitly unavailable: text matching
  and recognizer confidence do not measure these acoustic properties.
"""

from __future__ import annotations

import asyncio
import os
import time
from dataclasses import dataclass
from typing import Optional

import numpy as np

from app.core.config import settings
from app.core.logging import get_logger
from app.workers.inference_worker import (
    InferenceWorker,
    _build_reference_audio_url,
    _build_result_dict,
    _ensure_reference,
    _get_reference_store,
    _load_audio,
)

logger = get_logger(__name__)

BATCH_ANALYSIS_TIMEOUT_SEC = int(
    os.environ.get("QARI_BATCH_ANALYSIS_TIMEOUT_SEC", "90")
)
MIN_SPEECH_RMS = float(os.environ.get("QARI_BATCH_MIN_SPEECH_RMS", "0.006"))
MIN_ACTIVE_SPEECH_SEC = float(
    os.environ.get("QARI_BATCH_MIN_ACTIVE_SPEECH_SEC", "0.25")
)
WORD_CONFIDENCE_THRESHOLD = float(
    os.environ.get("QARI_BATCH_WORD_CONFIDENCE_THRESHOLD", "0.50")
)

# Numeric placeholders preserve the legacy 0..1 wire contract. Availability
# fields distinguish an unsupported metric from an evaluated zero score.
UNAVAILABLE_SCORE = 0.0


class FasterWhisperASRAdapter:
    """Expose the local Faster-Whisper model through ``QuranASR``'s interface."""

    def __init__(self) -> None:
        from ml.inference.faster_whisper_transcriber import get_transcriber
        self._transcriber = get_transcriber()

    def transcribe(self, audio, sample_rate: int = 16000):
        from ml.inference.asr import ASRResult, ASRToken, normalize_arabic

        started = time.perf_counter()
        words, confidences, starts, ends = self._transcriber.transcribe_independent_with_timings(
            audio, sample_rate
        )

        tokens: list[ASRToken] = []
        raw_words: list[str] = []
        normalized_words: list[str] = []
        for index, raw_word in enumerate(words):
            normalized = normalize_arabic(raw_word)
            if not normalized:
                continue
            confidence = float(confidences[index]) if index < len(confidences) else 0.0
            start_ms = starts[index] if index < len(starts) else 0
            end_ms = ends[index] if index < len(ends) else start_ms
            for normalized_word in normalized.split():
                raw_words.append(raw_word.strip())
                normalized_words.append(normalized_word)
                tokens.append(
                    ASRToken(
                        text=raw_word.strip(),
                        normalized=normalized_word,
                        start_time=start_ms / 1000.0,
                        end_time=end_ms / 1000.0,
                        confidence=confidence,
                    )
                )

        return ASRResult(
            raw_text=" ".join(raw_words),
            normalized_text=" ".join(normalized_words),
            tokens=tokens,
            language="ar",
            model_id=self._transcriber.verify_model_dir,
            processing_time_s=time.perf_counter() - started,
        )


@dataclass
class BatchWordMatch:
    reference: Optional[str]
    hypothesis: Optional[str]
    verdict: str
    confidence: float
    start_ms: Optional[int]
    end_ms: Optional[int]


@dataclass
class BatchWordMatchResult:
    words: list[BatchWordMatch]
    reference_audio_url: str


class BatchWordMatchingPipeline:
    """Compare independently heard words with a reference after decoding.

    No expected text enters ASR. No acoustic checks or confidence values are
    derived from uniformly estimated reference-word timestamps.
    """

    def __init__(self, reference_store, asr) -> None:
        from ml.alignment.word_alignment import WordAligner

        self.reference_store = reference_store
        self.asr = asr
        self._word_aligner = WordAligner()

    def analyze(
        self, audio, sample_rate, surah, ayah, session_id, *, user_audio_url=""
    ) -> BatchWordMatchResult:
        reference = self.reference_store.get(surah, ayah)
        if reference is None:
            raise ValueError(f"No reference data for surah {surah}, ayah {ayah}")

        transcription = self.asr.transcribe(audio, sample_rate)
        alignment = self._word_aligner.align(
            reference.expected_words,
            transcription.normalized_words,
            confidences=[token.confidence for token in transcription.tokens],
        )
        words = []
        for aligned in alignment.aligned_words:
            token = (
                transcription.tokens[aligned.hyp_index]
                if aligned.hyp_index is not None
                else None
            )
            words.append(BatchWordMatch(
                reference=aligned.reference,
                hypothesis=aligned.hypothesis,
                verdict=aligned.verdict.value,
                confidence=token.confidence if token is not None else 0.0,
                start_ms=round(token.start_time * 1000) if token is not None else None,
                end_ms=round(token.end_time * 1000) if token is not None else None,
            ))
        return BatchWordMatchResult(
            words=words, reference_audio_url=reference.reference_audio_url
        )


_pipeline = None


def _get_fast_pipeline():
    global _pipeline
    if _pipeline is None:
        store = _get_reference_store()
        if store is None:
            raise RuntimeError("Reference store unavailable — cannot run inference")

        _pipeline = BatchWordMatchingPipeline(
            reference_store=store,
            asr=FasterWhisperASRAdapter(),
        )
        logger.info(
            "fast_worker.pipeline_ready",
            model_dir=_pipeline.asr._transcriber.verify_model_dir,
            speech_gate="rms",
            word_timestamps="independent_asr",
        )
    return _pipeline


def _speech_activity(audio: np.ndarray, sample_rate: int) -> tuple[float, float]:
    samples = np.asarray(audio, dtype=np.float32).reshape(-1)
    if samples.size == 0 or sample_rate <= 0:
        return 0.0, 0.0

    whole_rms = float(np.sqrt(np.mean(np.square(samples, dtype=np.float64))))
    frame_size = max(1, int(sample_rate * 0.03))
    active_frames = 0
    for start in range(0, samples.size, frame_size):
        frame = samples[start : start + frame_size]
        if frame.size < frame_size // 2:
            continue
        frame_rms = float(np.sqrt(np.mean(np.square(frame, dtype=np.float64))))
        if frame_rms >= MIN_SPEECH_RMS:
            active_frames += 1
    return active_frames * frame_size / sample_rate, whole_rms


def _public_user_audio_url(session_id: str, fallback: Optional[str]) -> Optional[str]:
    public_base = settings.recitation_api_public_url.rstrip("/")
    if public_base:
        return f"{public_base}/v1/recitations/{session_id}/audio"
    return fallback


def _reference_only_verdicts(
    word_results,
    *,
    start_index: int,
    reference_audio_url: Optional[str],
    user_audio_url: Optional[str],
) -> tuple[list[dict], int, int, list[float]]:
    verdicts: list[dict] = []
    correct_count = 0
    confidences: list[float] = []
    next_index = start_index

    for word_result in word_results:
        expected = word_result.reference
        if not expected:
            logger.info(
                "fast_worker.ignore_asr_insertion",
                hypothesis=word_result.hypothesis,
                confidence=round(float(word_result.confidence), 3),
            )
            continue

        confidence = float(word_result.confidence)
        confidences.append(confidence)
        is_uncertain = (
            word_result.verdict == "low_confidence"
            or (word_result.hypothesis is not None and confidence < WORD_CONFIDENCE_THRESHOLD)
        )
        is_correct = word_result.verdict == "correct" and not is_uncertain
        if is_correct:
            correct_count += 1

        if is_correct:
            error_type = None
            error_description = None
        elif is_uncertain:
            error_type = "recognition_uncertain"
            error_description = (
                "The speech recognizer was not confident about this word. "
                "Please retry; this is not a confirmed pronunciation error."
            )
        else:
            error_type = word_result.verdict
            error_description = (
                "The independent recognizer did not hear this expected word."
                if word_result.hypothesis is None
                else "The independently recognized word differs from the reference."
            )

        verdicts.append(
            {
                "word": expected,
                "word_index": next_index,
                "is_correct": is_correct,
                "confidence": confidence,
                "expected_text": expected,
                "actual_text": word_result.hypothesis,
                "start_ms": getattr(word_result, "start_ms", None),
                "end_ms": getattr(word_result, "end_ms", None),
                "error_type": error_type,
                "error_description": error_description,
                "reference_audio_url": reference_audio_url,
                "user_audio_url": user_audio_url,
                "phoneme_errors": [],
            }
        )
        next_index += 1

    return verdicts, next_index, correct_count, confidences


async def run_fast_ml_inference(job: dict) -> dict:
    session_id = job.get("session_id", "")
    surah = int(job.get("surah_number", 1))
    ayah_from = int(job.get("ayah_from", 1))
    ayah_to = int(job.get("ayah_to", ayah_from))
    qari_id = job.get("qari_id")
    audio_path = job.get("audio_path")
    duration_sec = int(round(float(job.get("audio_duration_sec", 0))))
    user_audio_url = _public_user_audio_url(session_id, audio_path)

    if not audio_path or not os.path.exists(audio_path):
        raise ValueError(f"Audio file missing for session {session_id}")

    audio, sample_rate = _load_audio(audio_path)
    active_seconds, rms = _speech_activity(audio, sample_rate)
    if active_seconds < MIN_ACTIVE_SPEECH_SEC:
        logger.info(
            "fast_worker.no_speech",
            session_id=session_id,
            active_seconds=round(active_seconds, 3),
            rms=round(rms, 6),
        )
        return _build_result_dict(
            job=job,
            session_id=session_id,
            surah=surah,
            ayah=ayah_from,
            overall=0.0,
            pronunciation=0.0,
            tajweed=UNAVAILABLE_SCORE,
            fluency=0.0,
            accuracy=0.0,
            word_verdicts=[],
            reference_audio_url=None,
            user_audio_url=user_audio_url,
            feedback="No recitation was detected. Move closer to the microphone and try again.",
            feedback_urdu=None,
            duration_seconds=duration_sec,
            confidence=0.0,
        )

    pipeline = _get_fast_pipeline()
    word_verdicts: list[dict] = []
    global_index = 0
    evaluated_ayahs = 0
    correct_reference_words = 0
    reference_word_count = 0
    result_confidences: list[float] = []
    reference_audio_url: Optional[str] = None
    ignored_insertions = 0

    for ayah in range(ayah_from, ayah_to + 1):
        if not _ensure_reference(surah, ayah, qari_id):
            logger.warning(
                "fast_worker.skip_ayah_no_ref",
                session_id=session_id,
                surah=surah,
                ayah=ayah,
            )
            continue

        try:
            ml_result = await asyncio.wait_for(
                asyncio.to_thread(
                    pipeline.analyze,
                    audio,
                    sample_rate,
                    surah,
                    ayah,
                    session_id,
                    user_audio_url=user_audio_url or "",
                ),
                timeout=BATCH_ANALYSIS_TIMEOUT_SEC,
            )
        except asyncio.TimeoutError as exc:
            raise TimeoutError(
                f"Analysis exceeded {BATCH_ANALYSIS_TIMEOUT_SEC}s for {surah}:{ayah}"
            ) from exc

        evaluated_ayahs += 1
        ignored_insertions += sum(1 for row in ml_result.words if not row.reference)
        ayah_reference_url = (
            ml_result.reference_audio_url
            or _build_reference_audio_url(surah, ayah)
        )
        if reference_audio_url is None:
            reference_audio_url = ayah_reference_url

        ayah_verdicts, global_index, ayah_correct, ayah_confidences = (
            _reference_only_verdicts(
                ml_result.words,
                start_index=global_index,
                reference_audio_url=ayah_reference_url,
                user_audio_url=user_audio_url,
            )
        )
        word_verdicts.extend(ayah_verdicts)
        correct_reference_words += ayah_correct
        reference_word_count += len(ayah_verdicts)
        result_confidences.extend(ayah_confidences)

    if evaluated_ayahs == 0 or reference_word_count == 0:
        return _build_result_dict(
            job=job,
            session_id=session_id,
            surah=surah,
            ayah=ayah_from,
            overall=0.0,
            pronunciation=0.0,
            tajweed=UNAVAILABLE_SCORE,
            fluency=0.0,
            accuracy=0.0,
            word_verdicts=[],
            reference_audio_url=None,
            user_audio_url=user_audio_url,
            feedback="We couldn't analyse this recitation with enough confidence.",
            feedback_urdu=None,
            duration_seconds=duration_sec,
            confidence=0.0,
        )

    word_match_score = correct_reference_words / reference_word_count
    average_confidence = (
        sum(result_confidences) / len(result_confidences)
        if result_confidences
        else 0.0
    )

    uncertain_count = sum(
        1
        for verdict in word_verdicts
        if verdict.get("error_type") == "recognition_uncertain"
    )
    if uncertain_count:
        feedback = (
            f"{uncertain_count} word(s) were uncertain. They are not confirmed "
            "pronunciation errors. Tajweed scoring is not available in fast mode."
        )
    else:
        feedback = (
            "Word matching complete. Tap red words to compare the recognized "
            "word with the reference. Tajweed scoring is not available in fast mode."
        )

    logger.info(
        "fast_worker.reference_scoring",
        session_id=session_id,
        correct=correct_reference_words,
        reference_words=reference_word_count,
        ignored_insertions=ignored_insertions,
        word_match_score=round(word_match_score, 4),
        average_confidence=round(average_confidence, 4),
    )

    return _build_result_dict(
        job=job,
        session_id=session_id,
        surah=surah,
        ayah=ayah_from,
        overall=word_match_score,
        pronunciation=UNAVAILABLE_SCORE,
        tajweed=UNAVAILABLE_SCORE,
        fluency=UNAVAILABLE_SCORE,
        accuracy=word_match_score,
        word_verdicts=word_verdicts,
        reference_audio_url=reference_audio_url,
        user_audio_url=user_audio_url,
        feedback=feedback,
        feedback_urdu=None,
        duration_seconds=duration_sec,
        confidence=average_confidence,
    )


async def run_worker() -> None:
    worker = InferenceWorker(inference_callback=run_fast_ml_inference)
    try:
        await worker.start()
    except KeyboardInterrupt:
        await worker.stop()


if __name__ == "__main__":
    asyncio.run(run_worker())
