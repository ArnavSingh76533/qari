"""The batch verifier must return audio evidence without an expected-text prompt."""

from types import SimpleNamespace

from ml.inference.faster_whisper_transcriber import FasterWhisperTranscriber


class _VerificationModel:
    def transcribe(self, _samples, **options):
        # If expected text ever reaches this decoder, the oracle-like branch
        # produces a different transcript and the observable assertion fails.
        text = options.get("initial_prompt") or "بِسْمِ اللَّهِ"
        return [SimpleNamespace(words=[
            SimpleNamespace(word=text.split()[0], probability=0.0, start=0.1, end=0.3),
            SimpleNamespace(word=text.split()[1], probability=0.9, start=0.4, end=0.8),
        ])], SimpleNamespace()


def test_independent_batch_decode_preserves_word_evidence_and_timings():
    transcriber = FasterWhisperTranscriber(model_dir="/unused/oracle")
    transcriber._model_verify = _VerificationModel()
    decode = getattr(transcriber, "transcribe_independent_with_timings", None)
    assert callable(decode), "Independent batch verification needs a timestamped decode"

    words, confidences, starts, ends = decode([0.1] * 16000, 16000)

    assert words == ["بِسْمِ", "اللَّهِ"]
    assert confidences == [0.0, 0.9]
    assert starts == [100, 400]
    assert ends == [300, 800]


def test_empty_independent_batch_decode_does_not_load_a_model(monkeypatch):
    transcriber = FasterWhisperTranscriber(model_dir="/missing/oracle")

    def cannot_load():
        raise AssertionError("Empty audio must not require model weights")

    monkeypatch.setattr(transcriber, "_model_verify_for", cannot_load)
    decode = getattr(transcriber, "transcribe_independent_with_timings", None)
    assert callable(decode), "Independent batch verification needs a timestamped decode"
    assert decode([], 16000) == ([], [], [], [])


def test_missing_independent_probability_is_not_treated_as_certain():
    transcriber = FasterWhisperTranscriber(model_dir="/unused/oracle")
    transcriber._model_verify = SimpleNamespace(transcribe=lambda *_args, **_options: (
        [SimpleNamespace(words=[
            SimpleNamespace(word="بسم", probability=None, start=0.1, end=0.3),
        ])], SimpleNamespace(),
    ))

    words, confidences, starts, ends = transcriber.transcribe_independent_with_timings(
        [0.1] * 16000, 16000
    )
    assert words == ["بسم"]
    assert confidences == [0.0]
    assert starts == [100]
    assert ends == [300]
