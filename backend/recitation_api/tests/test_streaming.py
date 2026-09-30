"""Tests for the real-time streaming recitation WebSocket."""

import pytest
from fastapi.testclient import TestClient

import app.services.streaming_session as ss
from app.main import app
from tests.support import auth_headers


REFERENCE = ["بسم", "الله", "الرحمن", "الرحيم"]
REFERENCE_ENTRIES = [
    {"text_with_tashkeel": w, "clean_text": w} for w in REFERENCE
]


@pytest.fixture
def stub_stream(monkeypatch):
    """Force stub transcriber + a fixed reference so the WS is model-free."""
    monkeypatch.setattr(
        ss,
        "resolve_reference_words_sequence",
        lambda ayah_refs: (REFERENCE, REFERENCE, "https://example/ref.mp3", REFERENCE_ENTRIES, []),
    )
    monkeypatch.setattr(ss.settings, "ml_use_stub", True, raising=False)
    # Don't touch Redis in tests.
    async def _noop(self, result, audio_path):
        return None
    monkeypatch.setattr(ss.StreamingRecitationSession, "_persist", _noop)
    yield


def _pcm_seconds(seconds: float, sr: int = 16000, *, silent: bool = False) -> bytes:
    """Generate PCM16 bytes for `seconds` of audio at `sr` Hz.

    By default produces a low-amplitude but non-silent tone (RMS well above
    SILENCE_RMS_THRESHOLD) so the stub transcriber's silence gate lets words
    through. Pass ``silent=True`` for pure-zero PCM (e.g. testing the silence
    gate itself).
    """
    import math

    n = int(seconds * sr)
    if silent:
        return b"\x00\x00" * n
    # A 440 Hz sine at ~0.3 amplitude — well above the silence threshold.
    samples = [int(0.3 * 32767 * math.sin(2 * math.pi * 440 * i / sr)) for i in range(n)]
    import struct

    return struct.pack(f"<{n}h", *samples)


def test_stream_handshake_sends_ready(stub_stream):
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "start", "surah_number": 1, "ayah_number": 1,
                      "mode": "memorization"})
        ready = ws.receive_json()
        assert ready["type"] == "ready"
        assert ready["word_count"] == 4
        # Blueprint word-level model: word_id, sequence_index, text_with_tashkeel,
        # clean_text, state.
        words = ready["words"]
        assert len(words) == 4
        assert [w["text_with_tashkeel"] for w in words] == REFERENCE
        assert words[0]["word_id"] == 1
        assert words[0]["sequence_index"] == 1
        assert words[0]["state"] == "active"
        assert words[1]["state"] == "hidden"
        ws.send_json({"type": "stop"})
        # Drain until the final message.
        final = _recv_until(ws, "final")
        assert final["result"]["session_id"] == ready["session_id"]


def test_stream_reveals_words_live(stub_stream):
    """Streaming audio produces word 'match' events as words are revealed."""
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "start", "surah_number": 1, "ayah_number": 1})
        ready = ws.receive_json()
        assert ready["type"] == "ready"

        # ~5s of audio → stub reveals min(4, floor(5/0.9)) = 4 words.
        ws.send_bytes(_pcm_seconds(5.0))

        matched = []
        # Collect the word events emitted for this chunk.
        for index in range(4):
            if index == 3:
                # The live matcher resolves at most three reference words in
                # its first window; another audio interval advances the tail.
                ws.send_bytes(_pcm_seconds(1.3))
            evt = ws.receive_json()
            assert evt["type"] == "word"
            # Blueprint wire status is "match" (not "matched").
            assert evt["status"] == "match"
            assert "word_id" in evt and evt["word_id"] == evt["word_index"] + 1
            matched.append(evt["word_index"])
        assert matched == [0, 1, 2, 3]

        ws.send_json({"type": "stop"})
        final = _recv_until(ws, "final")
        result = final["result"]
        assert result["accuracy_score"] == 1.0
        assert len(result["word_verdicts"]) == 4
        assert all(v["is_correct"] for v in result["word_verdicts"])


def test_stream_final_marks_unrecited_skipped(stub_stream):
    """Stopping early leaves un-recited words flagged (not falsely correct)."""
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "start", "surah_number": 1, "ayah_number": 1})
        ws.receive_json()  # ready
        ws.send_bytes(_pcm_seconds(1.6))  # ~1 word revealed
        # There may be a word event; drain then stop.
        ws.send_json({"type": "stop"})
        final = _recv_until(ws, "final")
        verdicts = final["result"]["word_verdicts"]
        assert len(verdicts) == 4
        skipped = [v for v in verdicts if v["error_type"] == "skipped"]
        assert len(skipped) >= 1


def test_stream_silence_does_not_auto_complete_ayah(stub_stream):
    """Pure silence must NOT reveal words or auto-complete the ayah.

    This is the regression test for the bug where the stub transcriber revealed
    words based on audio duration alone — so room tone / breath accumulated and
    the ayah completed even though the user said nothing.
    """
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "start", "surah_number": 1, "ayah_number": 1})
        ws.receive_json()  # ready
        # Send 10 seconds of SILENT audio — well past the threshold that would
        # normally reveal all 4 words via the stub.
        ws.send_bytes(_pcm_seconds(10.0, silent=True))
        # Stop first, then drain: with silence the server emits NO word event, so
        # draining before `stop` would block forever on receive_json().
        ws.send_json({"type": "stop"})
        word_events = []
        final = None
        try:
            while True:
                evt = ws.receive_json()
                if evt.get("type") == "word":
                    word_events.append(evt)
                if evt.get("type") == "final":
                    final = evt
                    break
        except Exception:
            pass  # no more events (timeout / connection close)
        assert word_events == [], (
            f"Silence should not reveal words, got {len(word_events)} events"
        )
        assert final is not None
        verdicts = final["result"]["word_verdicts"]
        assert len(verdicts) == 4
        # All words should be skipped (none recited).
        skipped = [v for v in verdicts if v["error_type"] == "skipped"]
        assert len(skipped) == 4


def test_stream_requires_start_first(stub_stream):
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "audio"})  # wrong first message
        msg = ws.receive_json()
        assert msg["type"] == "error"


def test_stream_multi_ayah_sequence(stub_stream):
    """An explicit `ayahs` list is concatenated into one continuous word list."""
    client = TestClient(app, headers=auth_headers())
    with client.websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({
            "type": "start",
            "ayahs": [[1, 1], [1, 2]],
            "mode": "memorization",
        })
        ready = ws.receive_json()
        assert ready["type"] == "ready"
        # The stub ignores the refs and returns the 4-word REFERENCE list.
        assert ready["word_count"] == 4
        assert [w["text_with_tashkeel"] for w in ready["words"]] == REFERENCE
        ws.send_json({"type": "stop"})
        _recv_until(ws, "final")


def _recv_until(ws, msg_type, limit=50):
    for _ in range(limit):
        msg = ws.receive_json()
        if msg.get("type") == msg_type:
            return msg
    raise AssertionError(f"did not receive '{msg_type}' message")


# ---------------------------------------------------------------------------
# Sliding-window transcription (lag fix)
# ---------------------------------------------------------------------------

def test_stitch_hypothesis_empty_prefix():
    words, confs = ss.stitch_hypothesis([], [], ["a", "b"], [0.9, 0.9])
    assert words == ["a", "b"]
    assert confs == [0.9, 0.9]


def test_stitch_hypothesis_dedups_overlap():
    """A new window that re-contains the prefix tail must not double-count."""
    words, confs = ss.stitch_hypothesis(
        ["a", "b", "c"], [1, 1, 1], ["b", "c", "d", "e"], [1, 1, 2, 2]
    )
    assert words == ["a", "b", "c", "d", "e"]
    assert confs == [1, 1, 1, 2, 2]


def test_stitch_hypothesis_no_overlap_appends_all():
    words, _ = ss.stitch_hypothesis(["a", "b"], [1, 1], ["c", "d"], [1, 1])
    assert words == ["a", "b", "c", "d"]


def test_stitch_hypothesis_fuzzy_overlap_dedups():
    """Re-transcription rarely emits byte-identical tokens across passes, so the
    overlap must be found on a *similarity* basis — otherwise every window is
    appended again and the hypothesis explodes (matcher races past the user)."""
    words, _ = ss.stitch_hypothesis(
        ["بسم", "الله", "الرحمن"], [1, 1, 1],
        ["الله", "الرحمن", "الرحيم"], [1, 1, 1],
    )
    assert words == ["بسم", "الله", "الرحمن", "الرحيم"]


def test_stitch_hypothesis_window_fully_contained():
    """If the whole window is already in the prefix, nothing new is added."""
    words, _ = ss.stitch_hypothesis(["a", "b", "c"], [1, 1, 1], ["b", "c"], [1, 1])
    assert words == ["a", "b", "c"]


def test_real_transcriber_uses_bounded_window(monkeypatch):
    """The real (non-stub) path transcribes only the recent window, and the
    stitched cumulative hypothesis grows across passes without double-counting."""
    monkeypatch.setattr(
        ss,
        "resolve_reference_words_sequence",
        lambda ayah_refs: (REFERENCE, REFERENCE, "https://example/ref.mp3", REFERENCE_ENTRIES, []),
    )
    monkeypatch.setattr(ss.settings, "ml_use_stub", False, raising=False)

    # Fake ASR: returns the words "spoken" in the audio window handed to it. We
    # encode the spoken word count in the audio length so we can simulate a
    # growing recitation window-by-window.
    calls = {"n": 0}

    def fake_transcriber(audio, sr):
        calls["n"] += 1
        # window 1 -> ["بسم","الله"]; window 2 (overlaps) -> ["الله","الرحمن"]
        if calls["n"] == 1:
            return ["بسم", "الله"], [0.9, 0.9]
        return ["الله", "الرحمن"], [0.9, 0.9]

    # The live pipeline corroborates the prompted decode against the INDEPENDENT
    # (unprompted) verification decode. Stub that too — otherwise the real base
    # model runs against the synthetic tone, its garbage output fails
    # corroboration and the hypothesis is replaced by that garbage. It returns
    # the superset so every prompted word is corroborated.
    monkeypatch.setattr(
        ss,
        "_independent_transcriber",
        lambda audio, sr: (["بسم", "الله", "الرحمن"], [0.9, 0.9, 0.9]),
    )

    import asyncio
    import math

    # Non-silent audio: a sine wave with real RMS energy, so the silence gate
    # (which drops pure `b"\x00\x00"` room tone) does not suppress the pass.
    def _tone(seconds, sr=16000, freq=220.0):
        import struct

        out = bytearray()
        for n in range(int(seconds * sr)):
            s = int(12000 * math.sin(2 * math.pi * freq * n / sr))
            out += struct.pack("<h", s)
        return bytes(out)

    async def run():
        sess = ss.StreamingRecitationSession(
            surah=1, ayah_from=1, ayah_to=1, transcriber=fake_transcriber
        )
        sess.load_reference()
        assert sess._is_stub is False
        # Feed >1.2s of audio so a pass triggers, then transcribe twice.
        sess.add_audio(_tone(3))
        await sess.maybe_transcribe(force=True)
        sess.add_audio(_tone(3))
        await sess.maybe_transcribe(force=True)
        # Cumulative hypothesis stitched, overlap "الله" deduped.
        assert sess._hypothesis == ["بسم", "الله", "الرحمن"]

    asyncio.run(run())


def test_silence_does_not_auto_complete_ayah(monkeypatch):
    """When the user says nothing, near-silent mic audio must NOT resolve any
    reference word — the ayah must NOT auto-complete on phantom ASR tokens."""
    monkeypatch.setattr(
        ss,
        "resolve_reference_words_sequence",
        lambda ayah_refs: (REFERENCE, REFERENCE, "https://example/ref.mp3", REFERENCE_ENTRIES, []),
    )
    monkeypatch.setattr(ss.settings, "ml_use_stub", False, raising=False)

    # A "real" transcriber that returns hallucinated words regardless of input
    # (simulating Whisper emitting tokens on silence).
    def fake_transcriber(audio, sr):
        return ["بسم", "الله", "الرحمن", "الرحيم"], [0.9, 0.9, 0.9, 0.9]

    import asyncio

    async def run():
        sess = ss.StreamingRecitationSession(
            surah=1, ayah_from=1, ayah_to=1, transcriber=fake_transcriber
        )
        sess.load_reference()
        # Pure silence: zeroed PCM. The silence gate must drop it.
        sess.add_audio(b"\x00\x00" * (16000 * 3))
        events = await sess.maybe_transcribe(force=True)
        assert events == [], "silence must not resolve any word"
        # No reference word should be marked resolved.
        assert sess._last_status == {}

    asyncio.run(run())


def test_missing_production_model_never_falls_back_to_duration_stub(monkeypatch):
    """A missing production model must fail, not reveal words on elapsed time."""
    monkeypatch.setattr(
        ss,
        "resolve_reference_words_sequence",
        lambda ayah_refs: (REFERENCE, REFERENCE, "", REFERENCE_ENTRIES, []),
    )
    monkeypatch.setattr(ss.settings, "ml_use_stub", False, raising=False)

    from ml.inference import faster_whisper_transcriber as fwt

    class BrokenTranscriber:
        def load(self):
            raise RuntimeError("model directory missing")

    monkeypatch.setattr(fwt, "get_transcriber", lambda: BrokenTranscriber())

    sess = ss.StreamingRecitationSession(surah=1, ayah_from=1, ayah_to=1)
    with pytest.raises(ss.LiveTranscriberUnavailable, match="temporarily unavailable"):
        sess.load_reference()
    assert sess._transcriber is None
    assert sess._is_stub is True  # default flag, but no stub was installed
