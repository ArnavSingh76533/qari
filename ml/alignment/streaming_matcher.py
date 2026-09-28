"""Incremental word alignment for live Quran recitation tracking.

Live tracking follows the approach Tarteel documented for its own app: ASR text
is compared to the Quranic reference with *fuzzy string matching* (never
waveform DTW), the individual words are aligned with a Needleman-Wunsch (DP)
sequence alignment, and the search is anchored to the last known position,
widening only when the tracker loses confidence.

The previous implementation used a one-way greedy cursor: it walked the
hypothesis token stream once and never re-scanned it, consuming every
unmatched token as "noise". Whenever the expected word's token was missing
(window-cut fragment, prompt echo, a swallowed word) the cursor simply stopped
advancing and NO further live word could ever resolve — the exact "words stop
appearing mid-surah" failure. The anchor + local-window DP below is monotonic
but re-aligns the whole recent window on every pass, so a missing or mangled
word is skipped and the reveal continues.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from .phonetic import PHONETIC_MATCH_THRESHOLD, phonetic_similarity


class WordStatus(str, Enum):
    PENDING = "pending"
    MATCHED = "matched"
    ERROR = "error"
    SKIPPED = "skipped"


@dataclass
class WordState:
    index: int
    expected: str
    status: WordStatus
    spoken: Optional[str] = None
    confidence: float = 1.0


def _levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    if len(a) < len(b):
        a, b = b, a
    previous = list(range(len(b) + 1))
    for i, char_a in enumerate(a):
        current = [i + 1]
        for j, char_b in enumerate(b):
            current.append(
                min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + (char_a != char_b),
                )
            )
        previous = current
    return previous[-1]


def char_similarity(a: str, b: str) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return 1.0 - _levenshtein(a, b) / max(len(a), len(b))


# Alef-family letters only: allowing ANY single-letter difference would make
# genuinely distinct words collide (e.g. 'الذي' / 'الذين'), whereas an extra
# alef is a systematic Quranic recitation/ASR confusion, not a different word.
_ALEF_VARIANTS = frozenset("اٱآأإٰ")


def _equal_modulo_one_alef(a: str, b: str) -> bool:
    """True when the words differ only by exactly one inserted alef."""
    if a == b:
        return True
    if abs(len(a) - len(b)) != 1:
        return False
    short, long_ = (a, b) if len(a) < len(b) else (b, a)
    for index, char in enumerate(long_):
        if char in _ALEF_VARIANTS and long_[:index] + long_[index + 1 :] == short:
            return True
    return False


MATCH_SIMILARITY_THRESHOLD = 0.80
LIVE_MATCH_CONFIDENCE_THRESHOLD = 0.55
LOOKAHEAD = 3
WINDOW_SIZE = 15

# --- Live DP alignment (Tarteel-style anchor + local window) ----------------
# Reference words searched ahead of the anchor on a normal pass. Mirrors
# Tarteel's "tracking mode": a local window keeps alignment fast and stops the
# tracker from jumping across the surah on one noisy window.
#
# CLAMPED (2026-09-26). This used to be WINDOW_SIZE (15). The live DP commits
# every reference word up to its LAST CONFIDENT MATCH as SKIPPED, so a large
# reach turns one lucky anchor into a cascade of red marks — observed live as
# the cursor jumping from ayah 2 to a word in ayah 6, painting the rest red.
# The user's contract: never search more than MAX_MATCH_LOOKAHEAD words past
# the last confirmed word.
LIVE_SEARCH_REACH = MAX_MATCH_LOOKAHEAD = 3
# Widened reach used once the tracker has stalled (Tarteel's "search mode"):
# recovers the position after a skipped/repeated passage instead of freezing.
#
# CLAMPED (2026-09-26): this was 30. Leaving it wide while clamping the normal
# reach would have been a TRAP, not a fix — every genuine multi-word skip would
# push `_stall_passes >= LIVE_LOW_CONF_STREAK` and route straight into the wide
# search, reintroducing the exact long-distance jump we are removing. Bounded
# recovery only: enough to re-find the position after a pause, never enough to
# cross several short ayahs. Override with QARI_LIVE_REACH / QARI_LIVE_REACH_WIDE.
LIVE_SEARCH_REACH_WIDE = int(os.environ.get("QARI_LIVE_REACH_WIDE", "8"))
# Consecutive no-progress passes after which the wide search engages.
LIVE_LOW_CONF_STREAK = 2
# How many ayahs past the active one the live window may reach. The user-facing
# rule is "active_ayah_idx ± 1": a match one ayah ahead is plausible speech
# (the reciter is mid-transition), a match several ayahs ahead is not.
# Applied as a HARD ceiling on the window, so it bounds the cursor no matter how
# generous the word-count reach is. Set 0 to disable the ayah clamp.
AYAH_LOOKAHEAD = int(os.environ.get("QARI_AYAH_LOOKAHEAD", "1"))
# DP scores. A match must out-weigh a handful of skipped reference words so the
# alignment only jumps ahead when there is real evidence (>=2 matching words),
# never on a single lucky fuzzy hit.
DP_MATCH_SCORE = 2.0
DP_MISMATCH_SCORE = -2.0
# Skipping a reference word is deliberately expensive. The DP picks the BEST
# PARTIAL alignment, so a heavy skip cost makes it stop at the last confident
# match and wait for better evidence instead of jumping over the words the ASR
# happened to miss in one window and committing them as SKIPPED (they are
# usually recovered by the next, overlapping window). A genuine skip still wins:
# one skipped word + one later match is +2.0 - 1.5 > 0, so the tracker moves on.
DP_SKIP_REF_PENALTY = -1.5
DP_INSERT_PENALTY = -0.4
# Newest hypothesis tokens considered per pass. Bounds the DP and drops stale
# garbage from earlier passes (the cumulative hypothesis is append-only).
DP_HYP_TAIL = 48

# Verbose live-alignment diagnostics (enable with QARI_STREAM_DEBUG=1).
_DEBUG = os.environ.get("QARI_STREAM_DEBUG", "").lower() in ("1", "true", "yes")


class StreamingMatcher:
    """Incrementally align a cumulative ASR hypothesis to a Quran reference.

    Live mode shows what the user actually said: a word turns green only when a
    confident token aligns to it, and a reference word the reciter passed over
    (skipped / mispronounced) is reported SKIPPED so the client can tint it red
    in real time. Words the reciter has not reached yet stay pending.

    Final review mode retains richer error/skip classification for the summary
    after recording has stopped.
    """

    def __init__(
        self,
        reference_words: list[str],
        *,
        match_threshold: float = MATCH_SIMILARITY_THRESHOLD,
        live_confidence_threshold: float = LIVE_MATCH_CONFIDENCE_THRESHOLD,
        lookahead: int = LOOKAHEAD,
        window_size: int = WINDOW_SIZE,
        phonetic_threshold: float = PHONETIC_MATCH_THRESHOLD,
        use_phonetic: bool = True,
        ayah_boundaries: Optional[list[dict]] = None,
        ayah_lookahead: int = AYAH_LOOKAHEAD,
    ) -> None:
        self.reference = list(reference_words)
        self.match_threshold = match_threshold
        self.live_confidence_threshold = max(0.0, min(1.0, live_confidence_threshold))
        self.lookahead = max(0, lookahead)
        self.window_size = max(1, window_size)
        self.phonetic_threshold = phonetic_threshold
        self.use_phonetic = use_phonetic
        self.ayah_lookahead = max(0, ayah_lookahead)
        # Global word-index ranges per ayah, as (start, end_inclusive) pairs
        # sorted by start. Empty when the caller has no ayah metadata, in which
        # case the ayah clamp is simply inert (word-count reach still applies).
        self._ayah_ranges: list[tuple[int, int]] = []
        for b in sorted(
            ayah_boundaries or [],
            key=lambda d: int(d.get("word_index_end", -1)),
        ):
            try:
                end = int(b["word_index_end"])
                count = int(b.get("word_count", 0) or 0)
            except (KeyError, TypeError, ValueError):
                continue
            if end < 0:
                continue
            self._ayah_ranges.append((max(0, end - max(0, count - 1)), end))
        # Anchor: the number of reference words already resolved. Live alignment
        # never re-opens words below it, so the reveal is monotonic.
        self._cursor = 0
        self._hyp_cursor = 0
        self._resolved: dict[int, WordStatus] = {}
        self._resolved_states: list[WordState] = []
        # Consecutive evaluate() passes where the anchor made no progress.
        # Drives the wide "search mode" (see _evaluate_live).
        self._stall_passes = 0
        # Last DP internals, populated only when QARI_STREAM_DEBUG is set.
        self._last_dp_debug: dict[str, object] = {}

    def _ayah_of(self, index: int) -> int:
        """Index of the ayah containing global word `index` (-1 if unknown)."""
        for i, (start, end) in enumerate(self._ayah_ranges):
            if start <= index <= end:
                return i
        return -1

    def _ayah_ceiling(self, anchor: int, reference_count: int) -> int:
        """Exclusive upper bound on the live window from the ayah clamp.

        Allows the window to reach into ayah `active + ayah_lookahead` only. With
        the default of 1 that is the "active_ayah_idx +/- 1" rule: a match one
        ayah ahead is plausible, a match several ayahs ahead is not — which is
        what stops the ayah-2 -> ayah-6 jump.
        """
        if not self._ayah_ranges or self.ayah_lookahead <= 0:
            return reference_count
        active = self._ayah_of(anchor)
        if active < 0:
            return reference_count
        target = min(active + self.ayah_lookahead, len(self._ayah_ranges) - 1)
        return min(reference_count, self._ayah_ranges[target][1] + 1)

    def _is_match(self, hypothesis: str, reference: str) -> bool:
        if not hypothesis or not reference:
            return False
        if hypothesis == reference:
            return True
        if char_similarity(hypothesis, reference) >= self.match_threshold:
            return True
        # Quranic liaison: a word that loses its leading article inside the
        # recitation flow (e.g. reference 'صرط' spoken as the close token
        # 'الصرط') never clears the 0.80 similarity bar on its own. If the
        # article-stripped forms are IDENTICAL this is a match, not a guess.
        if self._strip_article(hypothesis) == self._strip_article(reference):
            return True
        # Quranic liaison via an EXTRA ALEF: the reciter merges words in flow and
        # the ASR emits the connecting alef (reference 'صرط' heard as 'صراط',
        # 'الرحمن' as 'الرحمان'). On a 3-4 letter word that single alef keeps the
        # similarity at 0.75 — under the 0.80 bar — so the word could NEVER match
        # and the tracker skipped it as a mistake. If the only difference is one
        # alef it is the same word.
        if _equal_modulo_one_alef(hypothesis, reference):
            return True
        return self.use_phonetic and (
            phonetic_similarity(hypothesis, reference) >= self.phonetic_threshold
        )

    @staticmethod
    def _strip_article(word: str) -> str:
        return word[2:] if len(word) > 4 and word.startswith("ال") else word

    def evaluate(
        self,
        hypothesis_words: list[str],
        confidences: Optional[list[float]] = None,
        *,
        full: bool = False,
    ) -> list[WordState]:
        if full:
            return self._evaluate_full(hypothesis_words, confidences)
        return self._evaluate_live(hypothesis_words, confidences)

    # ------------------------------------------------------------------
    # Live alignment
    # ------------------------------------------------------------------
    def _evaluate_live(
        self,
        hypothesis_words: list[str],
        confidences: Optional[list[float]] = None,
    ) -> list[WordState]:
        """Align the recent ASR tokens to a local window of reference words.

        A Needleman-Wunsch DP over (reference window x hypothesis tail) chooses
        the best *partial* alignment, so:
          * an inserted/hallucinated token is consumed as an insertion,
          * the expected word's missing token (window-cut fragment, echo, or a
            swallowed word) becomes a single skipped REFERENCE word instead of
            jamming the cursor,
          * trailing reference words with no evidence stay pending (the user
            has simply not recited them yet).
        Only reference words up to the LAST matched pair are committed; anything
        after it is left for a later pass, which is what keeps the live reveal
        honest — a word only goes green on evidence, and only goes red once the
        reciter has demonstrably moved past it.
        """
        reference = self.reference
        reference_count = len(reference)
        anchor = self._cursor
        if anchor >= reference_count:
            return list(self._resolved_states)

        wide = self._stall_passes >= LIVE_LOW_CONF_STREAK
        reach = LIVE_SEARCH_REACH_WIDE if wide else min(self.window_size, LIVE_SEARCH_REACH)
        win_start = anchor
        # Two independent ceilings on the live window:
        #   1. word-count reach from the last confirmed word (LIVE_SEARCH_REACH)
        #   2. the ayah clamp — never past ayah `active + ayah_lookahead`
        # Both must hold, so the cursor cannot be dragged several ayahs ahead by
        # one noisy window. The second is what removes the long-distance false
        # anchor (ayah 2 -> ayah 6) that cascaded red marks across the surah.
        ceiling = self._ayah_ceiling(anchor, reference_count)
        win_end = min(anchor + reach, ceiling, reference_count)
        if win_end <= win_start:
            # The clamp is tighter than the reach: the reciter is at the end of
            # the allowed ayah span. Hold the cursor (the next pass re-aligns
            # with fresh audio) rather than cascade skips to the rest of the
            # surah. This is the ayah-boundary "pause in active state" rule.
            self._stall_passes += 1
            return list(self._resolved_states)
        ref_win = reference[win_start:win_end]
        m = len(ref_win)

        total = len(hypothesis_words)
        hyp_start = min(self._hyp_cursor, total)
        # Keep only the newest tokens: the cumulative hypothesis is append-only,
        # so older unmatched tokens are stale noise.
        if total - hyp_start > DP_HYP_TAIL:
            hyp_start = total - DP_HYP_TAIL
        hyp = list(hypothesis_words[hyp_start:])
        k = len(hyp)

        if m == 0 or k == 0:
            if anchor < reference_count:
                self._stall_passes += 1
            return list(self._resolved_states)

        def confidence(j: int) -> float:
            absolute = hyp_start + j
            if confidences is not None and 0 <= absolute < len(confidences):
                return float(confidences[absolute])
            return 1.0

        def paired(i: int, j: int) -> bool:
            return confidence(j) >= self.live_confidence_threshold and self._is_match(
                hyp[j], ref_win[i]
            )

        NEG = float("-inf")
        dp = [[NEG] * (k + 1) for _ in range(m + 1)]
        dp[0][0] = 0.0
        for j in range(1, k + 1):
            dp[0][j] = dp[0][j - 1] + DP_INSERT_PENALTY
        for i in range(1, m + 1):
            dp[i][0] = dp[i - 1][0] + DP_SKIP_REF_PENALTY
        for i in range(1, m + 1):
            prev_row = dp[i - 1]
            row = dp[i]
            for j in range(1, k + 1):
                pair = prev_row[j - 1] + (
                    DP_MATCH_SCORE if paired(i - 1, j - 1) else DP_MISMATCH_SCORE
                )
                skip = prev_row[j] + DP_SKIP_REF_PENALTY
                insert = row[j - 1] + DP_INSERT_PENALTY
                row[j] = max(pair, skip, insert)

        # Best partial alignment: trailing unaligned regions are intentionally
        # left pending rather than forced through the DP.
        best = 0.0
        best_i = best_j = 0
        for i in range(m + 1):
            row = dp[i]
            for j in range(k + 1):
                if row[j] > best:
                    best = row[j]
                    best_i, best_j = i, j
        if best <= 0.0:
            self._stall_passes += 1
            return list(self._resolved_states)

        ops: list[tuple[str, int, int]] = []
        i, j = best_i, best_j
        while i > 0 or j > 0:
            if i > 0 and j > 0:
                pair = dp[i - 1][j - 1] + (
                    DP_MATCH_SCORE if paired(i - 1, j - 1) else DP_MISMATCH_SCORE
                )
                if dp[i][j] == pair:
                    ops.append(("pair", i - 1, j - 1))
                    i -= 1
                    j -= 1
                    continue
            if i > 0 and dp[i][j] == dp[i - 1][j] + DP_SKIP_REF_PENALTY:
                ops.append(("skip", i - 1, -1))
                i -= 1
                continue
            ops.append(("insert", -1, j - 1))
            j -= 1
        ops.reverse()

        last_match_i = -1
        last_match_j = -1
        for kind, ii, jj in ops:
            if kind == "pair" and paired(ii, jj):
                last_match_i = ii
                last_match_j = jj
        if last_match_i < 0:
            # Heard something, but nothing that confidently anchors to this
            # window: hold position (the next pass re-aligns with fresh audio).
            self._stall_passes += 1
            return list(self._resolved_states)

        for kind, ii, jj in ops:
            if ii < 0 or ii > last_match_i:
                continue
            index = win_start + ii
            if index in self._resolved:
                continue
            if kind == "pair" and paired(ii, jj):
                self._resolved_states.append(
                    WordState(
                        index,
                        reference[index],
                        WordStatus.MATCHED,
                        hyp[jj],
                        confidence(jj),
                    )
                )
            else:
                # Reference word the reciter moved past without a confident
                # match — skipped / mispronounced. Reported live so it can be
                # tinted red (real-time mistake signal). The final review
                # re-scores the whole audio, so a noisy live call cannot corrupt
                # the summary verdict.
                self._resolved_states.append(
                    WordState(index, reference[index], WordStatus.SKIPPED, "", 0.0)
                )

        if _DEBUG:
            # Exposed for the session's QARI_STREAM_DEBUG log block (this module
            # is imported by ml tooling too, so it must not depend on the API's
            # structlog logger).
            self._last_dp_debug = {
                "anchor": anchor,
                "win": f"{win_start}-{win_end}",
                "hyp_start": hyp_start,
                "k": k,
                "best": round(best, 2),
                "best_ij": f"{best_i},{best_j}",
                "last_match": f"{last_match_i},{last_match_j}",
                "unconsumed": " ".join(hyp[last_match_j + 1 : last_match_j + 8]),
            }
        self._cursor = win_start + last_match_i + 1
        # Consume tokens only up to the LAST MATCHED pair. Tokens after it stay
        # available for the next pass: a trailing token that looks like noise now
        # is often the beginning of the next word (e.g. the ASR emits 'صراط' one
        # window before the reference 'صرط' can be matched). Consuming the whole
        # alignment endpoint ate that evidence and pinned the anchor at the
        # ayah-6 -> 7 boundary (verified live: cursor stuck at 20/29 while the
        # audio kept going).
        self._hyp_cursor = min(hyp_start + last_match_j + 1, total)
        for state in self._resolved_states:
            self._resolved[state.index] = state.status
        self._stall_passes = 0
        return list(self._resolved_states)

    # ------------------------------------------------------------------
    # Final review
    # ------------------------------------------------------------------
    def _evaluate_full(
        self,
        hypothesis_words: list[str],
        confidences: Optional[list[float]] = None,
    ) -> list[WordState]:
        """Classify substitutions and short skips after the session ended."""
        i = self._cursor
        prev_cursor = self._cursor
        j = min(self._hyp_cursor, len(hypothesis_words))
        reference_count = len(self.reference)
        hypothesis_count = len(hypothesis_words)
        window_end = reference_count

        def confidence(index: int) -> float:
            if confidences is not None and 0 <= index < len(confidences):
                return float(confidences[index])
            return 1.0

        while i < window_end and j < hypothesis_count:
            spoken = hypothesis_words[j]
            expected = self.reference[i]

            if self._is_match(spoken, expected):
                self._resolved_states.append(
                    WordState(i, expected, WordStatus.MATCHED, spoken, confidence(j))
                )
                i += 1
                j += 1
                continue

            skip_search_end = min(window_end, i + 1 + self.lookahead)
            skip_to = self._find_ref(spoken, i + 1, skip_search_end)
            if skip_to is not None:
                for index in range(i, skip_to):
                    self._resolved_states.append(
                        WordState(index, self.reference[index], WordStatus.SKIPPED)
                    )
                self._resolved_states.append(
                    WordState(
                        skip_to,
                        self.reference[skip_to],
                        WordStatus.MATCHED,
                        spoken,
                        confidence(j),
                    )
                )
                i = skip_to + 1
                j += 1
                continue

            insertion_search_end = j + 1 + self.lookahead
            insertion_to = self._find_hyp(
                expected,
                hypothesis_words,
                j + 1,
                insertion_search_end,
            )
            if insertion_to is not None:
                j = insertion_to
                continue

            self._resolved_states.append(
                WordState(i, expected, WordStatus.ERROR, spoken, confidence(j))
            )
            i += 1
            j += 1

        self._cursor = i
        self._hyp_cursor = min(j, hypothesis_count)
        for state in self._resolved_states:
            self._resolved[state.index] = state.status
        if i > prev_cursor:
            self._stall_passes = 0
        return list(self._resolved_states)

    def _find_ref(self, word: str, start: int, end: int) -> Optional[int]:
        for index in range(start, min(len(self.reference), end)):
            if self._is_match(word, self.reference[index]):
                return index
        return None

    def _find_hyp(
        self,
        word: str,
        hypothesis: list[str],
        start: int,
        end: int,
    ) -> Optional[int]:
        for index in range(start, min(len(hypothesis), end)):
            if self._is_match(hypothesis[index], word):
                return index
        return None

    def finalize(
        self,
        hypothesis_words: list[str],
        confidences: Optional[list[float]] = None,
    ) -> list[WordState]:
        # Final hypothesis is authoritative: re-score from scratch over the
        # whole reference (live cursors are not reused).
        self._cursor = 0
        self._hyp_cursor = 0
        self._resolved.clear()
        self._resolved_states.clear()
        self.evaluate(hypothesis_words, confidences, full=True)
        state_by_index = {state.index: state for state in self._resolved_states}
        final_states: list[WordState] = []
        for index, expected in enumerate(self.reference):
            state = state_by_index.get(index)
            final_states.append(
                WordState(
                    index=index,
                    expected=expected,
                    status=self._resolved.get(index, WordStatus.SKIPPED),
                    spoken=state.spoken if state is not None else None,
                    confidence=state.confidence if state is not None else 1.0,
                )
            )
        return final_states
