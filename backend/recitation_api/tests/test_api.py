"""Tests for the Qari recitation_api service."""

import json
import struct
import io
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app
from tests.support import auth_headers


def _make_wav(sample_rate: int = 16000, channels: int = 1, bits_per_sample: int = 16, duration_sec: float = 1.0) -> bytes:
    """Generate a minimal valid WAV file in memory."""
    num_samples = int(sample_rate * duration_sec)
    data_size = num_samples * channels * (bits_per_sample // 8)
    header = struct.pack(
        "<4sI4s4sIHHIIHH4sI",
        b"RIFF",
        36 + data_size,
        b"WAVE",
        b"fmt ",
        16,
        1,  # PCM
        channels,
        sample_rate,
        sample_rate * channels * (bits_per_sample // 8),
        channels * (bits_per_sample // 8),
        bits_per_sample,
        b"data",
        data_size,
    )
    # Silent audio data (zeros)
    data = b"\x00" * data_size
    return header + data


@pytest_asyncio.fixture
async def client():
    """Yield an async HTTP test client."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test", headers=auth_headers()) as ac:
        yield ac


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient):
    """Health endpoint should return 200."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["service"] == "qari-recitation-api"


@pytest.mark.asyncio
async def test_upload_missing_audio(client: AsyncClient):
    """Upload without audio file should return 422."""
    resp = await client.post(
        "/v1/recitations/upload",
        data={"surah_number": "1", "ayah_from": "1", "ayah_to": "7"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_upload_invalid_surah(client: AsyncClient):
    """Surah number > 114 should return 422 validation error."""
    wav_bytes = _make_wav()
    resp = await client.post(
        "/v1/recitations/upload",
        data={"surah_number": "999", "ayah_from": "1", "ayah_to": "7"},
        files={"audio": ("test.wav", wav_bytes, "audio/wav")},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_upload_ayah_to_before_from(client: AsyncClient):
    """ayah_to < ayah_from should fail validation."""
    wav_bytes = _make_wav()
    resp = await client.post(
        "/v1/recitations/upload",
        data={"surah_number": "1", "ayah_from": "7", "ayah_to": "1"},
        files={"audio": ("test.wav", wav_bytes, "audio/wav")},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_upload_invalid_wav_format(client: AsyncClient):
    """Non-WAV file should return 415."""
    resp = await client.post(
        "/v1/recitations/upload",
        data={"surah_number": "1", "ayah_from": "1", "ayah_to": "7"},
        files={"audio": ("test.mp3", b"not a wav file", "audio/mpeg")},
    )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_upload_corrupted_wav(client: AsyncClient):
    """File with RIFF header but corrupted data should return 422."""
    bad_bytes = b"RIFF\x00\x00\x00\x00WAVE" + b"\x00" * 100
    resp = await client.post(
        "/v1/recitations/upload",
        data={"surah_number": "1", "ayah_from": "1", "ayah_to": "7"},
        files={"audio": ("test.wav", bad_bytes, "audio/wav")},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_get_nonexistent_session(client: AsyncClient):
    """Getting a non-existent session should return 404."""
    fake_id = "00000000-0000-0000-0000-000000000000"
    resp = await client.get(f"/v1/recitations/{fake_id}")
    assert resp.status_code == 404
    data = resp.json()
    assert data["detail"]["title"] == "Not Found"


@pytest.mark.asyncio
async def test_metrics_endpoint(client: AsyncClient):
    """Prometheus metrics should be available."""
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert "qari_recitation" in resp.text
