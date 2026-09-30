"""Pytest fixtures for async DB and test client."""

import asyncio
import os
from typing import AsyncIterator

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

# Set test env before importing app
os.environ.setdefault("QARI_ENVIRONMENT", "test")
os.environ.setdefault("QARI_JWT_SECRET_KEY", "test-only-signing-key-for-security-regressions-2026")
os.environ.setdefault("QARI_DEBUG", "true")
os.environ.setdefault("QARI_DATABASE_URL", "postgresql+asyncpg://qari:qari@localhost:5432/qari_test")
os.environ.setdefault("QARI_REDIS_URL", "redis://localhost:6379/1")
os.environ.setdefault("QARI_RATE_LIMIT_ENABLED", "false")

from app.db.session import Base
from app.models import corpus, content, user  # noqa: F401 – register all models
from app.main import app


@pytest.fixture(scope="session")
def event_loop():
    """Create a single event loop for the test session."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session")
async def test_engine():
    """Create a test database engine."""
    engine = create_async_engine(
        os.environ["QARI_DATABASE_URL"],
        echo=False,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture
async def db_session(test_engine) -> AsyncIterator[AsyncSession]:
    """Yield a fresh DB session for each test."""
    factory = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def client() -> AsyncIterator[AsyncClient]:
    """Yield an async HTTP test client."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
def mock_user_id():
    """A fixed UUID for testing."""
    import uuid
    return uuid.UUID("12345678-1234-1234-1234-123456789012")
