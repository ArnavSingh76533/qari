"""Production settings fail closed before any service accepts traffic."""

import importlib.util
from pathlib import Path

import pytest
from pydantic import ValidationError

REPO = Path(__file__).resolve().parents[3]


@pytest.fixture(params=["core_api", "recitation_api"])
def settings_class(request):
    path = REPO / "backend" / request.param / "app" / "core" / "config.py"
    spec = importlib.util.spec_from_file_location(f"{request.param}_settings_under_test", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Settings


def test_production_requires_explicit_jwt_secret(settings_class, monkeypatch):
    monkeypatch.delenv("QARI_JWT_SECRET_KEY", raising=False)
    with pytest.raises(ValidationError):
        settings_class(_env_file=None, environment="production")


@pytest.mark.parametrize("key", ["change-me-in-production", "short", " " * 64])
def test_production_rejects_weak_signing_keys(settings_class, key):
    with pytest.raises(ValidationError):
        settings_class(_env_file=None, environment="production", jwt_secret_key=key)


def test_production_rejects_debug_mode(settings_class):
    with pytest.raises(ValidationError):
        settings_class(_env_file=None, environment="production", debug=True)


def test_production_rejects_wildcard_cors(settings_class):
    with pytest.raises(ValidationError):
        settings_class(_env_file=None, environment="production", cors_origins=["*"])


def test_production_preserves_configured_signing_key(settings_class):
    config = settings_class(_env_file=None, environment="production")
    assert config.jwt_secret_key == "test-only-signing-key-for-security-regressions-2026"
