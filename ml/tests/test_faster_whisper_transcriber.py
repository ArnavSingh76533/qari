"""Unit tests for the Faster-Whisper live transcriber."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from ml.inference.faster_whisper_transcriber import (
    FasterWhisperTranscriber,
    get_transcriber,
    resolve_model_dir,
)


class _FakeWord:
    def __init__(
        self,
        word: str,
        probability: float | None,
        start: float = 0.0,
        end: float = 0.0,
    ) -> None:
        self.word = word
        self.probability = probability
        self.start = start
        self.end = end


class _FakeSegment:
    def __init__(self, words) -> None:
        self.words = words


class _FakeModel:
    def __init__(self, *segments) -> None:
        self._segments = segments

    def transcribe(self, *args, **kwargs):
        return list(self._segments), MagicMock()


def _patch_model(fake: _FakeModel):
    # qari-env does not ship faster_whisper; register a stand-in module so the
    # lazy `from faster_whisper import WhisperModel` inside transcriber.load()
    # resolves to the patched fake. Environment shim only, no logic change.
    import sys
    import types

    module = sys.modules.get("faster_whisper")
    if module is None:
        module = types.ModuleType("faster_whisper")
        sys.modules["faster_whisper"] = module
    if not hasattr(module, "WhisperModel"):
        module.WhisperModel = MagicMock()
    return patch("faster_whisper.WhisperModel", return_value=fake)


def test_resolve_model_dir_env_override(monkeypatch):
    monkeypatch.setenv("QARI_FASTERWHISPER_MODEL_DIR", "/tmp/custom-ct2")
    assert resolve_model_dir() == "/tmp/custom-ct2"
    assert resolve_model_dir("/explicit") == "/explicit"


def test_transcribe_extracts_words_and_confidences():
    fake = _FakeModel(
        _FakeSegment([_FakeWord("بِسْمِ", 0.91), _FakeWord("اللَّهِ", 0.88)]),
        _FakeSegment([_FakeWord("الرَّحْمَنِ", 0.80)]),
    )
    tx = FasterWhisperTranscriber(model_dir="/tmp/model")
    with _patch_model(fake):
        tx.load()
        words, confs = tx.transcribe([0.0] * 1600, 16000)
    assert words == ["بِسْمِ", "اللَّهِ", "الرَّحْمَنِ"]
    assert confs == [0.91, 0.88, 0.80]


def test_zero_probability_is_not_promoted_to_one():
    fake = _FakeModel(_FakeSegment([_FakeWord("خطأ", 0.0)]))
    tx = FasterWhisperTranscriber(model_dir="/tmp/model")
    with _patch_model(fake):
        tx.load()
        words, confs = tx.transcribe([0.1] * 1600, 16000)
    assert words == ["خطأ"]
    assert confs == [0.0]


def test_missing_probability_defaults_to_one():
    fake = _FakeModel(_FakeSegment([_FakeWord("بسم", None)]))
    tx = FasterWhisperTranscriber(model_dir="/tmp/model")
    with _patch_model(fake):
        tx.load()
        _, confs = tx.transcribe([0.1] * 1600, 16000)
    assert confs == [1.0]


def test_transcribe_with_timings_preserves_zero_probability():
    fake = _FakeModel(
        _FakeSegment([_FakeWord("بسم", 0.0, start=0.25, end=0.75)])
    )
    tx = FasterWhisperTranscriber(model_dir="/tmp/model")
    with _patch_model(fake):
        tx.load()
        words, confs, starts, ends = tx.transcribe_with_timings(
            [0.1] * 1600, 16000
        )
    assert words == ["بسم"]
    assert confs == [0.0]
    assert starts == [250]
    assert ends == [750]


def test_transcribe_empty_audio_returns_empty():
    tx = FasterWhisperTranscriber(model_dir="/tmp/model")
    with _patch_model(_FakeModel()):
        tx.load()
        words, confs = tx.transcribe([], 16000)
    assert words == []
    assert confs == []


def test_singleton_returns_same_instance():
    import ml.inference.faster_whisper_transcriber as module

    module._transcriber_singleton = None
    first = get_transcriber()
    second = get_transcriber()
    assert first is second
    module._transcriber_singleton = None
