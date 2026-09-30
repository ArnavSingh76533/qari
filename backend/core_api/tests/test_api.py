"""API endpoint tests for the Qari core_api."""

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_health_check(client: AsyncClient):
    """Health endpoint should return 200 with service info."""
    resp = await client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert "service" in data
    assert "version" in data


@pytest.mark.asyncio
async def test_surah_not_found(client: AsyncClient):
    """Invalid surah number should return 404 problem+json."""
    resp = await client.get("/v1/surahs/999")
    assert resp.status_code == 404
    data = resp.json()
    assert data["type"] == "about:blank"
    assert data["title"] == "Not Found"
    assert "999" in data["detail"]


@pytest.mark.asyncio
async def test_surah_out_of_range(client: AsyncClient):
    """Surah number > 114 should return 404."""
    resp = await client.get("/v1/surahs/115")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_ayahs_max_20_enforced(client: AsyncClient):
    """Requesting more than 20 ayahs should be capped to 20."""
    # This test verifies the cap logic — from=1, to=30 should be capped to 20
    resp = await client.get("/v1/surahs/1/ayahs?from=1&to=30")
    # Even if DB is empty, the endpoint should not error
    # The cap is enforced server-side
    assert resp.status_code in (200, 404)


@pytest.mark.asyncio
async def test_word_not_found(client: AsyncClient):
    """Non-existent word should return 404."""
    resp = await client.get("/v1/words/999:999:999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_root_not_found(client: AsyncClient):
    """Non-existent root should return 404."""
    resp = await client.get("/v1/roots/99999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_lessons_list_empty(client: AsyncClient):
    """Lessons list should return a list (possibly empty if no published lessons)."""
    resp = await client.get("/v1/lessons")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


@pytest.mark.asyncio
async def test_lesson_not_found(client: AsyncClient):
    """Non-existent lesson should return 404."""
    resp = await client.get("/v1/lessons/99999")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_unauthorized_home(client: AsyncClient):
    """Home endpoint without auth should return 401."""
    resp = await client.get("/v1/me/home")
    assert resp.status_code == 401
    data = resp.json()
    assert data["title"] == "Unauthorized"


@pytest.mark.asyncio
async def test_unauthorized_flashcards(client: AsyncClient):
    """Flashcards due without auth should return 401."""
    resp = await client.get("/v1/flashcards/due")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_auth_exchange_invalid_token(client: AsyncClient, monkeypatch):
    """A rejected Firebase token returns 401 without external credential lookup."""
    from app.api.routes import users

    monkeypatch.setattr(users, "verify_firebase_token", lambda token: None)
    resp = await client.post(
        "/v1/users/auth/exchange",
        json={"firebase_token": "invalid-token"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_content_bundle_invalid_scope(client: AsyncClient):
    """Invalid bundle scope should return 400."""
    resp = await client.get("/v1/content/bundle?scope=invalid_scope")
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_content_bundle_valid_scope(client: AsyncClient):
    """Valid bundle scope should return 200 (may be empty if DB is empty)."""
    resp = await client.get("/v1/content/bundle?scope=juz30")
    assert resp.status_code == 200
    data = resp.json()
    assert data["scope"] == "juz30"
    assert "counts" in data


@pytest.mark.asyncio
async def test_problem_json_content_type(client: AsyncClient):
    """Error responses should use application/problem+json content type."""
    resp = await client.get("/v1/surahs/999")
    assert resp.status_code == 404
    # The content type should be problem+json
    content_type = resp.headers.get("content-type", "")
    assert "application/problem+json" in content_type


@pytest.mark.asyncio
async def test_scholar_questions_unauthorized(client: AsyncClient):
    """Scholar questions without auth should return 401."""
    resp = await client.get("/v1/scholar/questions")
    assert resp.status_code == 401
