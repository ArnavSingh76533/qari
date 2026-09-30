"""Regression coverage for prompt echo and fabricated acoustic scores."""

import asyncio
import math
import struct
import wave
from types import SimpleNamespace

import pytest

from app.schemas.recitation import RecitationAnalysisResult
from app.workers import fast_inference_worker as worker
from ml.inference.faster_whisper_transcriber import FasterWhisperTranscriber
from ml.tajweed.reference_store import AyahReference, ReferenceStore, WordReference


EXPECTED = ["الحمد", "لله", "رب", "العالمين"]
HEARD = ["بسم", "الله", "الرحمن", "الرحيم"]


class _AudioModel:
    def __init__(self, *, oracle=False, heard=None):
        self.oracle = oracle
        self.heard = HEARD if heard is None else heard
        self.decode_calls = 0

    def transcribe(self, _samples, **options):
        self.decode_calls += 1
        # Mirrors the reported failure: an oracle echoes a provided reference
        # regardless of the audio. The independent model only reports HEARD.
        prompt = options.get("initial_prompt")
        words = prompt.split() if self.oracle and prompt else self.heard
        return [SimpleNamespace(words=[
            SimpleNamespace(word=word, probability=0.9, start=i * 0.2, end=(i + 1) * 0.2)
            for i, word in enumerate(words)
        ])], SimpleNamespace()


@pytest.fixture
def recording(tmp_path):
    path = tmp_path / "recitation.wav"
    samples = [int(6000 * math.sin(2 * math.pi * 220 * i / 16000)) for i in range(16000)]
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(struct.pack("<16000h", *samples))
    return path


@pytest.fixture
def batch_job(monkeypatch, recording):
    store = ReferenceStore()
    store.add(AyahReference(
        surah=1, ayah=2, text=" ".join(EXPECTED), normalized_text=" ".join(EXPECTED),
        words=[WordReference(word=word) for word in EXPECTED],
        reference_audio_url="https://example.test/reference.mp3",
    ))
    transcriber = FasterWhisperTranscriber(model_dir="/unused/oracle")
    transcriber._model = _AudioModel(oracle=True)
    transcriber._model_raw = _AudioModel(oracle=True)
    transcriber._model_verify = _AudioModel()
    monkeypatch.setattr(
        "ml.inference.faster_whisper_transcriber.get_transcriber", lambda: transcriber
    )
    monkeypatch.setattr(worker, "_get_reference_store", lambda: store)
    monkeypatch.setattr(worker, "_ensure_reference", lambda *_: True)
    monkeypatch.setattr(worker, "_pipeline", None)
    return {
        "session_id": "wrong-verse", "surah_number": 1,
        "ayah_from": 2, "ayah_to": 2,
        "audio_path": str(recording), "audio_duration_sec": 1,
    }


def test_wrong_verse_cannot_pass_by_echoing_the_expected_prompt(batch_job):
    result = asyncio.run(worker.run_fast_ml_inference(batch_job))

    assert result["overall_score"] < 1.0
    assert result["accuracy_score"] < 1.0
    assert [word["word"] for word in result["word_verdicts"]] == EXPECTED
    assert [word["actual_text"] for word in result["word_verdicts"]] == HEARD
    assert any(not word["is_correct"] for word in result["word_verdicts"])


def test_batch_confidence_is_from_recognizer_not_estimated_alignment(batch_job):
    result = asyncio.run(worker.run_fast_ml_inference(batch_job))

    assert [word["confidence"] for word in result["word_verdicts"]] == [0.9] * 4
    assert result["confidence"] == 0.9


def test_batch_word_timings_are_from_the_independent_recognizer(batch_job):
    result = asyncio.run(worker.run_fast_ml_inference(batch_job))
    serialized = RecitationAnalysisResult.model_validate(result).model_dump()

    assert [word.get("start_ms") for word in serialized["word_verdicts"]] == [0, 200, 400, 600]
    assert [word.get("end_ms") for word in serialized["word_verdicts"]] == [200, 400, 600, 800]


def test_fast_batch_marks_acoustic_metrics_unavailable(batch_job):
    result = asyncio.run(worker.run_fast_ml_inference(batch_job))
    serialized = RecitationAnalysisResult.model_validate(result).model_dump()

    for metric in ("tajweed", "pronunciation", "fluency"):
        assert serialized.get(f"{metric}_available") is False
        assert serialized[f"{metric}_score"] == 0.0


def test_missing_verification_model_fails_without_oracle_fallback(batch_job, monkeypatch):
    pipeline = worker._get_fast_pipeline()
    transcriber = pipeline.asr._transcriber
    transcriber._model_verify = None

    def unavailable():
        raise FileNotFoundError("Independent verification model is missing")

    monkeypatch.setattr(transcriber, "_model_verify_for", unavailable)
    with pytest.raises(FileNotFoundError, match="verification model is missing"):
        asyncio.run(worker.run_fast_ml_inference(batch_job))


def _set_range(batch_job, references, heard):
    pipeline = worker._get_fast_pipeline()
    for ayah, words in enumerate(references, start=2):
        pipeline.reference_store.add(AyahReference(
            surah=1, ayah=ayah, text=" ".join(words), normalized_text=" ".join(words),
            words=[WordReference(word=word) for word in words],
            reference_audio_url=f"https://example.test/{ayah}.mp3",
        ))
    pipeline.asr._transcriber._model_verify = _AudioModel(heard=heard)
    return {**batch_job, "ayah_to": 1 + len(references)}


def test_one_spoken_phrase_cannot_receive_credit_for_two_verses(batch_job):
    job = _set_range(batch_job, [HEARD, HEARD], HEARD)
    result = asyncio.run(worker.run_fast_ml_inference(job))

    assert result["overall_score"] == 0.5
    assert result["accuracy_score"] == 0.5
    verdicts = result["word_verdicts"]
    assert [word["word_index"] for word in verdicts] == list(range(8))
    assert sum(word["is_correct"] for word in verdicts) == 4
    assert sum(word["actual_text"] is None for word in verdicts) == 4
    heard_rows = [word for word in verdicts if word["actual_text"] is not None]
    assert [word["start_ms"] for word in heard_rows] == [0, 200, 400, 600]
    assert [word["confidence"] for word in heard_rows] == [0.9] * 4
    assert [word["reference_audio_url"] for word in verdicts] == (
        ["https://example.test/2.mp3"] * 4 + ["https://example.test/3.mp3"] * 4
    )


def test_verse_range_decodes_the_recording_once(batch_job):
    job = _set_range(batch_job, [HEARD, HEARD], HEARD)
    result = asyncio.run(worker.run_fast_ml_inference(job))

    assert worker._get_fast_pipeline().asr._transcriber._model_verify.decode_calls == 1
    assert len(result["word_verdicts"]) == 8


def test_reversed_verse_order_does_not_receive_full_credit(batch_job):
    first = ["الحمد", "لله"]
    second = ["رب", "العالمين"]
    job = _set_range(batch_job, [first, second], second + first)
    result = asyncio.run(worker.run_fast_ml_inference(job))

    assert result["accuracy_score"] < 1.0
    assert [word["word"] for word in result["word_verdicts"]] == first + second
    actual_rows = [word for word in result["word_verdicts"] if word["actual_text"] is not None]
    starts = [word["start_ms"] for word in actual_rows]
    assert starts == sorted(starts)


def test_missing_reference_keeps_known_verse_order_and_audio_urls(batch_job, monkeypatch):
    job = _set_range(batch_job, [HEARD, EXPECTED, HEARD], HEARD)
    monkeypatch.setattr(worker, "_ensure_reference", lambda _surah, ayah, _qari: ayah != 3)
    result = asyncio.run(worker.run_fast_ml_inference(job))

    assert result["accuracy_score"] == 0.5
    assert [word["word_index"] for word in result["word_verdicts"]] == list(range(8))
    assert [word["reference_audio_url"] for word in result["word_verdicts"]] == (
        ["https://example.test/2.mp3"] * 4 + ["https://example.test/4.mp3"] * 4
    )


def test_no_references_returns_unavailable_feedback_without_decoding(batch_job, monkeypatch):
    job = _set_range(batch_job, [HEARD, HEARD], HEARD)
    monkeypatch.setattr(worker, "_ensure_reference", lambda *_args: False)
    result = asyncio.run(worker.run_fast_ml_inference(job))

    assert result["word_verdicts"] == []
    assert result["confidence"] == 0.0
    assert "couldn't analyse" in result["feedback"]
    assert worker._get_fast_pipeline().asr._transcriber._model_verify.decode_calls == 0
    assert result["tajweed_available"] is False
