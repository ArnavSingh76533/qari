"""Real-time streaming recitation session (Tarteel-style live tracking).

This service backs the ``/ws/recitation/stream`` WebSocket. Unlike the
upload → Redis-Stream → worker flow (batch analysis of a finished recording),
a :class:`StreamingRecitationSession` processes a **continuous audio stream**
while the user is still reciting and emits **word-by-word** match events in
real time.

Flow
----
1. The client opens the WebSocket and sends a ``start`` message (surah / ayah).
2. The session resolves the expected (reference) word list for the ayah(s).
3. The client streams raw PCM16 mono 16 kHz audio frames (binary messages).
4. Periodically the session re-transcribes the accumulated audio and feeds the
   cumulative hypothesis into a :class:`ml.alignment.streaming_matcher.StreamingMatcher`.
   Newly-resolved reference words are emitted as ``word`` events
   (matched / error / skipped).
5. On ``stop`` the session writes the full recording to disk, builds the
   mobile-shaped :class:`RecitationAnalysisResult` blob (so history + A/B
   playback keep working) and returns a ``final`` event.

The transcriber is pluggable. A lightweight duration-based stub is available
only when ``QARI_ML_USE_STUB`` is explicitly set (for tests and demos). A
missing real model must fail the session rather than awarding words merely as
time passes.
"""

from __future__ import annotations

import asyncio
import os
import struct
import uuid
import wave
from datetime import datetime, timezone
from typing import Callable, Optional

from app.core.config import settings
from app.core.logging import get_logger

logger = get_logger(__name__)

# How many seconds of *new* audio to accumulate before re-transcribing.
TRANSCRIBE_INTERVAL_SEC = 1.2
# --- Early first pass (2026-09-26): cut the first-word latency ---------------
#
# Measured decomposition of the ~2.1 s first-word latency on this 4-vCPU VPS:
#   ~1.2 s waiting for TRANSCRIBE_INTERVAL_SEC of audio to accumulate, plus
#   ~1.0-1.1 s for the unprompted decode of the 6.0+1.5 s window.
# The steady-state interval and window are NOT changed (recorded regressions:
# a 5.0 s window stalled the end of the surah, VERIFY_EVERY_N_PASSES=2 produced
# 5-13 s apparent latency). Instead ONLY the very first pass of a session is
# allowed to fire early, on a shorter window:
#
#   * EARLY_FIRST_PASS_SEC       audio required before pass #1 (was 1.2 s)
#   * EARLY_FIRST_PASS_WINDOW_S  window length for pass #1 (was 7.5 s)
#
# A shorter window also decodes faster, so this attacks BOTH terms. It applies
# once per session; the normal interval/window resume immediately afterwards.
# SAFETY: a very short window is where Whisper hallucinates, so this is gated on
# the same SILENCE_RMS_THRESHOLD check as every other pass, and the output is
# still only accepted through the unchanged matcher corroboration path.
#
# *** DEFAULT IS OFF — MEASURED NEGATIVE RESULT, DO NOT SIMPLY RE-ENABLE ***
# Enabling it made first-word latency WORSE, not better:
#     OFF : 2094 / 2119 / 2131 / 2139 / 2185 ms   (p50 ~2131)
#     ON  : 3137 / 3139 / 3142 / 3145 ms          (p50 ~3142)  <- +1.0 s WORSE
# Cause: 0.5 s of audio is below what Whisper needs to emit a usable
# transcript, so the "early" pass spends a full ~1 s decode producing nothing,
# and the real first word is pushed out by exactly that wasted decode. The
# window reduction does not help either: decode cost is independent of window
# length (measured: 7.5 s and 2.5 s windows both decode in 0.977 s) because
# Whisper pads input to 30 s internally.
#
# The ~1 s decode is a hard per-pass floor on this CPU, so there is no window /
# interval tuning that gets to 400 ms. Reaching it needs the GPU migration or a
# VAD + forced-alignment path that never runs Whisper per pass.
#
# The code and the env knobs are kept (QARI_EARLY_FIRST_PASS=1 to re-enable, and
# QARI_EARLY_FIRST_PASS_SEC to retune) so the negative result is reproducible
# rather than folklore. The loop-cadence coupling fix below is kept because it
# is correct regardless of this flag.
EARLY_FIRST_PASS = os.environ.get("QARI_EARLY_FIRST_PASS", "0").lower() in (
    "1", "true", "yes",
)
EARLY_FIRST_PASS_SEC = float(os.environ.get("QARI_EARLY_FIRST_PASS_SEC", "0.5"))
EARLY_FIRST_PASS_WINDOW_S = float(
    os.environ.get("QARI_EARLY_FIRST_PASS_WINDOW_S", "2.5")
)
# Users-perceived latency TARGET for a match, to be re-measured after the GPU
# migration. One unprompted decode of even a short window costs ~0.4-1.1 s on
# this CPU, so 400 ms is NOT achievable here today — recorded so the gap is
# explicit and re-measurable, not silently claimed.
TARGET_FIRST_WORD_MS = int(os.environ.get("QARI_TARGET_FIRST_WORD_MS", "400"))

# Stub transcriber: assumed seconds per recited word (reveals words over time).
STUB_SECONDS_PER_WORD = 0.9

# --- Sliding-window transcription (fixes unbounded live lag) ----------------
# The OLD live loop re-transcribed the ENTIRE growing audio buffer on every
# pass, so per-pass cost grew with recitation length. On a CPU VPS each Whisper
# pass already takes ~2.5-4s (base) which is slower than the 1.2s cadence, so the
# reveal fell further and further behind real time (worse with the bigger model).
#
# Instead we transcribe only a bounded WINDOW of the most recent audio each pass
# and STITCH the new words onto a cumulative `_hypothesis` list (the
# StreamingMatcher requires a cumulative hypothesis — it resumes at `_hyp_cursor`
# and never re-scans resolved words). Per-pass cost is now ~constant (bounded by
# the window length), so the reveal keeps up regardless of recitation length.
#
# The window (+ OVERLAP) controls both context and reveal latency. Tried a
# shorter 5.0s window: faster cadence but it lost the boundary-word context
# and stalled the end of the surah, so 6.0s stays. Latency is instead kept
# down by making each pass cheaper (unprompted verification runs on alternate
# passes — see _verify_every) and by the decode caps in the transcriber.
TRANSCRIBE_WINDOW_SEC = 6.0
# Run the unprompted verification decode only every N-th pass. Successive
# windows overlap heavily, so a verification set stays valid for the next
# pass; skipping the verification on alternate passes halves the average pass
# cost.
# NOTE: this MUST stay 1 in production. With N=2 the tier-2 evidence set is up
# to two passes (~4s) STALE, so a word the user has just spoken is not yet in
# it, tier-1 gets filtered as "uncorroborated" and the reveal waits for the
# next refresh — measured 5-13s apparent word latency over a full-surah
# recitation (the "words stop appearing" symptom). The concurrent tier-1 +
# tier-2 decode is ~2s, which the cadence absorbs, so fresh evidence every
# pass costs little and is what keeps the reveal tracking the voice.
VERIFY_EVERY_N_PASSES = 1
# Max already-resolved words used as the ORACLE prompt (see maybe_transcribe).
# Bounded because long prompts drift; 10 keeps the anchor local to the audio.
PROMPT_ANCHOR_WORDS = 10
# Left-overlap added to every sliding window. Without it a word straddling
# the window boundary is CUT IN HALF: the model sees only the word's tail in
# the next window and emits a broken fragment (e.g. 'ٰطَ' for 'صِرَٰطَ')
# that matches nothing — the matcher stalls and live events stop (observed
# at ayah boundaries in full-surah sessions). The overlap keeps the whole
# boundary word inside the window; stitch_hypothesis() already dedups the
# repeated tail (STITCH_MAX_OVERLAP_WORDS).
TRANSCRIBE_WINDOW_OVERLAP_SEC = 1.5
# How many not-yet-consumed hypothesis words to retain past the matcher's
# consumed prefix. Bounds repetition bursts without ever truncating the tail
# where freshly transcribed words are appended.
HYPO_TAIL_CAP = 40
# Max words of overlap to search when stitching a new window onto the cumulative
# hypothesis (drops words the previous window already contributed).
STITCH_MAX_OVERLAP_WORDS = 12

# --- Silence gating (fixes "ayah auto-completes while the user is silent") -----
# When the user is quiet, the mic still streams low-level room noise and Whisper
# frequently HALLUCINATES Arabic-looking tokens on near-silent audio. Those
# phantom words flowed into the matcher and "completed" the ayah automatically
# even though the user said nothing. We measure the RMS energy of each
# transcribed window and, when it is below this floor, treat the segment as
# silence: skip transcription entirely and emit NO word events (so nothing
# resolves until the user actually recites). 16-bit PCM normalized to [-1, 1];
# a calm room is typically ~0.002–0.01, speech is >0.02. Set conservatively low
# so only near-total silence (the user not reciting at all) is gated — quiet
# recitation must still pass through to ASR.
SILENCE_RMS_THRESHOLD = 0.006

# Verbose per-pass live diagnostics (tier-1/tier-2 words, matcher cursor, stall
# counter). Off by default — enable with QARI_STREAM_DEBUG=1 when diagnosing a
# live tracking problem, otherwise it floods the logs every ~2s per session.
STREAM_DEBUG = os.environ.get("QARI_STREAM_DEBUG", "").lower() in ("1", "true", "yes")

# Live evidence policy — WHICH decode feeds the live word reveal.
#
#   "tier2" (default): the INDEPENDENT, unprompted base decode is the live
#       hypothesis. This is the only witness that reports what the reciter
#       actually said. Measured on this VPS: 29/29 words revealed live on a real
#       Al-Fatiha recitation (repeatedly), and only 7/29 on an unrelated clip
#       (Fatiha's repeated words, textually ambiguous).
#   "corroborated": the prompt-conditioned Qari model supplies the words, kept
#       only where the independent decode agrees. Cleaner segmentation, but the
#       Qari model is an ORACLE (see _independent_transcriber): its echo of the
#       expected text passes corroboration whenever the independent decode heard
#       *any* occurrence of the same word, so it over-reveals (measured 9/29 on
#       the same unrelated clip).
#
# Live tracking therefore runs on the independent witness; the prompt-conditioned
# Qari model still drives the FINAL review (timed full-audio pass + tajweed
# checks), where it is scoring against the recorded audio instead of steering a
# live reveal.
EVIDENCE_POLICY = os.environ.get("QARI_EVIDENCE_POLICY", "tier2").lower()

# A transcriber turns a float32 mono 16 kHz signal into (normalized_words,
# per_word_confidences).
Transcriber = Callable[["object", int], "tuple[list[str], list[float]]"]


class LiveTranscriberUnavailable(RuntimeError):
    """Raised when production live ASR cannot be loaded safely."""


# ---------------------------------------------------------------------------
# Reference resolution (expected normalized words for an ayah)
# ---------------------------------------------------------------------------

# Inlined Arabic normalizer (mirrors ml.inference.asr.normalize_arabic) so the
# streaming reference resolution does NOT import the heavy ASR module (torch /
# numpy). The live stream only needs lightweight normalization + the pure-Python
# StreamingMatcher; the full ASR engine is only used by the real transcriber.
import re as _re

_HARAKAT = _re.compile(
    "[\u0618-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED]"
)
_TATWEEL = _re.compile("\u0640")
_ALEF = {"\u0622": "ا", "\u0623": "ا", "\u0625": "ا", "\u0671": "ا", "\u0672": "ا", "\u0673": "ا"}
_YA = {"\u0649": "ي", "\u06CC": "ي"}
_TA_MARBUTA = "\u0629"
_HA = "\u0647"
_HAMZA = {"\u0624": "و", "\u0626": "ي", "\u0621": ""}
_NON_ARABIC = _re.compile(r"[^\u0621-\u064A\u0660-\u0669\u066E-\u06D5\u06DE\u06EF ]")
_MULTI_SPACE = _re.compile(r"\s+")


def _normalize(text: str) -> str:
    if not text:
        return ""
    text = _HARAKAT.sub("", text)
    text = _TATWEEL.sub("", text)
    for variant, canonical in _ALEF.items():
        text = text.replace(variant, canonical)
    for variant, canonical in _YA.items():
        text = text.replace(variant, canonical)
    text = text.replace(_TA_MARBUTA, _HA)
    for variant, canonical in _HAMZA.items():
        text = text.replace(variant, canonical)
    text = _NON_ARABIC.sub(" ", text)
    text = _MULTI_SPACE.sub(" ", text)
    return text.strip()


def _pack_entries(display: list[str], norm: list[str]) -> list[dict]:
    """Zip display + normalized words into the blueprint word-level model.

    Keeps all three lists aligned (a reference word with no clean_text is
    dropped from all three) so the matcher, the UI, and the ``ready`` payload
    always agree on indices.
    """
    entries: list[dict] = []
    kept_display: list[str] = []
    kept_norm: list[str] = []
    for d, n in zip(display, norm):
        if not n:
            continue
        entries.append({"text_with_tashkeel": d, "clean_text": n})
        kept_display.append(d)
        kept_norm.append(n)
    return entries, kept_display, kept_norm


_reference_store_cache = None


def _get_reference_store():
    """Return a process-wide, read-only :class:`ReferenceStore` (built once).

    ``ReferenceStore.__init__`` globs and parses EVERY ``{surah}_{ayah}.json``
    bundle in ``reference_data_dir`` (~0.6s of disk + JSON work on this VPS).
    Rebuilding it on every ``resolve_reference_words`` call made a full-surah
    session (7 ayahs) spend 4+ seconds in ``load_reference`` BEFORE the
    ``ready`` handshake — the "app is frozen when I tap start" cold-start
    freeze. The store is immutable after load (a plain ``(surah, ayah) ->
    AyahReference`` dict with instant lookups), so one shared instance is safe
    and makes repeat lookups free. Mirrors the cached-store pattern already used
    in ``app.workers.inference_worker``.
    """
    global _reference_store_cache
    if _reference_store_cache is None:
        from ml.tajweed.reference_store import ReferenceStore

        _reference_store_cache = ReferenceStore(settings.reference_data_dir or None)
    return _reference_store_cache


def resolve_reference_words(surah: int, ayah: int) -> tuple[list[str], list[str], str, list[dict]]:
    """Resolve the expected (reference) word list for a single ayah.

    Returns ``(display_words, normalized_words, reference_audio_url,
    word_entries)`` where ``word_entries`` is a list (aligned 1:1 with the
    returned ``display_words``) of the blueprint word-level model::

        {"text_with_tashkeel": <UI Arabic>, "clean_text": <ASR key>}

    Tries the ML file-backed reference store first, then core_api. Returns
    empty lists when nothing is available (the client then falls back to its
    own bundled corpus for the masked text).
    """
    # 1) ML reference store (prebuilt {surah}_{ayah}.json bundle) — cached.
    try:
        store = _get_reference_store()
        if store.has(surah, ayah):
            ref = store.get(surah, ayah)
            display = [w.text_with_tashkeel or w.word for w in ref.words]
            norm = [_normalize(w.word) for w in ref.words]
            entries, display, norm = _pack_entries(display, norm)
            return display, norm, ref.reference_audio_url or "", entries
    except Exception as exc:  # pragma: no cover - ml deps optional
        logger.debug("stream.refstore_miss", surah=surah, ayah=ayah, error=str(exc))

    # 2) core_api fallback.
    try:
        import httpx

        url = (
            f"{settings.core_api_base_url}/v1/surahs/{surah}/ayahs"
            f"?from={ayah}&to={ayah}"
        )
        resp = httpx.get(url, timeout=10)
        resp.raise_for_status()
        payload = resp.json()
        ayahs = payload if isinstance(payload, list) else (
            payload.get("ayahs") or payload.get("data") or []
        )
        if ayahs:
            words = ayahs[0].get("words", [])
            display = [w.get("text_arabic", "") for w in words]
            norm = [_normalize(w.get("text_arabic", "")) for w in words]
            entries, display, norm = _pack_entries(display, norm)
            return display, norm, ayahs[0].get("audio_url", "") or "", entries
    except Exception as exc:
        logger.warning("stream.ref_fetch_failed", surah=surah, ayah=ayah, error=str(exc))

    return [], [], "", []


def resolve_reference_words_sequence(
    ayah_refs: list[tuple[int, int]],
) -> tuple[list[str], list[str], str, list[dict], list[dict]]:
    """Resolve and **concatenate** the reference word lists for a sequence of
    ``(surah, ayah)`` references — used for continuous full-page / full-surah
    recitation.

    Returns ``(display_words, normalized_words, first_audio_url,
    word_entries, ayah_boundaries)`` where ``ayah_boundaries`` is a list
    (one entry per ayah) of ``{"surah", "ayah", "word_index_end",
    "word_count"}`` describing where each ayah ends in the global
    (concatenated) word index. This lets the client render end-of-ayah markers
    without re-deriving the split itself.
    """
    display: list[str] = []
    norm: list[str] = []
    audio_url = ""
    entries: list[dict] = []
    boundaries: list[dict] = []

    for surah, ayah in ayah_refs:
        d, n, url, e = resolve_reference_words(surah, ayah)
        if not audio_url and url:
            audio_url = url
        # Record the boundary *before* extending so word_index_end is correct.
        boundaries.append({
            "surah": surah,
            "ayah": ayah,
            "word_index_end": len(display) + len(d) - 1,
            "word_count": len(d),
        })
        display.extend(d)
        norm.extend(n)
        entries.extend(e)

    return display, norm, audio_url, entries, boundaries


# ---------------------------------------------------------------------------
# Transcribers
# ---------------------------------------------------------------------------

_real_asr = None


def _real_transcriber(
    audio, sr: int, initial_prompt: str = ""
) -> tuple[list[str], list[float]]:
    """Transcribe with Faster-Whisper (CT2, INT8) — CPU-efficient real-time ASR.

    Runs the **Qari V50 trained model** (prompt-conditioned LoRA merged into
    whisper-base-ar-quran, converted to CTranslate2 INT8 from local files).
    ``initial_prompt`` = expected ayah text (tashkeel) — the ORACLE prompt the
    model was trained with (WER 0.0065 prompted vs 6.8 unprompted); it curbs
    the repetition loops the free-running decoder falls into. Raw Arabic
    tokens are normalized with the *same* ``_normalize`` used for the reference
    words, so the :class:`StreamingMatcher` compares hypothesis ↔ reference on a
    consistent basis. Returns ``([], [])`` on any failure so the session falls
    back to the stub-style behaviour instead of crashing.
    """
    try:
        from ml.inference.faster_whisper_transcriber import get_transcriber

        raw_words, confs = get_transcriber().transcribe(audio, sr, initial_prompt)
    except Exception as exc:  # pragma: no cover - model/load failures
        logger.error("stream.faster_whisper_failed", error=str(exc))
        return [], []

    norm: list[str] = []
    out_confs: list[float] = []
    for w, c in zip(raw_words, confs):
        n = _normalize(w)
        if n:
            norm.append(n)
            out_confs.append(c)
    return norm, out_confs


def _accepts_prompt(transcriber) -> bool:
    """Whether a transcriber callable takes an oracle prompt as 3rd argument.

    Transcriber callables come in two shapes: the production Faster-Whisper
    wrapper takes ``(audio, sample_rate, prompt)``, while the duration stub and
    the injected test fakes take ``(audio, sample_rate)``. Calling a 2-arg
    callable with 3 arguments raised TypeError, which the live loop swallowed
    (``stream.transcribe_failed``) — so NO word event ever fired on the stub
    path and the streaming WebSocket test hung waiting for them.
    """
    import inspect

    try:
        params = inspect.signature(transcriber).parameters
    except (TypeError, ValueError):  # builtins / C callables: assume flexible
        return True
    count = 0
    for param in params.values():
        if param.kind == param.VAR_POSITIONAL:
            return True
        if param.kind in (param.POSITIONAL_ONLY, param.POSITIONAL_OR_KEYWORD):
            count += 1
    return count >= 3


def _invoke_transcriber(transcriber, audio, sr: int, prompt: str):
    """Call ``transcriber`` with the prompt only when it accepts one."""
    if _accepts_prompt(transcriber):
        return transcriber(audio, sr, prompt)
    return transcriber(audio, sr)


def _independent_transcriber(audio, sr: int) -> tuple[list[str], list[float]]:
    """UNPROMPTED decode with the independent base model — the honest witness.

    The Qari adapter is an ORACLE model (trained to reproduce the expected text
    given as the prompt), so it cannot validate a recitation: with Al-Fatiha as
    the prompt it emits Al-Fatiha even when the audio is a totally different
    recitation (verified on this VPS). Only a decode that never sees the
    expected text can tell what the reciter actually said, which is what the
    live matcher needs to flag real mistakes.
    """
    try:
        from ml.inference.faster_whisper_transcriber import get_transcriber

        raw_words, confs = get_transcriber().transcribe_independent(audio, sr)
    except Exception as exc:  # pragma: no cover - model/load failures
        logger.error("stream.independent_decode_failed", error=str(exc))
        return [], []

    norm: list[str] = []
    out_confs: list[float] = []
    for w, c in zip(raw_words, confs):
        n = _normalize(w)
        if n:
            norm.append(n)
            out_confs.append(c)
    return norm, out_confs


def _make_stub_transcriber(reference_words: list[str]) -> Transcriber:
    """Duration-based stub: reveal reference words as audio accumulates.

    Lets the full live flow be demoed without model weights. It reveals one
    reference word per ``STUB_SECONDS_PER_WORD`` of audio, so words light up
    green sequentially as the user "recites".

    Silence gate: only reveal words when the audio actually contains speech
    (RMS above ``SILENCE_RMS_THRESHOLD``). Without this, room tone / breath
    alone would accumulate duration and auto-complete the ayah even though the
    user said nothing — matching the real-ASR path's behaviour.
    """

    def _transcribe(audio, sr: int) -> tuple[list[str], list[float]]:
        try:
            n = len(audio)
        except TypeError:
            n = 0
        # Silence gate: if the audio is essentially quiet (the user is not
        # reciting), reveal nothing — even the stub must not auto-complete the
        # ayah on room tone / breath alone.
        if _rms_energy(audio) < SILENCE_RMS_THRESHOLD:
            return [], []
        seconds = (n / sr) if sr else 0.0
        reveal = min(len(reference_words), int(seconds / STUB_SECONDS_PER_WORD))
        words = list(reference_words[:reveal])
        return words, [0.9] * len(words)

    return _transcribe


def _words_similar(a: str, b: str, threshold: float = 0.80) -> bool:
    """Loose word match used when stitching overlapping ASR windows.

    The ASR re-transcribes the same audio every pass, and the model rarely emits
    byte-identical tokens across passes (segmentation / diacritic-stripping noise
    differ). An *exact* equality check therefore almost never finds the overlap,
    so every window got appended again and the cumulative hypothesis grew without
    bound — which made the matcher blow through the entire reference ayah long
    before the user had spoken those words. Comparing on the normalized form with
    a similarity floor recovers the overlap.
    """
    na, nb = _normalize(a), _normalize(b)
    # When normalization strips everything (e.g. non-Arabic / Latin test tokens,
    # numbers), fall back to a raw comparison so overlap detection still works.
    if not na or not nb:
        return a == b
    if na == nb:
        return True
    from ml.alignment.streaming_matcher import char_similarity

    return char_similarity(na, nb) >= threshold


def stitch_hypothesis(
    prefix: list[str],
    prefix_confs: list[float],
    window_words: list[str],
    window_confs: list[float],
    *,
    max_overlap: int = STITCH_MAX_OVERLAP_WORDS,
) -> tuple[list[str], list[float]]:
    """Append a re-transcribed audio WINDOW onto the cumulative hypothesis.

    Consecutive windows overlap in time, so ``window_words`` re-contains the tail
    of what ``prefix`` already holds. We find the largest ``k`` such that the last
    ``k`` words of ``prefix`` are *similar* to the first ``k`` words of
    ``window_words`` (fuzzy, not exact — see :func:`_words_similar`) and only
    append the remainder — so the same spoken word is never counted twice and the
    hypothesis length tracks the user's actual progress instead of exploding.

    Falls back to appending the whole window when no overlap is found (e.g. the
    user recited fast enough that the window is entirely new). Pure function (no
    timestamps needed) so it is trivially unit-testable.
    """
    if not window_words:
        return list(prefix), list(prefix_confs)
    if not prefix:
        return list(window_words), list(window_confs)

    max_k = min(max_overlap, len(prefix), len(window_words))
    best_k = 0
    for k in range(max_k, 0, -1):
        if all(
            _words_similar(prefix[-(k - m)], window_words[m])
            for m in range(k)
        ):
            best_k = k
            break
    merged = list(prefix) + list(window_words[best_k:])
    merged_confs = list(prefix_confs) + list(window_confs[best_k:])
    return merged, merged_confs


def _rms_energy(samples: list[float]) -> float:
    """Root-mean-square energy of a float32 signal in [0, 1].

    Used to detect silence: near-silent mic audio (room tone / the user not
    reciting) has a very low RMS, while actual recitation is markedly higher.
    """
    if not samples:
        return 0.0
    return (sum(s * s for s in samples) / len(samples)) ** 0.5


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

class StreamingRecitationSession:
    """Stateful live recitation session for a single WebSocket connection."""

    def __init__(
        self,
        *,
        surah: int = 1,
        ayah_from: int = 1,
        ayah_to: int = 1,
        ayah_refs: Optional[list[tuple[int, int]]] = None,
        mode: str = "tracking",
        sample_rate: int = 16000,
        transcriber: Optional[Transcriber] = None,
        client_words: Optional[list[str]] = None,
    ) -> None:
        self.session_id = str(uuid.uuid4())

        # `ayah_refs` is the authoritative, ordered list of (surah, ayah) the
        # user will recite continuously (a full Mushaf page or a whole surah).
        # When omitted we fall back to a single-surah range for backwards
        # compatibility with older clients.
        if ayah_refs:
            self.ayah_refs: list[tuple[int, int]] = list(ayah_refs)
        else:
            self.ayah_refs = [(surah, a) for a in range(ayah_from, ayah_to + 1)]

        self.surah = self.ayah_refs[0][0] if self.ayah_refs else surah
        self.ayah_from = self.ayah_refs[0][1] if self.ayah_refs else ayah_from
        self.ayah_to = self.ayah_refs[-1][1] if self.ayah_refs else ayah_to
        self.mode = mode
        self.sample_rate = sample_rate

        self.display_words: list[str] = []
        self.reference_words: list[str] = []
        self.reference_audio_url: str = ""
        self.word_entries: list[dict] = []
        self.ayah_boundaries: list[dict] = []

        # Client-supplied word list (sent in the `start` handshake). Used as a
        # fallback reference when the server's own reference store / corpus is
        # empty, so the matcher still produces verdicts (fixes "0 of 0 words").
        self._client_words: list[str] = list(client_words or [])

        self._pcm = bytearray()
        self._samples_at_last_transcribe = 0
        self._transcribe_lock = asyncio.Lock()
        self._transcribe_stop = False
        self._matcher = None
        self._last_status: dict[int, str] = {}
        # Cumulative hypothesis (stitched from per-window transcriptions) + its
        # per-word confidences. `_last_hypothesis` is kept as an alias to the
        # cumulative words so `finalize()` and existing callers keep working.
        self._hypothesis: list[str] = []
        self._hypothesis_confs: list[float] = []
        self._last_hypothesis: list[str] = []
        # Alternate-pass verification state: number of live transcription
        # passes so far and the (word, conf) list from the last unprompted
        # verification decode (reused on passes that skip it).
        self._pass_count = 0
        self._verified_words: list[tuple[str, float]] = []
        self._explicit_transcriber = transcriber
        self._transcriber: Optional[Transcriber] = None
        # Whether the active transcriber is the duration-based stub (which needs
        # the FULL buffer sample count to reveal words over time) vs a real ASR
        # (which uses the bounded sliding window). Set in load_reference.
        self._is_stub = True

    # ------------------------------------------------------------------
    def load_reference(self) -> None:
        """Resolve the expected (concatenated) word list and pick a transcriber."""
        from ml.alignment.streaming_matcher import StreamingMatcher

        display, norm, ref_url, entries, boundaries = resolve_reference_words_sequence(
            self.ayah_refs
        )
        self.display_words = display
        self.reference_words = norm
        self.reference_audio_url = ref_url
        self.word_entries = entries
        self.ayah_boundaries = boundaries
        # Per-word tashkeel text used to build the ORACLE decode prompt for the
        # prompt-conditioned V50 ASR model. Falls back to normalized words when
        # tashkeel entries are unavailable (e.g. client-words fallback).
        self.reference_text_with_tashkeel_words: list[str] = [
            (e.get("text_with_tashkeel") or "") for e in entries
        ]
        if not self.reference_text_with_tashkeel_words or any(
            not w for w in self.reference_text_with_tashkeel_words
        ):
            self.reference_text_with_tashkeel_words = list(display or norm)

        # Fallback: if the server resolved NO reference words (empty reference
        # store / corpus), trust the client's own resolved word list so we can
        # still score and emit word events instead of "0 of 0".
        if not self.reference_words and self._client_words:
            logger.warning(
                "stream.using_client_words_fallback",
                session_id=self.session_id,
                count=len(self._client_words),
            )
            c_display = list(self._client_words)
            c_norm = [_normalize(w) for w in c_display]
            c_entries, c_display, c_norm = _pack_entries(c_display, c_norm)
            self.display_words = c_display
            self.reference_words = c_norm
            self.word_entries = c_entries
            self.ayah_boundaries = []
            self.reference_text_with_tashkeel_words = list(c_display)

        # Build the matcher + transcriber from the FINAL reference words (which
        # may be the client-words fallback), not the original (possibly empty)
        # `norm` returned by the server's own resolver.
        #
        # The ayah boundaries are handed to the matcher so its live search can be
        # clamped to the active ayah (+1). Without them the aligner could anchor
        # on a word several ayahs ahead and cascade SKIPPED marks over everything
        # in between (the "red wall" symptom).
        self._matcher = StreamingMatcher(
            self.reference_words,
            ayah_boundaries=self.ayah_boundaries,
        )

        if self._explicit_transcriber is not None:
            self._transcriber = self._explicit_transcriber
            # An explicit transcriber (tests / real ASR injection) is treated as
            # real so it uses the bounded sliding window.
            self._is_stub = False
        elif settings.ml_use_stub or not self.reference_words:
            self._transcriber = _make_stub_transcriber(self.reference_words)
            self._is_stub = True
        else:
            # Real ASR requested. Probe whether the Faster-Whisper CT2 model is
            # actually loadable in this container (it must be bind-mounted at
            # QARI_FASTERWHISPER_MODEL_DIR). If it is missing/unloadable the real
            # transcriber would silently return [] on every call. Critically,
            # never fall back to the duration-based demo stub here: that stub
            # reveals one word every 0.9 seconds without inspecting speech and
            # therefore auto-completes an ayah when the user says nothing.
            try:
                from ml.inference.faster_whisper_transcriber import get_transcriber

                get_transcriber().load()
                self._transcriber = _real_transcriber
                self._is_stub = False
                logger.info(
                    "stream.transcriber", session_id=self.session_id,
                    engine="faster-whisper", words=len(self.reference_words),
                )
            except Exception as exc:
                logger.error(
                    "stream.real_transcriber_unavailable",
                    session_id=self.session_id, error=str(exc),
                )
                raise LiveTranscriberUnavailable(
                    "Live speech recognition is temporarily unavailable. "
                    "The recitation model could not be loaded."
                ) from exc

    # ------------------------------------------------------------------
    def ready_payload(self) -> dict:
        # Word-level model served to the client (per the Hifz data contract):
        #   word_id, sequence_index, text_with_tashkeel, clean_text, state
        # The first word is "active" (the next word the user must recite); the
        # rest start "hidden" until revealed by the live engine.
        words = []
        for i, entry in enumerate(self.word_entries):
            words.append({
                "word_id": i + 1,
                "sequence_index": i + 1,
                "text_with_tashkeel": entry.get("text_with_tashkeel", self.display_words[i]),
                "clean_text": entry.get("clean_text", self.display_words[i]),
                "state": "active" if i == 0 else "hidden",
            })
        return {
            "type": "ready",
            "session_id": self.session_id,
            "surah_number": self.surah,
            "ayah_from": self.ayah_from,
            "ayah_to": self.ayah_to,
            "mode": self.mode,
            "words": words,
            "word_count": len(self.reference_words),
            "ayah_boundaries": self.ayah_boundaries,
        }

    # ------------------------------------------------------------------
    def add_audio(self, chunk: bytes) -> None:
        self._pcm.extend(chunk)

    # Background transcription loop (driven by the WebSocket handler so the
    # receive loop never blocks on the slow Whisper call). Re-transcribes the
    # accumulated audio on a fixed cadence and emits `word` events as words
    # resolve. A single in-flight transcription is guarded by `_transcribe_lock`
    # so concurrent ticks never stack.
    def stop_transcription(self) -> "asyncio.Future":
        self._transcribe_stop = True
        return asyncio.sleep(0)  # no-op awaitable for callers

    def _is_first_pass(self) -> bool:
        """True only for the very first live pass of a session.

        Single source of truth for "is this still the early pass?", used by BOTH
        the audio threshold (maybe_transcribe) and the loop cadence. They must
        not drift: the first version lowered the threshold but left the loop
        sleeping the full 1.2 s, so the early pass never actually fired early
        and first-word latency stayed at ~2.1 s (measured). Keeping both call
        sites on this predicate is what makes the optimisation real.
        """
        return self._pass_count == 0 and not self._hypothesis

    def _next_interval_sec(self) -> float:
        """Seconds of *new* audio to accumulate before the next pass."""
        if EARLY_FIRST_PASS and self._is_first_pass():
            return EARLY_FIRST_PASS_SEC
        return TRANSCRIBE_INTERVAL_SEC

    async def transcription_loop(self, websocket) -> None:
        self._transcribe_stop = False
        try:
            while not self._transcribe_stop:
                try:
                    t0 = asyncio.get_event_loop().time()
                    for event in await self.maybe_transcribe():
                        await websocket.send_json(event)
                except Exception as exc:  # pragma: no cover - model failures
                    logger.error("stream.loop_transcribe_failed", session_id=self.session_id, error=str(exc))
                # Sleep only the *remaining* interval after a (possibly slow)
                # transcription pass so the cadence stays ~constant regardless of
                # how long Whisper took. This keeps the live reveal smooth
                # instead of a fixed 1.2s gap stacked on top of each pass.
                #
                # The interval is EARLY-AWARE: on the first pass it is
                # EARLY_FIRST_PASS_SEC (0.5 s) instead of 1.2 s. Without this the
                # loop simply never ticked again until 1.2 s had elapsed, so
                # lowering the threshold in maybe_transcribe alone changed
                # nothing (measured: first word stayed ~2.1 s).
                elapsed = asyncio.get_event_loop().time() - t0
                remaining = self._next_interval_sec() - elapsed
                if remaining > 0:
                    await asyncio.sleep(remaining)
        except asyncio.CancelledError:
            return

    @property
    def _total_samples(self) -> int:
        return len(self._pcm) // 2  # 16-bit samples

    @property
    def duration_seconds(self) -> float:
        return self._total_samples / self.sample_rate if self.sample_rate else 0.0

    def _decode_float(self, start_sample: int = 0, end_sample: Optional[int] = None):
        # Numpy-free decode: convert the raw PCM16 bytes into a list of float32
        # samples in [-1, 1]. Kept dependency-light so the live stream runs in
        # the API container without the full ML stack. Optionally decode only the
        # sample range [start_sample, end_sample) — the sliding window transcribes
        # a bounded recent span instead of the whole growing buffer.
        if not self._pcm:
            return []
        import array

        start_byte = max(0, start_sample) * 2
        end_byte = (
            len(self._pcm)
            if end_sample is None
            else min(len(self._pcm), end_sample * 2)
        )
        # PCM length may be odd (partial final frame); align to an even byte
        # boundary so `array.frombytes` never sees a half-sample. Without this
        # the real-ASR sliding-window path raised ValueError on every pass ->
        # no word events fired during streaming (the reveal only "dumped" on the
        # forced final transcribe), which is exactly the "buffering" feel.
        end_byte -= end_byte % 2
        if end_byte <= start_byte:
            return []
        samples = array.array("h")
        samples.frombytes(bytes(self._pcm[start_byte:end_byte]))
        return [s / 32768.0 for s in samples]

    # ------------------------------------------------------------------
    async def maybe_transcribe(self, *, force: bool = False) -> list[dict]:
        """Re-transcribe if enough new audio arrived; return new word events.

        For the real ASR we transcribe only a bounded SLIDING WINDOW of the most
        recent audio (``TRANSCRIBE_WINDOW_SEC``) and stitch the new words onto the
        cumulative hypothesis — so per-pass cost stays ~constant and the live
        reveal keeps up regardless of recitation length. The duration-based STUB
        still needs the full buffer (it reveals words from the total sample
        count), so it runs on the whole buffer (which is cheap for the stub).
        """
        if self._matcher is None or self._transcriber is None:
            return []
        new_samples = self._total_samples - self._samples_at_last_transcribe
        # Early first pass: only pass #1 of the session, only when nothing has
        # been revealed yet, and only if the feature is enabled. After it, the
        # normal TRANSCRIBE_INTERVAL_SEC cadence resumes untouched.
        is_first_pass = self._is_first_pass()
        early = EARLY_FIRST_PASS and is_first_pass and not force
        interval_sec = self._next_interval_sec()
        threshold = int(interval_sec * self.sample_rate)
        if not force and new_samples < threshold:
            return []
        # A forced (stop-time) pass must NOT be dropped just because the
        # background loop is mid-transcription: dropping it silently discards
        # the final window's words (observed live: the last ayah never
        # resolved before `final`). Forced callers wait for the lock instead;
        # cadence callers skip to keep the reveal smooth.
        if self._transcribe_lock.locked() and not force:
            return []

        async with self._transcribe_lock:
            self._samples_at_last_transcribe = self._total_samples
            total = self._total_samples

            if self._is_stub:
                # Stub reveals words from the TOTAL duration → needs full buffer.
                audio = self._decode_float()
                try:
                    words, confs = await asyncio.to_thread(
                        _invoke_transcriber, self._transcriber, audio,
                        self.sample_rate,
                        " ".join(self.reference_text_with_tashkeel_words),
                    )
                except Exception as exc:  # pragma: no cover - model failures
                    logger.error(
                        "stream.transcribe_failed",
                        session_id=self.session_id, error=str(exc),
                    )
                    return []
                self._hypothesis = list(words)
                self._hypothesis_confs = list(confs)
            else:
                # Real ASR: transcribe only the last TRANSCRIBE_WINDOW_SEC of
                # audio and stitch the new words onto the cumulative hypothesis.
                # On the early first pass a SHORTER window is used so the decode
                # itself is cheaper; it applies to that one pass only.
                window_sec = (
                    EARLY_FIRST_PASS_WINDOW_S if early else TRANSCRIBE_WINDOW_SEC
                )
                overlap_sec = 0.0 if early else TRANSCRIBE_WINDOW_OVERLAP_SEC
                window_samples = int(
                    (window_sec + overlap_sec) * self.sample_rate
                )
                start = max(0, total - window_samples)
                audio = self._decode_float(start_sample=start)
                # Silence gate: if this window is essentially quiet (the user is
                # not reciting), Whisper would still hallucinate phantom Arabic
                # words that "complete" the ayah on their own. Skip transcription
                # and emit NO events so nothing resolves until there is real
                # speech. Do NOT advance `_samples_at_last_transcribe` so the next
                # pass that does contain speech still re-scans this quiet span.
                # NOTE: _rms_energy is a MODULE-LEVEL function (not a method).
                # A previous `self._rms_energy(audio)` typo raised
                # AttributeError on EVERY live pass — the transcription loop
                # swallowed it and no `word` event ever reached the client
                # (the summary-only symptom).
                if _rms_energy(audio) < SILENCE_RMS_THRESHOLD:
                    return []
                # ORACLE prompt — must stay in the model's TRAINING condition:
                # V50 was trained on PER-AYAH prompts (prompt = text of the SAME
                # ayah as the speech). Cross-ayah or past-word prompts make the
                # model echo the prompt instead of transcribing (verified), and
                # full-page prompts break its alignment. So: prompt = the
                # remaining words of the ayah that contains the matcher cursor.
                # Echo risk exists only when the user recites something OTHER
                # than the on-screen reference — the trust-first matcher gate
                # bounds that, and the final review re-scores honestly.
                cursor = getattr(self._matcher, "_cursor", 0) or 0
                ayah_start, ayah_end = 0, len(self.reference_text_with_tashkeel_words) - 1
                for b in getattr(self, "ayah_boundaries", None) or []:
                    end = int(b.get("word_index_end", -1))
                    if end >= cursor:
                        ayah_start = max(0, end + 1 - int(b.get("word_count", 0)))
                        ayah_end = end
                        break
                # ANCHORED prompt: only words BEFORE the matcher cursor, capped to
                # a short span, and framed inside the current ayah. A prompt that
                # included the *upcoming* words made the model ECHO them instead
                # of transcribing: every echoed word was already resolved, so
                # stitching deduped it, the hypothesis stopped growing and the
                # live reveal FROZE for the rest of the ayah (verified: cursor
                # pinned at the ayah-6 -> 7 boundary for ~22s until the final
                # window cleared it). With no future text in the prompt the model
                # can only report what it actually hears, so the reveal tracks the
                # recitation (verified honest across the anchor matrix).
                # NOTE: tried anchoring the prompt on already-resolved words only
                # (no future text) to remove echo risk entirely — measured 3/29
                # live words vs 20/29 with the per-ayah prompt, so the model
                # really does need the current ayah's text (its training
                # condition) and the remaining-words prompt stays. Echo risk is
                # instead bounded by the corroboration filter + watchdog below.
                remaining = self.reference_text_with_tashkeel_words[
                    max(cursor, ayah_start):ayah_end + 1
                ]
                prompt = " ".join(remaining[:PROMPT_ANCHOR_WORDS])
                # --- Two-tier decode (V51-kernel style) ---------------------
                # Tier 1 (PROMPTED) is the model's training condition and
                # accurate when the audio matches the expectation, but an
                # oracle prompt is not an independent witness: on mismatched
                # audio the model ECHOES the prompt and would highlight words
                # the user has not recited yet (verified: ayah-5 words fired
                # while only ayah-3 audio had been streamed).
                # Tier 2 (UNPROMPTED) is echo-immune evidence of the actual
                # speech; a tier-1 word is accepted only when corroborated.
                # Decodes run CONCURRENTLY (2 threads each, see
                # QARI_FASTERWHISPER_THREADS) — wall time is ~max(tier1, tier2)
                # instead of the sum (measured 1.9s vs 4.2s). The unprompted
                # verification decode additionally runs only every
                # VERIFY_EVERY_N_PASSES passes: windows overlap heavily so its
                # token set stays valid, and skipping it on alternate passes
                # cuts the average pass cost further (lower reveal latency).
                stall = int(getattr(self._matcher, "_stall_passes", 0) or 0) >= 1
                self._pass_count += 1
                refresh_verify = (
                    not self._verified_words
                    or VERIFY_EVERY_N_PASSES <= 1
                    or self._pass_count % VERIFY_EVERY_N_PASSES == 0
                    or stall
                )
                try:
                    if EVIDENCE_POLICY == "tier2":
                        # The independent witness IS the live hypothesis (see
                        # EVIDENCE_POLICY), so the prompted decode is not needed
                        # at all: one decode instead of two halves CPU use and
                        # drops the pass wall time (~1.1s vs ~1.9s measured on
                        # this VPS), which is the live reveal latency.
                        win_words, win_confs = await asyncio.to_thread(
                            _independent_transcriber, audio, self.sample_rate
                        )
                        raw_words, raw_confs = list(win_words), list(win_confs)
                        self._verified_words = [
                            (w, c) for w, c in zip(raw_words, raw_confs) if w
                        ]
                    elif refresh_verify:
                        # tier-2 = INDEPENDENT model, unprompted (honest witness).
                        # NOT the V50 oracle with an empty prompt: that model
                        # only reproduces text it was prompted with and is
                        # useless as evidence.
                        (win_words, win_confs), (raw_words, raw_confs) = await asyncio.gather(
                            asyncio.to_thread(
                                _invoke_transcriber, self._transcriber, audio,
                                self.sample_rate, prompt,
                            ),
                            asyncio.to_thread(
                                _independent_transcriber, audio, self.sample_rate
                            ),
                        )
                        self._verified_words = [
                            (w, c) for w, c in zip(raw_words, raw_confs) if w
                        ]
                    else:
                        win_words, win_confs = await asyncio.to_thread(
                            _invoke_transcriber, self._transcriber, audio,
                            self.sample_rate, prompt,
                        )
                        raw_words = [w for w, _ in self._verified_words]
                        raw_confs = [c for _, c in self._verified_words]
                except Exception as exc:  # pragma: no cover - model failures
                    logger.error(
                        "stream.transcribe_failed",
                        session_id=self.session_id, error=str(exc),
                    )
                    return []

                raw_norm_list = [_normalize(w) for w in raw_words if w]
                raw_norm_set = set(raw_norm_list)
                if STREAM_DEBUG:
                    logger.info(
                        "stream.pass_debug",
                        session_id=self.session_id,
                        force=force,
                        dur=round(self.duration_seconds, 1),
                        cursor_before=int(getattr(self._matcher, "_cursor", 0) or 0),
                        stall=stall,
                        tier1=" ".join(w for w in win_words if w)[:120],
                        tier2=" ".join(w for w in raw_words if w)[:120],
                        hyp=" ".join(self._hypothesis[-20:]),
                        dp=getattr(self._matcher, "_last_dp_debug", None),
                    )
                ref_norm_set = set(self.reference_words)
                # NOTE (removed): a "watchdog" used to disable this filter after
                # a few stalled passes, on the theory that tier-2 had gone
                # garbage while tier-1 was correct. With the ORACLE (V50) model
                # that bypass was the exact bug users see — it accepts text the
                # model ECHOED from the prompt, so a recitation is reported
                # correct no matter what was actually said. tier-2 is now the
                # independent base model (see _independent_transcriber), so the
                # corroboration requirement is kept unconditionally: no evidence
                # heard by the independent decode -> no match.
                def _corroborated(token: str) -> bool:
                    n = _normalize(token)
                    if not n:
                        return False
                    if n in raw_norm_set:
                        return True
                    # Different tokenization of the same word (article split /
                    # merged): a >=4-char word embedded in a longer raw token.
                    if len(n) >= 4 and any(n in r for r in raw_norm_list):
                        return True
                    # Tier-2 sometimes mangles a single word of an otherwise
                    # correct span — accept near-identical tokens.
                    import difflib

                    return any(
                        difflib.SequenceMatcher(None, n, r).ratio() >= 0.6
                        for r in raw_norm_list
                    )

                verified = [
                    (w, c) for w, c in zip(win_words, win_confs)
                    if _corroborated(w)
                ]
                if EVIDENCE_POLICY == "tier2":
                    win_words = list(raw_words)
                    win_confs = list(raw_confs)
                elif verified:
                    win_words = [w for w, _ in verified]
                    win_confs = [c for _, c in verified]
                elif raw_words:
                    # The prompted decode produced nothing OR was filtered out
                    # (a prompt ECHO). Either way the INDEPENDENT decode is the
                    # evidence of what was actually spoken, so use it. This case
                    # MUST cover the empty-tier-1 window: previously the fallback
                    # required a non-empty tier-1, so on windows where the oracle
                    # emitted no words the independent words were thrown away,
                    # the cumulative hypothesis stopped growing and the reveal
                    # FROZE for the rest of the surah (observed live from ayah 4
                    # onward, ~20 of 29 words).
                    logger.debug(
                        "stream.independent_fallback",
                        session_id=self.session_id,
                        tier1=len(win_words),
                        tier2=len(raw_words),
                    )
                    win_words = list(raw_words)
                    win_confs = list(raw_confs)
                else:
                    # Nothing independent was heard on this window: emit NO
                    # words rather than the oracle's echo (the honesty fix).
                    logger.debug(
                        "stream.echo_uncorroborated",
                        session_id=self.session_id,
                        tier1=len(win_words),
                    )
                    win_words = []
                    win_confs = []
                # STALL UNION: when the reference cursor did not advance during
                # the previous pass, the prompted decode is ECHOING the oracle
                # prompt. Every echoed word was already resolved earlier, so
                # stitching them adds nothing and the reveal FREEZES forever
                # (verified live: cursor pinned at the ayah-6 -> 7 boundary
                # while the user kept reciting). The unprompted decode is
                # echo-immune, so on stalled passes union its tokens into the
                # window output — the matcher then sees the words actually
                # spoken and walks forward again. Only used while stalled, so
                # normal passes keep the accurate prompted-only alignment.
                if stall and raw_words and EVIDENCE_POLICY != "tier2":
                    win_words = list(win_words) + list(raw_words)
                    win_confs = list(win_confs) + list(raw_confs)
                # STALL TAIL RESET: the matcher consumed the stalled tokens as
                # noise, so the tail past its cursor is spent. Worse, if those
                # tokens were prompt-echo they now sit in the hypothesis and
                # stitch_hypothesis() DEDUPS the genuinely-spoken words when the
                # user actually reaches them (seen live: the real ayah-7 words
                # were dropped as "already contributed" and the reveal never
                # moved again). Dropping the spent tail loses nothing and lets
                # fresh evidence append cleanly.
                if stall and self._hypothesis:
                    keep = max(
                        0, int(getattr(self._matcher, "_hyp_cursor", 0) or 0)
                    )
                    self._hypothesis = self._hypothesis[:keep]
                    self._hypothesis_confs = self._hypothesis_confs[:keep]
                stitched, stitched_confs = stitch_hypothesis(
                    self._hypothesis,
                    self._hypothesis_confs,
                    win_words,
                    win_confs,
                )
                # Clamp the cumulative hypothesis so ASR hallucinations /
                # repeated-token explosions can't grow it without bound. The
                # cap must be measured from the matcher's CONSUMED prefix
                # (`_hyp_cursor`), not from the reference length: an absolute
                # cap truncated the TAIL — exactly where the newly transcribed
                # words land — so once a repetition/echo burst filled the
                # budget, every later pass had its real words cut off and the
                # matcher pinned at the cap forever (verified live: cursor
                # frozen while the hypothesis sat at ref_len + lookahead).
                # Keeping `pref + HYPO_TAIL_CAP` words preserves index
                # alignment for the consumed region and lets the matcher walk
                # forward through new tokens as they arrive.
                pref = max(0, int(getattr(self._matcher, "_hyp_cursor", 0) or 0))
                cap = min(
                    len(stitched),
                    pref + HYPO_TAIL_CAP,
                )
                if len(stitched) > cap:
                    stitched = stitched[:cap]
                    stitched_confs = stitched_confs[:cap]
                self._hypothesis = stitched
                self._hypothesis_confs = stitched_confs

            self._last_hypothesis = self._hypothesis
            _cursor_before = int(getattr(self._matcher, "_cursor", 0) or 0)
            states = self._matcher.evaluate(
                self._hypothesis, self._hypothesis_confs
            )
            if STREAM_DEBUG:
                logger.info(
                    "stream.pass",
                    session_id=self.session_id,
                    cursor_before=_cursor_before,
                    cursor_after=int(getattr(self._matcher, "_cursor", 0) or 0),
                    stall=int(getattr(self._matcher, "_stall_passes", 0) or 0),
                    hyp=len(self._hypothesis),
                )
            return self._diff_events(states)

    def _diff_events(self, states) -> list[dict]:
        events: list[dict] = []
        for st in states:
            if self._last_status.get(st.index) == st.status.value:
                continue
            self._last_status[st.index] = st.status.value
            # Blueprint contract: the client receives a stable ``status`` of
            # ``match`` (correctly revealed) or ``error_skipped`` (skipped /
            # mispronounced), keyed by the 1-based ``word_id``. We keep the
            # richer fields (word_index, expected, spoken, confidence) for
            # debugging and richer UI affordances — they are additive.
            blueprint_status = (
                "match" if st.status.value == "matched" else "error_skipped"
            )
            events.append({
                "type": "word",
                "session_id": self.session_id,
                "status": blueprint_status,
                "word_id": st.index + 1,
                "word_index": st.index,
                "expected": st.expected,
                "spoken": st.spoken,
                "confidence": round(st.confidence, 3),
                "timestamp_ms": int(self.duration_seconds * 1000),
            })
        return events

    # ------------------------------------------------------------------
    def _write_wav(self) -> Optional[str]:
        if not self._pcm:
            return None
        try:
            storage = os.path.join(settings.audio_storage_path, self.session_id)
            os.makedirs(storage, exist_ok=True)
            path = os.path.join(storage, "audio.wav")
            with wave.open(path, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(self.sample_rate)
                wf.writeframes(bytes(self._pcm))
            return path
        except Exception as exc:  # pragma: no cover
            logger.warning("stream.wav_write_failed", session_id=self.session_id, error=str(exc))
            return None

    def _run_tajweed_checks(
        self, audio
    ) -> Optional[tuple[float, list[dict]]]:
        """Timed full-audio transcription → acoustic tajweed checks.

        Runs synchronously (call via ``asyncio.to_thread``). Returns
        ``(score_0_to_1, surfaced_issue_dicts)`` or ``None`` when nothing
        could be evaluated. Uses the CT2 word timestamps instead of the
        torch forced aligner so it works inside the live API container.
        """
        from ml.inference.asr import normalize_arabic
        from ml.inference.faster_whisper_transcriber import get_transcriber
        from ml.tajweed.checks import TajweedChecker

        words, _confs, starts, ends = get_transcriber().transcribe_with_timings(
            audio, self.sample_rate,
            " ".join(self.reference_text_with_tashkeel_words),
        )
        if not words:
            return None
        norm = [normalize_arabic(w) for w in words]
        # _decode_float() yields a plain list; the acoustic tajweed helpers are
        # numpy-based (segment.astype(...)) — convert before checking, otherwise
        # every finalize raises "'list' object has no attribute 'astype'".
        import numpy as np
        summary = TajweedChecker(sample_rate=self.sample_rate).check_all(
            np.asarray(audio, dtype=np.float32), norm, starts, ends
        )
        if summary.total_checks == 0:
            return None
        issues = [
            {
                "rule": r.check_type.value,
                "word_index": r.word_index,
                "word": norm[r.word_index]
                if r.word_index is not None and r.word_index < len(norm)
                else None,
                "letter": r.letter,
                "detail": r.detail,
                "start_ms": r.start_ms,
                "end_ms": r.end_ms,
            }
            for r in summary.results
            if r.should_surface
        ]
        return summary.tajweed_score / 100.0, issues

    async def finalize(self) -> dict:
        """End the session: persist audio + build the final result blob."""
        from ml.alignment.streaming_matcher import WordStatus

        # If live transcription never produced a hypothesis (e.g. the forced
        # final transcription on `stop` was slow and the client timed out, or the
        # transcriber was the stub and produced nothing), do ONE full-audio
        # transcription here so the verdicts aren't all "skipped" (0 of N). This
        # guarantees a meaningful result whenever reference words exist.
        if not self._last_hypothesis and self._transcriber is not None and self._pcm:
            try:
                audio = self._decode_float()
                words, confs = await asyncio.to_thread(
                    self._transcriber, audio, self.sample_rate
                )
                if words:
                    self._last_hypothesis = words
            except Exception as exc:  # pragma: no cover - model failures
                logger.error("stream.finalize_transcribe_failed", session_id=self.session_id, error=str(exc))

        audio_path = self._write_wav()
        public_base = settings.recitation_api_public_url.rstrip("/")
        user_audio_url = (
            f"{public_base}/v1/recitations/{self.session_id}/audio"
            if public_base and audio_path
            else audio_path
        )

        states = (
            self._matcher.finalize(self._last_hypothesis)
            if self._matcher is not None
            else []
        )

        word_verdicts = []
        matched = 0
        for st in states:
            is_correct = st.status == WordStatus.MATCHED
            if is_correct:
                matched += 1
            word_verdicts.append({
                "word": st.expected,
                "word_index": st.index,
                "is_correct": is_correct,
                "confidence": round(st.confidence, 3),
                "expected_text": st.expected,
                "actual_text": st.spoken,
                "error_type": None if is_correct else st.status.value,
                "error_description": (
                    None if is_correct else _describe(st.status.value)
                ),
                "reference_audio_url": self.reference_audio_url or None,
                "user_audio_url": user_audio_url,
                "phoneme_errors": [],
            })

        total = len(states)
        accuracy = (matched / total) if total else 0.0
        # Live matching without a resolvable reference gives us nothing to score
        # against → low confidence (mobile shows "no red marks", per trust rule).
        confidence = 1.0 if total else 0.0

        # Best-effort tajweed pass (Tarteel-style post-session "mistake
        # review"): one timed full-audio transcription feeds the acoustic
        # tajweed checks (ghunnah/qalqalah/madd — numpy only, no torch).
        # Never blocks the result on failure; stub sessions and very long
        # sessions skip it.
        tajweed_score = 0.0
        tajweed_issues: list[dict] = []
        if (
            not self._is_stub
            and total
            and self._pcm
            and self.duration_seconds <= 300
        ):
            try:
                audio = self._decode_float()
                tj = await asyncio.to_thread(self._run_tajweed_checks, audio)
                if tj is not None:
                    tajweed_score, tajweed_issues = tj
            except Exception as exc:  # pragma: no cover - analysis best-effort
                logger.warning(
                    "stream.tajweed_failed",
                    session_id=self.session_id,
                    error=str(exc),
                )

        result = {
            "session_id": self.session_id,
            "surah_number": self.surah,
            "ayah_number": self.ayah_from,
            "overall_score": round(accuracy, 4),
            "pronunciation_score": round(accuracy, 4),
            "tajweed_score": round(tajweed_score, 4),
            "tajweed_issues": tajweed_issues,
            "fluency_score": round(accuracy, 4),
            "accuracy_score": round(accuracy, 4),
            "word_verdicts": word_verdicts,
            "reference_audio_url": self.reference_audio_url or None,
            "user_audio_url": user_audio_url,
            "feedback": (
                "Live session complete. Tap red words to compare your recitation."
                if total else
                "We couldn't analyse this recitation with enough confidence."
            ),
            "feedback_urdu": None,
            "duration_seconds": int(self.duration_seconds),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "confidence": round(confidence, 4),
        }
        await self._persist(result, audio_path)
        return result

    async def _persist(self, result: dict, audio_path: Optional[str]) -> None:
        """Store the result in Redis so GET /{session_id} + history keep working."""
        try:
            import json

            import redis.asyncio as redis

            r = redis.from_url(settings.redis_url, decode_responses=True)
            now = datetime.now(timezone.utc).isoformat()
            await r.hset(
                f"qari:recitation:session:{self.session_id}",
                mapping={
                    "session_id": self.session_id,
                    "surah_number": str(self.surah),
                    "ayah_from": str(self.ayah_from),
                    "ayah_to": str(self.ayah_to),
                    "status": "completed",
                    "source": "stream",
                    "audio_path": audio_path or "",
                    "completed_at": now,
                },
            )
            await r.expire(f"qari:recitation:session:{self.session_id}", 86400)
            await r.set(
                f"qari:recitation:result:{self.session_id}",
                json.dumps(result, default=str),
                ex=86400,
            )
            await r.aclose()
        except Exception as exc:  # pragma: no cover - redis optional in tests
            logger.warning("stream.persist_failed", session_id=self.session_id, error=str(exc))


def _describe(status: str) -> str:
    if status == "skipped":
        return "You skipped this word. Recite it before moving on."
    if status == "error":
        return "This word sounded different from the reference. Listen and retry."
    return "Needs practice."
