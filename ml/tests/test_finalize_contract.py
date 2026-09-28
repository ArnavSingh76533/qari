"""Final-review contract tests for StreamingMatcher.finalize().

Regression coverage for the 2026-09-17 finalize state fix: finalize() now
treats the passed cumulative hypothesis as authoritative and re-evaluates it
from scratch. Previously, live passes consumed unmatched ASR tokens and the
stale cursors made finalize lose substitutions and repaired words.
"""

from ml.alignment.streaming_matcher import StreamingMatcher, WordStatus

REF = ["بسم", "الله", "الرحمن", "الرحيم"]


def test_final_recovers_live_consumed_substitution():
    m = StreamingMatcher(REF)
    m.evaluate(REF[:2])
    hyp = REF[:2] + ["السلام"]
    live = m.evaluate(hyp)
    assert all(s.status == WordStatus.MATCHED for s in live)
    result = m.finalize(hyp, [0.9, 0.8, 0.7])
    assert result[2].status == WordStatus.ERROR
    assert result[2].spoken == "السلام"
    assert result[2].confidence == 0.7


def test_final_recovers_later_word_after_omission():
    m = StreamingMatcher(REF)
    hyp = REF[:2] + [REF[3]]
    m.evaluate(hyp)
    result = m.finalize(hyp)
    assert [s.status for s in result] == [WordStatus.MATCHED, WordStatus.MATCHED,
                                          WordStatus.SKIPPED, WordStatus.MATCHED]


def test_final_authoritative_revision_repairs_old_hypothesis():
    m = StreamingMatcher(REF)
    m.evaluate(REF[:2] + ["السلام"])
    result = m.finalize(REF)
    assert all(s.status == WordStatus.MATCHED for s in result)
    assert [s.spoken for s in result] == REF


def test_repeated_finalization_uses_latest_input():
    m = StreamingMatcher(REF)
    assert all(s.status == WordStatus.MATCHED for s in m.finalize(REF))
    result = m.finalize(REF[:2] + ["السلام"])
    assert result[2].status == WordStatus.ERROR
    assert result[3].status == WordStatus.SKIPPED


def test_live_clean_and_final_idempotent():
    m = StreamingMatcher(REF)
    for i in range(1, 5):
        assert len(m.evaluate(REF[:i])) == i
    result = m.finalize(REF)
    assert all(s.status == WordStatus.MATCHED for s in result)
    assert result == m.finalize(REF)


def test_final_empty_clears_previous_result():
    m = StreamingMatcher(REF)
    m.evaluate(REF)
    assert all(s.status == WordStatus.SKIPPED for s in m.finalize([]))


def test_final_overrides_forced_false_internal_state():
    """Direct state injection: corrupt live cursors/resolution must not leak
    into the authoritative final review result."""
    m = StreamingMatcher(REF)
    # Simulate a corrupted/false live transition: cursor raced ahead, one
    # reference word force-marked, hypothesis cursor past the end.
    m._cursor = len(REF)
    m._hyp_cursor = 99
    m._resolved = {2: WordStatus.ERROR}
    m._resolved_states = []
    result = m.finalize(REF)
    assert all(s.status == WordStatus.MATCHED for s in result)
    assert [s.spoken for s in result] == REF
    assert m._cursor == len(REF)
    assert m._hyp_cursor == len(REF)
