"""Faster-Whisper CTranslate2 transcriber for live Quran recitation."""

from __future__ import annotations

import logging
import os
import threading
from typing import List, Optional, Tuple

logger = logging.getLogger(__name__)

DEFAULT_MODEL_DIR = "/app/models/qari-ct2-tiny-robust-v2"
ENV_MODEL_DIR = "QARI_FASTERWHISPER_MODEL_DIR"
# Independent VERIFICATION model (unprompted). The Qari V50/QARI adapter is an
# ORACLE model: it was trained to reproduce the expected text given as prompt
# (trained "prompted WER 0.0065"), so on audio that does NOT match the prompt it
# still emits the prompt — verified on this VPS: with Al-Fatiha as the prompt it
# recited the whole Fatiha while the audio was a different recitation. Using it
# to validate the user's recitation therefore always "passes". The base Quran
# ASR model, decoded WITHOUT a prompt, transcribes only what is actually heard
# (verified: bismillah audio -> "بسم الله الرحمن الرحيم"; the same audio prompted
# with Fatiha -> Fatiha ayah 2+). That is the honest evidence the live matcher
# needs to show real mistakes.
ENV_VERIFY_MODEL_DIR = "QARI_FASTERWHISPER_VERIFY_MODEL_DIR"
DEFAULT_VERIFY_DIRNAME = "qari-ct2-base"

# Decode token caps. Whisper on short windows occasionally falls into a
# repetition loop; each repeat costs decode time AND pollutes the hypothesis.
# Measured on the VPS: an unprompted 7.5s window ran 22 tokens in 2.87s, while
# the same window capped at 48 tokens finished in 1.09s with the real words
# (live-reveal latency ~4x lower). Prompted decodes are well-behaved but get a
# generous safety cap so a loop can never stall the live loop.
PROMPTED_MAX_NEW_TOKENS = 96
UNPROMPTED_MAX_NEW_TOKENS = 64


def resolve_model_dir(explicit: Optional[str] = None) -> str:
    return explicit or os.environ.get(ENV_MODEL_DIR, DEFAULT_MODEL_DIR)


def _word_probability(word) -> float:
    """Preserve a genuine 0.0 probability; only missing values default to 1."""
    value = getattr(word, "probability", None)
    return 1.0 if value is None else float(value)


class FasterWhisperTranscriber:
    """Thin, lazy and thread-safe wrapper around ``WhisperModel``."""

    def _resolve_verify_dir(self) -> str:
        explicit = os.environ.get(ENV_VERIFY_MODEL_DIR)
        if explicit:
            return explicit
        if self.model_dir:
            candidate = os.path.join(
                os.path.dirname(self.model_dir), DEFAULT_VERIFY_DIRNAME
            )
            if os.path.isdir(candidate):
                return candidate
        return os.path.join(os.path.dirname(DEFAULT_MODEL_DIR), DEFAULT_VERIFY_DIRNAME)

    def __init__(
        self,
        model_dir: Optional[str] = None,
        device: str = "cpu",
        compute_type: str = "int8",
        cpu_threads: Optional[int] = None,
    ) -> None:
        self.model_dir = resolve_model_dir(model_dir)
        self.device = device
        self.compute_type = compute_type
        self.cpu_threads = cpu_threads or int(
            os.environ.get("QARI_FASTERWHISPER_THREADS") or (os.cpu_count() or 2)
        )
        self._model = None
        # Separate instance for UNPROMPTED decodes. The live session runs the
        # prompted (tier-1) and unprompted (tier-2) decodes CONCURRENTLY, and
        # CTranslate2 serializes concurrent calls on the SAME model instance
        # (measured: 3.15s shared vs 1.96s with two instances at 2 threads
        # each). Lazily created — only streaming unprompted calls need it.
        self._model_raw = None
        # Independent verification decode (see ENV_VERIFY_MODEL_DIR).
        self.verify_model_dir = self._resolve_verify_dir()
        self._model_verify = None
        self._lock = threading.Lock()

    def _build_model(self):
        from faster_whisper import WhisperModel

        return WhisperModel(
            self.model_dir,
            device=self.device,
            compute_type=self.compute_type,
            cpu_threads=self.cpu_threads,
        )

    def load(self) -> None:
        if self._model is not None:
            return
        logger.info(
            "Loading Faster-Whisper (%s, %d threads) from %s",
            self.compute_type,
            self.cpu_threads,
            self.model_dir,
        )
        with self._lock:
            if self._model is None:
                self._model = self._build_model()
        logger.info("Faster-Whisper model loaded")

    def _model_for(self, prompted: bool):
        """Return the model instance to decode with.

        Prompted decodes use the primary instance; unprompted ones get their
        own so both can execute in parallel (see ``_model_raw``).
        """
        if prompted:
            self.load()
            return self._model
        if self._model_raw is None:
            with self._lock:
                if self._model_raw is None:
                    self._model_raw = self._build_model()
                    logger.info("Faster-Whisper RAW (unprompted) model loaded")
        return self._model_raw

    def _model_verify_for(self):
        """Lazily build the independent (base, unprompted) verification model."""
        if self._model_verify is None:
            with self._lock:
                if self._model_verify is None:
                    from faster_whisper import WhisperModel

                    logger.info(
                        "Loading verification model from %s", self.verify_model_dir
                    )
                    self._model_verify = WhisperModel(
                        self.verify_model_dir,
                        device=self.device,
                        compute_type=self.compute_type,
                        cpu_threads=self.cpu_threads,
                    )
                    logger.info("Verification model loaded")
        return self._model_verify

    def transcribe_independent(
        self, audio, sample_rate: int = 16000
    ) -> Tuple[List[str], List[float]]:
        """UNPROMPTED decode with the independent base model.

        This is the honest witness: no expected text goes in, so the output is
        whatever the reciter actually said (the V50 oracle model cannot be used
        for this — it echoes the prompt).
        """
        samples = self._prepare_audio(audio, sample_rate)
        if len(samples) == 0:
            return [], []
        model = self._model_verify_for()
        segments, _info = model.transcribe(
            samples,
            language="ar",
            task="transcribe",
            beam_size=1,
            word_timestamps=False,
            vad_filter=False,
            temperature=0.0,
            condition_on_previous_text=False,
            initial_prompt=None,
            max_new_tokens=UNPROMPTED_MAX_NEW_TOKENS,
        )
        words: List[str] = []
        confidences: List[float] = []
        for segment in segments:
            text = (getattr(segment, "text", None) or "").strip()
            if not text:
                continue
            conf = self._segment_confidence(segment)
            for token in text.split():
                words.append(token)
                confidences.append(conf)
        return words, confidences

    def is_loaded(self) -> bool:
        return self._model is not None

    def transcribe_independent_with_timings(
        self, audio, sample_rate: int = 16000
    ) -> Tuple[List[str], List[float], List[int], List[int]]:
        """Return timestamped evidence from the independent, unprompted model.

        Expected Quran text is deliberately not an argument. If verification
        weights are unavailable the call raises; a prompt-conditioned model
        cannot substitute for independent evidence.
        """
        samples = self._prepare_audio(audio, sample_rate)
        if len(samples) == 0:
            return [], [], [], []
        segments, _info = self._model_verify_for().transcribe(
            samples,
            language="ar",
            task="transcribe",
            beam_size=1,
            word_timestamps=True,
            vad_filter=False,
            temperature=0.0,
            condition_on_previous_text=False,
            initial_prompt=None,
            max_new_tokens=UNPROMPTED_MAX_NEW_TOKENS,
        )
        words: List[str] = []
        confidences: List[float] = []
        starts: List[int] = []
        ends: List[int] = []
        for segment in segments:
            for word in getattr(segment, "words", None) or []:
                text = (getattr(word, "word", None) or "").strip()
                if not text:
                    continue
                words.append(text)
                probability = getattr(word, "probability", None)
                confidences.append(0.0 if probability is None else float(probability))
                starts.append(int(float(getattr(word, "start", 0.0) or 0.0) * 1000))
                ends.append(int(float(getattr(word, "end", 0.0) or 0.0) * 1000))
        return words, confidences, starts, ends

    @staticmethod
    def _prepare_audio(audio, sample_rate: int):
        import numpy as np

        if audio is None or len(audio) == 0:
            return np.asarray([], dtype=np.float32)
        samples = np.asarray(audio, dtype=np.float32)
        if sample_rate != 16000:
            import librosa

            samples = librosa.resample(
                samples, orig_sr=sample_rate, target_sr=16000
            ).astype(np.float32)
        return samples

    def _decode(
        self,
        samples,
        initial_prompt: str = "",
        *,
        word_timestamps: bool = True,
        max_new_tokens: Optional[int] = None,
    ):
        """Decode audio. ``initial_prompt`` = expected ayah text (tashkeel) —
        the ORACLE prompt our prompt-conditioned LoRA model (V50) was trained
        with (WER 0.0065 prompted vs 6.8 unprompted). Without it the decoder
        free-runs and falls into repetition loops on real recitation.

        ``word_timestamps``: measured on this VPS, cross-attention DTW
        timestamps cost ~6x decode time (RTF 1.59 vs 0.25 on the 6s window).
        The live streaming path disables them (the matcher needs words, not
        word-level timings); the batch path keeps them for result metadata.
        """
        if max_new_tokens is None:
            max_new_tokens = (
                PROMPTED_MAX_NEW_TOKENS
                if initial_prompt
                else UNPROMPTED_MAX_NEW_TOKENS
            )
        return self._model_for(bool(initial_prompt)).transcribe(
            samples,
            language="ar",
            task="transcribe",
            beam_size=1,
            word_timestamps=word_timestamps,
            vad_filter=False,
            temperature=0.0,
            condition_on_previous_text=False,
            initial_prompt=initial_prompt or None,
            max_new_tokens=max_new_tokens,
        )

    @staticmethod
    def _segment_confidence(segment) -> float:
        """Convert a segment's ``avg_logprob`` into a [0, 1] pseudo-probability.

        Used on the live path where ``word_timestamps=False`` leaves no
        per-word probabilities. Confident Arabic speech sits around
        avg_logprob -0.05..-0.4 → exp() maps it to ~0.67..0.96, comfortably
        above the streaming matcher's 0.55 live threshold.
        """
        import math

        lp = getattr(segment, "avg_logprob", None)
        if lp is None:
            return 1.0
        try:
            return max(0.0, min(1.0, math.exp(float(lp))))
        except (ValueError, OverflowError):
            return 1.0

    def transcribe(
        self, audio, sample_rate: int = 16000, initial_prompt: str = ""
    ) -> Tuple[List[str], List[float]]:
        self.load()
        # Ensure the instance this call will use exists BEFORE decoding so
        # concurrent tier-1/tier-2 calls never race on model construction.
        self._model_for(bool(initial_prompt))
        samples = self._prepare_audio(audio, sample_rate)
        if len(samples) == 0:
            return [], []
        # Live path: word_timestamps=False (6x faster decode — see _decode).
        segments, _info = self._decode(samples, initial_prompt, word_timestamps=False)
        words: List[str] = []
        confidences: List[float] = []
        for segment in segments:
            seg_words = getattr(segment, "words", None) or []
            if seg_words:
                for word in seg_words:
                    text = (getattr(word, "word", None) or "").strip()
                    if text:
                        words.append(text)
                        confidences.append(_word_probability(word))
                continue
            # No word timings: split the segment text (Arabic script is
            # space-delimited) and share the segment-level confidence.
            text = (getattr(segment, "text", None) or "").strip()
            if not text:
                continue
            conf = self._segment_confidence(segment)
            for token in text.split():
                words.append(token)
                confidences.append(conf)
        return words, confidences

    def transcribe_with_timings(
        self, audio, sample_rate: int = 16000, initial_prompt: str = ""
    ) -> Tuple[List[str], List[float], List[int], List[int]]:
        self.load()
        samples = self._prepare_audio(audio, sample_rate)
        if len(samples) == 0:
            return [], [], [], []
        segments, _info = self._decode(samples, initial_prompt)
        words: List[str] = []
        confidences: List[float] = []
        starts: List[int] = []
        ends: List[int] = []
        for segment in segments:
            for word in getattr(segment, "words", None) or []:
                text = (getattr(word, "word", None) or "").strip()
                if not text:
                    continue
                words.append(text)
                confidences.append(_word_probability(word))
                starts.append(int(float(getattr(word, "start", 0.0) or 0.0) * 1000))
                ends.append(int(float(getattr(word, "end", 0.0) or 0.0) * 1000))
        return words, confidences, starts, ends


_transcriber_singleton: Optional[FasterWhisperTranscriber] = None
_transcriber_lock = threading.Lock()


def get_transcriber() -> FasterWhisperTranscriber:
    global _transcriber_singleton
    if _transcriber_singleton is None:
        with _transcriber_lock:
            if _transcriber_singleton is None:
                _transcriber_singleton = FasterWhisperTranscriber()
    return _transcriber_singleton
