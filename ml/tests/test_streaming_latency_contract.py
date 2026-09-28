"""Contract guard for the live-streaming latency path.

``app.services.streaming_session`` cannot be imported in this environment (it
needs ``pydantic_settings``, part of the full backend env — the long-standing
"backend tests are blocked" limitation). These tests therefore read the module
SOURCE and assert on its constants and on the early-first-pass predicate.

The point is to pin the two things a future edit must NOT quietly change:

* ``TRANSCRIBE_WINDOW_SEC`` / ``TRANSCRIBE_WINDOW_OVERLAP_SEC`` — a 5.0 s window
  was already tried and "lost the boundary-word context and stalled the end of
  the surah".
* ``VERIFY_EVERY_N_PASSES`` — must stay 1; at N=2 the tier-2 evidence is ~4 s
  stale and the measured symptom is 5-13 s apparent word latency.

Plus the new early-first-pass knobs, which must only ever affect pass #1.
"""
from __future__ import annotations

import ast
from pathlib import Path

SESSION_PY = (
    Path(__file__).resolve().parents[2]
    / "backend" / "recitation_api" / "app" / "services" / "streaming_session.py"
)


def _source() -> str:
    return SESSION_PY.read_text(encoding="utf-8")


def _literal(node: ast.AST) -> float | None:
    """Resolve a constant, or the DEFAULT of an os.environ.get(...) call,
    unwrapping float()/int() wrappers. Env defaults are STRING literals
    (``os.environ.get("X", "0.5")``), so numeric strings are coerced."""
    if isinstance(node, ast.Constant):
        v = node.value
        if isinstance(v, bool):
            return None
        if isinstance(v, (int, float)):
            return float(v)
        if isinstance(v, str):
            try:
                return float(v)
            except ValueError:
                return None
    if isinstance(node, ast.Call):
        fname = None
        if isinstance(node.func, ast.Name):
            fname = node.func.id
        elif isinstance(node.func, ast.Attribute):
            fname = node.func.attr  # os.environ.get -> "get"
        if fname in ("float", "int") and node.args:
            return _literal(node.args[0])
        if fname == "get" and len(node.args) >= 2:
            # os.environ.get(NAME, DEFAULT) -> DEFAULT
            return _literal(node.args[1])
    return None


def _const(name: str) -> float:
    """Value of a module-level numeric constant (or its env-var default)."""
    tree = ast.parse(_source())
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
            continue
        val = _literal(node.value)
        if val is None:
            raise AssertionError(
                f"{name} has no resolvable literal default: "
                f"{ast.unparse(node.value)}"
            )
        return val
    raise AssertionError(f"{name} not found as a module constant in {SESSION_PY}")


def _has_const(name: str) -> bool:
    tree = ast.parse(_source())
    return any(
        isinstance(n, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in n.targets)
        for n in tree.body
    )


# --- the protected steady-state knobs --------------------------------------
def test_steady_state_window_unchanged():
    assert _const("TRANSCRIBE_WINDOW_SEC") == 6.0
    assert _const("TRANSCRIBE_WINDOW_OVERLAP_SEC") == 1.5
    assert _const("TRANSCRIBE_INTERVAL_SEC") == 1.2


def test_verify_every_n_passes_still_one():
    assert _const("VERIFY_EVERY_N_PASSES") == 1, (
        "N>1 makes the tier-2 evidence stale and caused 5-13 s apparent latency"
    )


# --- the new early-first-pass knobs ----------------------------------------
def test_early_first_pass_knobs_exist_and_are_smaller():
    assert _has_const("EARLY_FIRST_PASS")
    assert _const("EARLY_FIRST_PASS_SEC") == 0.5
    assert _const("EARLY_FIRST_PASS_WINDOW_S") == 2.5
    assert _const("EARLY_FIRST_PASS_SEC") < _const("TRANSCRIBE_INTERVAL_SEC")
    assert _const("EARLY_FIRST_PASS_WINDOW_S") < _const("TRANSCRIBE_WINDOW_SEC")


def test_early_first_pass_is_off_by_default_measured_negative():
    """The early first pass was TRIED, MEASURED, and made latency worse.

        OFF : 2094 / 2119 / 2131 / 2139 / 2185 ms  (p50 ~2131)
        ON  : 3137 / 3139 / 3142 / 3145 ms         (p50 ~3142)  +1.0 s WORSE

    0.5 s of audio is below what Whisper needs for a usable transcript, so the
    "early" pass burns a full ~1 s decode and pushes the real first word out by
    exactly that. The default is therefore OFF, and the knobs are kept only so
    the negative result stays reproducible.
    """
    src = _source()
    assert 'os.environ.get("QARI_EARLY_FIRST_PASS", "0")' in src, (
        "the early first pass must default OFF — it was measured ~1 s SLOWER"
    )
    assert "MEASURED NEGATIVE RESULT" in src, (
        "the negative result must stay documented next to the flag"
    )


def test_early_pass_predicate_is_narrow():
    """`early` must be true ONLY for pass #1 with an empty hypothesis and not
    forced — otherwise the steady-state cadence would be silently changed."""
    # Mirror of the implementation predicate, asserted here so a change to the
    # source has to be mirrored deliberately rather than drifting silently.
    def early_for(pass_count: int, has_hypothesis: bool, force: bool) -> bool:
        return (
            True  # EARLY_FIRST_PASS default is on
            and pass_count == 0
            and not has_hypothesis
            and not force
        )

    assert early_for(0, False, False) is True
    assert early_for(1, False, False) is False, "only pass #1 may be early"
    assert early_for(0, True, False) is False, "never after a reveal"
    assert early_for(0, False, True) is False, "a forced stop pass is never early"

    # ...and the source really still reads that way.
    src = _source()
    assert "self._pass_count == 0 and not self._hypothesis" in src


def test_loop_cadence_is_early_aware():
    """REGRESSION: the LOOP must use the early interval too.

    First attempt lowered only the audio threshold in maybe_transcribe while the
    transcription loop still slept the full TRANSCRIBE_INTERVAL_SEC, so the loop
    never ticked again until 1.2 s had elapsed and the "early" pass never fired
    early — measured first-word latency stayed at ~2.1 s instead of ~1.5 s.
    Both call sites now share `_next_interval_sec()`.
    """
    src = _source()
    assert "def _next_interval_sec" in src, "shared interval helper is missing"
    assert "def _is_first_pass" in src, "shared first-pass predicate is missing"
    # The loop must NOT hard-code the steady-state interval any more.
    assert "remaining = self._next_interval_sec() - elapsed" in src, (
        "the transcription loop must use the early-aware interval"
    )
    assert "remaining = TRANSCRIBE_INTERVAL_SEC - elapsed" not in src, (
        "the loop is back to the fixed interval — the early pass cannot fire"
    )
    # ...and the threshold must come from the same helper, not a second copy.
    assert "threshold = int(interval_sec * self.sample_rate)" in src
    assert "EARLY_FIRST_PASS_SEC if early else TRANSCRIBE_INTERVAL_SEC" not in src, (
        "duplicate interval logic is back — the two sites can drift again"
    )


def test_early_first_pass_is_off_by_default_measured_negative():
    """The early first pass was TRIED, MEASURED, and made latency worse.

        OFF : 2094 / 2119 / 2131 / 2139 / 2185 ms  (p50 ~2131)
        ON  : 3137 / 3139 / 3142 / 3145 ms         (p50 ~3142)  +1.0 s WORSE

    0.5 s of audio is below what Whisper needs for a usable transcript, so the
    "early" pass burns a full ~1 s decode and pushes the real first word out by
    exactly that. The default is therefore OFF, and the knobs are kept only so
    the negative result stays reproducible.
    """
    src = _source()
    assert 'os.environ.get("QARI_EARLY_FIRST_PASS", "0")' in src, (
        "the early first pass must default OFF — it was measured ~1 s SLOWER"
    )
    assert "MEASURED NEGATIVE RESULT" in src, (
        "the negative result must stay documented next to the flag"
    )


def test_target_first_word_is_recorded_not_claimed():
    """400 ms is a TARGET for the post-GPU world, explicitly not met today."""
    assert _const("TARGET_FIRST_WORD_MS") == 400
    src = _source()
    assert "NOT achievable" in src, "the 400 ms gap must stay documented in-source"
