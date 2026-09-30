"""Recitation audio and results must stay private to the verified JWT owner."""

import json
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from jose import jwt
from starlette.websockets import WebSocketDisconnect

from app.main import app
from app.core.config import settings
from tests.support import OWNER_ID, OTHER_ID, TEST_SECRET, access_token, auth_headers
from tests.test_api import _make_wav

SESSION_ID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
RESULT = {
    "session_id": SESSION_ID,
    "surah_number": 1,
    "ayah_number": 1,
    "overall_score": 0.8,
    "pronunciation_score": 0.0,
    "tajweed_score": 0.0,
    "fluency_score": 0.0,
    "accuracy_score": 0.8,
    "word_verdicts": [],
    "reference_audio_url": "https://example.test/reference.mp3",
    "user_audio_url": f"https://example.test/v1/recitations/{SESSION_ID}/audio",
    "feedback": "Private recitation feedback",
    "feedback_urdu": None,
    "duration_seconds": 1,
    "created_at": "2026-09-30T12:00:00+00:00",
    "confidence": 0.8,
    "tajweed_available": False,
    "pronunciation_available": False,
    "fluency_available": False,
}


def _session(store, user_id=OWNER_ID, status="completed"):
    meta = {"session_id": SESSION_ID, "status": status}
    if user_id is not None:
        meta["user_id"] = user_id
    store.hashes[f"qari:recitation:session:{SESSION_ID}"] = meta
    store.values[f"qari:recitation:result:{SESSION_ID}"] = json.dumps(RESULT)
    path = Path(settings.audio_storage_path) / SESSION_ID
    path.mkdir()
    (path / "audio.wav").write_bytes(_make_wav())


@pytest.mark.parametrize("path", ["upload", "identify"])
def test_audio_processing_requires_authentication(path, recitation_storage):
    with TestClient(app) as client:
        response = client.post(
            f"/v1/recitations/{path}",
            data={"surah_number": "1", "ayah_number": "1"},
            files={"audio": ("test.wav", _make_wav(), "audio/wav")},
        )
    assert response.status_code == 401
    assert response.headers["WWW-Authenticate"] == "Bearer"
    assert not recitation_storage.hashes


@pytest.mark.parametrize("claims", [
    {"exp": int(time.time()) - 3600},
    {"iss": "another-service"},
    {"sub": "not-a-user-uuid"},
    {"exp": None},
])
def test_upload_rejects_invalid_backend_claims(claims, recitation_storage):
    token = access_token(**claims)
    response = TestClient(app).post(
        "/v1/recitations/upload",
        headers={"Authorization": f"Bearer {token}"},
        data={"surah_number": "1", "ayah_number": "1"},
        files={"audio": ("test.wav", _make_wav(), "audio/wav")},
    )
    assert response.status_code == 401
    assert not recitation_storage.hashes


def test_upload_rejects_signature_with_another_key(recitation_storage):
    token = jwt.encode(
        {"sub": OWNER_ID, "exp": int(time.time()) + 3600, "iss": "qari-core-api"},
        "different-strong-enough-test-signing-secret", algorithm="HS256",
    )
    response = TestClient(app).post(
        "/v1/recitations/upload",
        headers={"Authorization": f"Bearer {token}"},
        data={"surah_number": "1", "ayah_number": "1"},
        files={"audio": ("test.wav", _make_wav(), "audio/wav")},
    )
    assert response.status_code == 401


def test_upload_binds_owner_from_verified_token(recitation_storage):
    response = TestClient(app).post(
        "/v1/recitations/upload", headers=auth_headers(),
        data={"surah_number": "1", "ayah_number": "1", "user_id": OTHER_ID},
        files={"audio": ("test.wav", _make_wav(), "audio/wav")},
    )
    assert response.status_code == 202
    session_id = response.json()["session_id"]
    assert recitation_storage.hashes[f"qari:recitation:session:{session_id}"]["user_id"] == OWNER_ID


@pytest.mark.parametrize("suffix", ["", "/audio"])
def test_results_require_authentication(suffix, recitation_storage):
    _session(recitation_storage)
    response = TestClient(app).get(f"/v1/recitations/{SESSION_ID}{suffix}")
    assert response.status_code == 401


@pytest.mark.parametrize("suffix", ["", "/audio"])
@pytest.mark.parametrize("user_id", [OTHER_ID, None])
def test_foreign_and_legacy_sessions_are_not_visible(suffix, user_id, recitation_storage):
    _session(recitation_storage, user_id=user_id)
    response = TestClient(app).get(
        f"/v1/recitations/{SESSION_ID}{suffix}", headers=auth_headers(),
    )
    assert response.status_code == 404


def test_owner_can_read_audio(recitation_storage):
    _session(recitation_storage)
    response = TestClient(app).get(
        f"/v1/recitations/{SESSION_ID}/audio", headers=auth_headers(),
    )
    assert response.status_code == 200
    assert response.content == _make_wav()


def test_owner_can_poll_completed_result(recitation_storage):
    _session(recitation_storage)
    response = TestClient(app).get(
        f"/v1/recitations/{SESSION_ID}", headers=auth_headers(),
    )
    assert response.status_code == 200
    assert response.json()["result"]["feedback"] == "Private recitation feedback"
    assert response.json()["result"]["session_id"] == SESSION_ID


@pytest.mark.parametrize("user_id", [OTHER_ID, None])
def test_results_websocket_hides_foreign_and_legacy_sessions(user_id, recitation_storage):
    _session(recitation_storage, user_id=user_id)
    with pytest.raises(WebSocketDisconnect) as exc:
        with TestClient(app).websocket_connect(
            f"/ws/recitation/{SESSION_ID}", headers=auth_headers(),
        ) as ws:
            ws.receive_json()
    assert exc.value.code == 4404


def test_results_websocket_requires_authentication(recitation_storage):
    _session(recitation_storage)
    with pytest.raises(WebSocketDisconnect) as exc:
        with TestClient(app).websocket_connect(f"/ws/recitation/{SESSION_ID}") as ws:
            ws.receive_json()
    assert exc.value.code == 4401


def test_results_websocket_returns_private_result_to_owner(recitation_storage):
    _session(recitation_storage)
    with TestClient(app).websocket_connect(
        f"/ws/recitation/{SESSION_ID}", headers=auth_headers(),
    ) as ws:
        result = ws.receive_json()
    assert result["result"] == RESULT


def test_live_start_requires_verified_token(recitation_storage):
    with TestClient(app).websocket_connect("/ws/recitation/stream") as ws:
        ws.send_json({"type": "start", "surah_number": 1, "ayah_number": 1})
        with pytest.raises(WebSocketDisconnect) as exc:
            ws.receive_json()
    assert exc.value.code == 4401
    assert not recitation_storage.hashes


@pytest.mark.parametrize("auth_in_start", [False, True])
def test_live_start_stores_owner_before_ready(auth_in_start, recitation_storage, monkeypatch):
    import app.services.streaming_session as ss

    monkeypatch.setattr(ss.settings, "ml_use_stub", True)
    monkeypatch.setattr(ss, "resolve_reference_words_sequence", lambda refs: ([], [], "", [], []))
    headers = {} if auth_in_start else auth_headers()
    with TestClient(app).websocket_connect("/ws/recitation/stream", headers=headers) as ws:
        start = {"type": "start", "surah_number": 1, "ayah_number": 1, "words": ["بسم"], "user_id": OTHER_ID}
        if auth_in_start:
            start["access_token"] = access_token()
        ws.send_json(start)
        ready = ws.receive_json()
        assert ready["type"] == "ready"
        session_id = ready["session_id"]
        assert recitation_storage.hashes[f"qari:recitation:session:{session_id}"]["user_id"] == OWNER_ID
        ws.send_json({"type": "stop"})
        final = ws.receive_json()
        assert final["type"] == "final"
    assert recitation_storage.hashes[f"qari:recitation:session:{session_id}"]["user_id"] == OWNER_ID


def test_production_diagnostics_are_disabled(monkeypatch):
    monkeypatch.setattr(settings, "environment", "production")
    response = TestClient(app).post(
        "/v1/recitations/debug_echo", json={"text": "private diagnostics"}, headers=auth_headers(),
    )
    assert response.status_code == 404
