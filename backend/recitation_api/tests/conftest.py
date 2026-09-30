"""Isolated test configuration; no production credentials or Redis required."""

import os

os.environ.setdefault("QARI_JWT_SECRET_KEY", "test-only-signing-key-for-security-regressions-2026")
os.environ.setdefault("QARI_ENVIRONMENT", "test")

import pytest

from app.api.routes import recitation, websocket
from app.core.config import settings
from tests.support import MemoryRedis


@pytest.fixture(autouse=True)
def recitation_storage(monkeypatch, tmp_path):
    """Keep HTTP/WS storage operations in a fresh local test sandbox."""
    import redis.asyncio

    store = MemoryRedis()
    monkeypatch.setattr(recitation, "_get_redis", lambda: store)
    monkeypatch.setattr(websocket, "_get_redis", lambda: store)
    monkeypatch.setattr(redis.asyncio, "from_url", lambda *args, **kwargs: store)
    monkeypatch.setattr(settings, "audio_storage_path", str(tmp_path))
    return store
