"""The retired standalone analyzer must never publish a fabricated pass."""

import importlib.util
from pathlib import Path
import subprocess
import sys

from fastapi.testclient import TestClient


def test_legacy_analyzer_returns_unavailable_instead_of_a_pass(tmp_path, monkeypatch):
    path = Path(__file__).resolve().parents[1] / "app.py"
    spec = importlib.util.spec_from_file_location("legacy_analysis_api", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    def fabricated_success(*_args, **_kwargs):
        return subprocess.CompletedProcess([], 0, '{"passed": true, "similarity": 1.0}', "")

    monkeypatch.setattr(subprocess, "run", fabricated_success)
    response = TestClient(module.app).post(
        "/analyze", data={"surah_id": 1, "ayah_number": 2},
        files={"audio_file": ("clip.wav", b"untrusted audio", "audio/wav")},
    )

    assert response.status_code == 503
    assert "passed" not in response.json()


def test_legacy_adapter_exits_unavailable_without_loading_ml(tmp_path):
    path = Path(__file__).resolve().parents[1] / "adapter_infer_sub.py"
    # Controlled modules let the old script execute far enough to expose its
    # fabricated pass, without downloading heavy models or GPU dependencies.
    (tmp_path / "torch.py").write_text("class cuda:\n    is_available = staticmethod(lambda: False)\n")
    (tmp_path / "librosa.py").write_text("")
    (tmp_path / "transformers.py").write_text("AutoProcessor = AutoModelForCTC = object\n")
    (tmp_path / "peft.py").write_text("PeftModel = object\n")
    # The import torch.nn.functional in the old script needs a package.
    (tmp_path / "torch").mkdir()
    (tmp_path / "torch" / "__init__.py").write_text("class cuda:\n    is_available = staticmethod(lambda: False)\n")
    (tmp_path / "torch" / "nn").mkdir()
    (tmp_path / "torch" / "nn" / "__init__.py").write_text("")
    (tmp_path / "torch" / "nn" / "functional.py").write_text("")
    import os
    process = subprocess.run(
        [sys.executable, str(path), "missing.wav", "1", "2"],
        env={**os.environ, "PYTHONPATH": str(tmp_path)}, capture_output=True, text=True,
    )

    assert process.returncode != 0
    assert '"passed": true' not in process.stdout
    assert "unavailable" in process.stderr.lower()
