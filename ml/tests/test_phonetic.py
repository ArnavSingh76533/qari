"""Tests for ml.alignment.phonetic + its StreamingMatcher integration."""

from ml.alignment.phonetic import (
    PHONETIC_MATCH_THRESHOLD,
    phonetic_similarity,
    to_phonemes,
)
from ml.alignment.streaming_matcher import StreamingMatcher, WordStatus


class TestPhoneticSimilarity:
    def test_identical_words(self):
        assert phonetic_similarity("الرحمن", "الرحمن") == 1.0

    def test_diacritics_are_ignored(self):
        assert phonetic_similarity("بِسْمِ", "بسم") == 1.0

    def test_empty(self):
        assert phonetic_similarity("", "") == 1.0
        assert phonetic_similarity("بسم", "") == 0.0

    def test_emphatic_confusion_is_a_match(self):
        # ص recited/heard as س — same word phonetically (accent/ASR drift).
        assert phonetic_similarity("سراط", "صراط") >= PHONETIC_MATCH_THRESHOLD

    def test_taa_emphatic_confusion(self):
        assert phonetic_similarity("مستقيم", "مصتقيم") >= PHONETIC_MATCH_THRESHOLD

    def test_different_words_stay_apart(self):
        # Two REAL different Quran words must never collide (wrong-word
        # tracking is worse than a false red mark).
        assert phonetic_similarity("الرحمن", "الرحيم") < PHONETIC_MATCH_THRESHOLD

    def test_unrelated_words_are_far(self):
        assert phonetic_similarity("بسم", "قل") < 0.5

    def test_digits_do_not_poison(self):
        assert phonetic_similarity("بسم1", "بسم") == 1.0

    def test_phoneme_mapping_covers_word(self):
        assert len(to_phonemes("بسم")) == 3


class TestMatcherPhoneticIntegration:
    REF = ["بسم", "الله", "الرحمن", "الرحيم"]

    def test_emphatic_drift_matches(self):
        m = StreamingMatcher(["صراط", "الذين"])
        states = m.evaluate(["سراط"])
        assert states[0].status == WordStatus.MATCHED

    def test_wrong_word_still_flagged(self):
        m = StreamingMatcher(self.REF)
        # 'الرحيم' recited where 'الرحمن' is expected: the matcher must not
        # collide them phonetically — it is classified as a skip of الرحمن,
        # never a match for it.
        states = m.finalize(["بسم", "الله", "الرحيم"])
        by_idx = {s.index: s.status for s in states}
        assert by_idx[2] != WordStatus.MATCHED

    def test_phonetic_can_be_disabled(self):
        m = StreamingMatcher(["صراط"], use_phonetic=False)
        states = m.evaluate(["سراط"], full=True)
        # Without phonetics, a 1-char drift in a 4-char word (0.75 < 0.80)
        # is judged an error — the historical behaviour.
        assert states[0].status == WordStatus.ERROR
