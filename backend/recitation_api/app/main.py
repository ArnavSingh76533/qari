"""FastAPI application for the Qari recitation_api service."""

import os
import threading
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncIterator

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest, Counter, Histogram, Gauge

from app.api.router import api_router
from app.core.config import settings
from app.core.logging import get_logger, setup_logging

# Compatibility guard for the live session's silence gate. The RMS helper is a
# module-level function, while the streaming code calls it through the session
# instance. Bind it as a static method at import time so production live ASR
# does not fail every pass with AttributeError. This is deliberately centralized
# here until the streaming service is split into smaller units.
from app.services import streaming_session as _streaming_session

if not hasattr(_streaming_session.StreamingRecitationSession, "_rms_energy"):
    _streaming_session.StreamingRecitationSession._rms_energy = staticmethod(
        _streaming_session._rms_energy
    )

# Final-session silence guard. The live sliding-window path already skips quiet
# windows, but finalize() previously performed a full-audio Whisper pass whenever
# no hypothesis existed. That made 20+ seconds of room tone hallucinate Arabic
# words and produce misleading red-word verdicts. Require sustained activity
# before any final ASR/tajweed work is allowed.
_FINAL_FRAME_SECONDS = 0.03
_FINAL_MIN_ACTIVE_SECONDS = 0.45
_FINAL_MIN_CONTIGUOUS_SECONDS = 0.12

# A live tick should only run Whisper when the NEW audio received since the last
# tick contains sustained activity. Checking the whole overlapping 6-second
# window lets the same two spoken words keep triggering several later passes
# after the user becomes silent, and each pass can append new hallucinations.
_LIVE_MIN_NEW_ACTIVE_SECONDS = 0.12
_LIVE_MIN_NEW_CONTIGUOUS_SECONDS = 0.06

# A normal Quran recitation is commonly around two to three words per second.
# Cap live reveal progress by measured active speech so a language-model
# continuation cannot reveal an entire page after the user says only a few words.
_LIVE_MAX_WORDS_PER_ACTIVE_SECOND = 2.4
_LIVE_MIN_WORD_CONFIDENCE = 0.35


def _speech_activity_seconds(
    samples: list[float],
    sample_rate: int,
    *,
    threshold: float = _streaming_session.SILENCE_RMS_THRESHOLD,
) -> tuple[float, float]:
    """Return total and longest contiguous above-threshold frame duration."""
    if not samples or sample_rate <= 0:
        return 0.0, 0.0

    frame_size = max(1, int(sample_rate * _FINAL_FRAME_SECONDS))
    active_frames = 0
    current_run = 0
    longest_run = 0

    for start in range(0, len(samples), frame_size):
        frame = samples[start : start + frame_size]
        if len(frame) < max(1, frame_size // 2):
            continue
        rms = (sum(value * value for value in frame) / len(frame)) ** 0.5
        if rms >= threshold:
            active_frames += 1
            current_run += 1
            longest_run = max(longest_run, current_run)
        else:
            current_run = 0

    frame_seconds = frame_size / sample_rate
    return active_frames * frame_seconds, longest_run * frame_seconds


class _ConservativeLiveMatcher:
    """Production live matcher: DP word alignment bounded by speech duration.

    Two independent guards keep the live reveal honest and in sync with the
    voice:

    * **Alignment** delegates to ``StreamingMatcher``'s live DP aligner (anchor +
      local window, Needleman-Wunsch — the approach Tarteel documents for its own
      app). The previous implementation here walked ASR tokens one at a time with
      ``lookahead=0``, consuming every unmatched token as noise: as soon as the
      expected word's own token was missing (window-cut fragment, mangled
      article, a swallowed word) it ate everything after it and NEVER advanced
      again, so the reveal froze for the rest of the surah (verified live at the
      ayah-6 -> 7 boundary: cursor pinned at 20/29 while the user kept
      reciting). The DP re-aligns the recent window every pass and skips past a
      lost word instead of jamming.
    * **Budget**: ``max_live_words`` caps the reveal at the number of words that
      could have been spoken in the measured active-speech time, so an ASR
      continuation can never highlight text the user has not recited yet.

    Detailed errors are still produced at final review by a fresh matcher.
    """

    def __init__(self, reference_words: list[str]) -> None:
        from ml.alignment.streaming_matcher import StreamingMatcher

        self.reference = list(reference_words)
        self.lookahead = 0
        self.max_live_words = 0
        self._cursor = 0
        self._hyp_cursor = 0
        self._states = []
        self._delegate = StreamingMatcher(self.reference)

    @property
    def _stall_passes(self) -> int:
        return getattr(self._delegate, "_stall_passes", 0)

    @property
    def _last_dp_debug(self):
        return getattr(self._delegate, "_last_dp_debug", {})

    def evaluate(self, hypothesis_words, confidences=None, *, full=False):
        limit = min(len(self.reference), max(0, int(self.max_live_words)))
        delegate = self._delegate
        # Enforce the speech-duration budget by restricting the reference the
        # aligner may see: words beyond the budget are unreachable, so they can
        # never resolve (and can never be jumped to by a mis-alignment).
        saved_reference = delegate.reference
        delegate.reference = self.reference[:limit]
        try:
            states = delegate._evaluate_live(hypothesis_words, confidences)
        finally:
            delegate.reference = saved_reference
        self._cursor = delegate._cursor
        self._hyp_cursor = delegate._hyp_cursor
        self._states = [state for state in states if state.index < limit]
        return list(self._states)

    def finalize(self, hypothesis_words, confidences=None):
        from ml.alignment.streaming_matcher import StreamingMatcher

        # Final review is allowed to report errors/skips. Use a fresh matcher so
        # conservative live decisions never contaminate the saved result.
        return StreamingMatcher(self.reference).finalize(
            hypothesis_words,
            confidences,
        )


_original_stream_load_reference = (
    _streaming_session.StreamingRecitationSession.load_reference
)


def _load_reference_with_conservative_live_matcher(self) -> None:
    _original_stream_load_reference(self)
    # Keep injected transcribers and the demo stub unchanged so unit tests and
    # explicit development flows retain their existing matcher semantics.
    if (
        self._explicit_transcriber is None
        and not self._is_stub
        and self.reference_words
    ):
        self._matcher = _ConservativeLiveMatcher(self.reference_words)
        self._qari_active_speech_seconds = 0.0


_streaming_session.StreamingRecitationSession.load_reference = (
    _load_reference_with_conservative_live_matcher
)

_original_stream_maybe_transcribe = (
    _streaming_session.StreamingRecitationSession.maybe_transcribe
)


async def _maybe_transcribe_with_recent_audio_gate(self, *, force: bool = False):
    """Gate repeated windows and cap live progress by actual active speech."""
    active_seconds = 0.0
    if not self._is_stub and not force and self.sample_rate > 0:
        total_samples = self._total_samples
        previous_samples = self._samples_at_last_transcribe
        new_samples = total_samples - previous_samples
        cadence_samples = int(
            _streaming_session.TRANSCRIBE_INTERVAL_SEC * self.sample_rate
        )

        if new_samples >= cadence_samples:
            recent_audio = self._decode_float(
                start_sample=previous_samples,
                end_sample=total_samples,
            )
            active_seconds, longest_active_seconds = _speech_activity_seconds(
                recent_audio,
                self.sample_rate,
            )
            has_new_speech = (
                active_seconds >= _LIVE_MIN_NEW_ACTIVE_SECONDS
                and longest_active_seconds >= _LIVE_MIN_NEW_CONTIGUOUS_SECONDS
            )
            if not has_new_speech:
                # Consume this quiet interval so the next tick examines only
                # genuinely new samples rather than repeatedly seeing the same
                # earlier speech in the overlapping ASR window.
                self._samples_at_last_transcribe = total_samples
                _streaming_session.logger.debug(
                    "stream.recent_audio_silent",
                    session_id=self.session_id,
                    active_seconds=round(active_seconds, 3),
                    longest_active_seconds=round(longest_active_seconds, 3),
                )
                return []

    matcher = self._matcher
    if isinstance(matcher, _ConservativeLiveMatcher):
        if active_seconds > 0:
            self._qari_active_speech_seconds = (
                getattr(self, "_qari_active_speech_seconds", 0.0)
                + active_seconds
            )
        speech_seconds = getattr(self, "_qari_active_speech_seconds", 0.0)
        matcher.max_live_words = min(
            len(self.reference_words),
            max(
                0,
                int(speech_seconds * _LIVE_MAX_WORDS_PER_ACTIVE_SECOND + 0.5),
            ),
        )

    events = await _original_stream_maybe_transcribe(self, force=force)
    if isinstance(matcher, _ConservativeLiveMatcher):
        # Production live UI reveals confirmed words only. Red mistake markers
        # belong to final review, where the full recording is considered.
        return [event for event in events if event.get("status") == "match"]
    return events


_streaming_session.StreamingRecitationSession.maybe_transcribe = (
    _maybe_transcribe_with_recent_audio_gate
)

_original_stream_finalize = _streaming_session.StreamingRecitationSession.finalize


async def _finalize_with_silence_guard(self) -> dict:
    """Return an explicit no-speech result without invoking Whisper."""
    if not self._is_stub and self._pcm:
        audio = self._decode_float()
        rms = _streaming_session._rms_energy(audio)
        active_seconds, longest_active_seconds = _speech_activity_seconds(
            audio, self.sample_rate
        )
        has_sustained_speech = (
            active_seconds >= _FINAL_MIN_ACTIVE_SECONDS
            and longest_active_seconds >= _FINAL_MIN_CONTIGUOUS_SECONDS
        )

        if not has_sustained_speech:
            audio_path = self._write_wav()
            public_base = settings.recitation_api_public_url.rstrip("/")
            user_audio_url = (
                f"{public_base}/v1/recitations/{self.session_id}/audio"
                if public_base and audio_path
                else audio_path
            )
            result = {
                "session_id": self.session_id,
                "surah_number": self.surah,
                "ayah_number": self.ayah_from,
                "overall_score": 0.0,
                "pronunciation_score": 0.0,
                "tajweed_score": 0.0,
                "tajweed_issues": [],
                "fluency_score": 0.0,
                "accuracy_score": 0.0,
                "word_verdicts": [],
                "reference_audio_url": self.reference_audio_url or None,
                "user_audio_url": user_audio_url,
                "feedback": (
                    "No recitation was detected. Move closer to the microphone "
                    "and try again."
                ),
                "feedback_urdu": None,
                "duration_seconds": int(self.duration_seconds),
                "created_at": datetime.now(timezone.utc).isoformat(),
                "confidence": 0.0,
                "no_speech_detected": True,
            }
            _streaming_session.logger.info(
                "stream.no_speech_detected",
                session_id=self.session_id,
                rms=round(rms, 6),
                active_seconds=round(active_seconds, 3),
                longest_active_seconds=round(longest_active_seconds, 3),
            )
            await self._persist(result, audio_path)
            return result

    return await _original_stream_finalize(self)


_streaming_session.StreamingRecitationSession.finalize = _finalize_with_silence_guard

setup_logging()
logger = get_logger(__name__)

REQUEST_COUNT = Counter(
    "qari_recitation_http_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)
REQUEST_LATENCY = Histogram(
    "qari_recitation_http_request_duration_seconds",
    "HTTP request latency",
    ["method", "endpoint"],
)
ACTIVE_REQUESTS = Gauge(
    "qari_recitation_http_active_requests",
    "Active HTTP requests",
)
RECITATION_QUEUED = Counter(
    "qari_recitation_queued_total",
    "Total recitation jobs queued",
)
RECITATION_COMPLETED = Counter(
    "qari_recitation_completed_total",
    "Total recitation jobs completed",
    ["status"],
)


def _warmup_ml() -> None:
    """Pre-load the reference store + ASR models in a background thread.

    Removes the cold-start penalty from the FIRST live session. Without this the
    first ``load_reference()`` pays the ``ReferenceStore`` disk build (~0.6s) and
    the first transcription pass pays the model loads (~0.8s), so the user taps
    start and stares at a frozen screen for a second or more. Runs off the event
    loop so ``/health`` and app readiness are NOT delayed.
    """
    try:
        from app.services.streaming_session import _get_reference_store

        _get_reference_store()
        logger.info("warmup.refstore_done")
    except Exception as exc:  # pragma: no cover - optional ml deps
        logger.debug("warmup.refstore_failed", error=str(exc))
    try:
        from ml.inference.faster_whisper_transcriber import get_transcriber

        transcriber = get_transcriber()
        transcriber.load()  # primary (prompted / V50) model
        transcriber._model_verify_for()  # independent verification (live witness)
        logger.info("warmup.models_done")
    except Exception as exc:  # pragma: no cover - model load failures
        logger.debug("warmup.model_failed", error=str(exc))


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    logger.info("app.starting", service=settings.app_name, version=settings.app_version)
    os.makedirs(settings.audio_storage_path, exist_ok=True)
    # Pre-warm ML assets in the background so the first live session has no
    # cold-start freeze. A daemon THREAD (not an asyncio task) so it never
    # touches the event loop or outlives it as a dangling task (which breaks
    # TestClient loop teardown with "Event loop is closed").
    threading.Thread(target=_warmup_ml, daemon=True, name="qari-ml-warmup").start()
    logger.info("app.started")
    yield
    logger.info("app.stopped")


def create_app() -> FastAPI:
    app = FastAPI(
        title="Qari Recitation API",
        description=(
            "Quran Learning App — Recitation API service "
            "(audio upload, WebSocket results, Redis Streams inference queue)"
        ),
        version=settings.app_version,
        lifespan=lifespan,
        docs_url="/docs" if not settings.is_production else None,
        redoc_url="/redoc" if not settings.is_production else None,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(api_router)

    @app.get("/health", tags=["health"])
    async def health_check():
        return {
            "status": "ok",
            "service": settings.app_name,
            "version": settings.app_version,
        }

    @app.get("/metrics", tags=["monitoring"])
    async def metrics():
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.middleware("http")
    async def metrics_middleware(request: Request, call_next):
        ACTIVE_REQUESTS.inc()
        import time

        start = time.time()
        try:
            response = await call_next(request)
            duration = time.time() - start
            REQUEST_COUNT.labels(
                method=request.method,
                endpoint=request.url.path,
                status=str(response.status_code),
            )
            REQUEST_LATENCY.labels(
                method=request.method,
                endpoint=request.url.path,
            ).observe(duration)
            return response
        finally:
            ACTIVE_REQUESTS.dec()

    return app


app = create_app()