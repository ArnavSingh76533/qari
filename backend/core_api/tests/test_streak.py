"""Streak service tests: idempotency, freeze grace, reset logic."""

from datetime import date, timedelta
from unittest.mock import AsyncMock, patch

import pytest
import pytest_asyncio
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.services.streak_service import update_streak, _maybe_grant_freeze


@pytest.fixture
def make_user():
    """Factory for creating in-memory User objects for streak tests."""
    import uuid
    
    def _make(
        current_streak: int = 0,
        longest_streak: int = 0,
        last_streak_date=None,
        freeze_credits: int = 1,
        last_freeze_grant_date=None,
        timezone: str = "UTC",
    ) -> User:
        u = User(
            id=uuid.uuid4(),
            firebase_uid="test-uid",
            current_streak=current_streak,
            longest_streak=longest_streak,
            last_streak_date=last_streak_date,
            freeze_credits=freeze_credits,
            last_freeze_grant_date=last_freeze_grant_date,
            timezone=timezone,
        )
        return u
    return _make


@pytest.fixture
def mock_db():
    """A mock AsyncSession that tracks flush calls."""
    db = AsyncMock(spec=AsyncSession)
    return db


@pytest.fixture(autouse=True)
def mock_redis_lock():
    """Mock the Redis streak lock to always acquire (first call)."""
    with patch("app.services.redis_service.acquire_streak_lock", new_callable=AsyncMock) as mock:
        mock.return_value = True
        yield mock


class TestStreakIdempotency:
    """Test that streak updates are idempotent per user-timezone-day."""

    @pytest.mark.asyncio
    async def test_first_ever_activity(self, make_user, mock_db):
        """First ever activity: streak = 1, last_streak_date = today."""
        user = make_user(current_streak=0, last_streak_date=None)
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1
        assert updated is True
        assert user.current_streak == 1
        assert user.last_streak_date == today
        assert user.longest_streak == 1

    @pytest.mark.asyncio
    async def test_consecutive_day(self, make_user, mock_db):
        """Activity on the day after last: streak += 1."""
        yesterday = date(2025, 6, 14)
        today = date(2025, 6, 15)
        user = make_user(current_streak=5, longest_streak=5, last_streak_date=yesterday)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 6
        assert updated is True
        assert user.current_streak == 6
        assert user.longest_streak == 6

    @pytest.mark.asyncio
    async def test_already_processed_today(self, make_user, mock_db, mock_redis_lock):
        """If Redis lock is not acquired (already processed), return unchanged."""
        mock_redis_lock.return_value = False
        user = make_user(current_streak=5, last_streak_date=date(2025, 6, 15))
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 5
        assert updated is False

    @pytest.mark.asyncio
    async def test_same_day_no_change(self, make_user, mock_db):
        """If last_streak_date == today, no update (even if lock acquired)."""
        today = date(2025, 6, 15)
        user = make_user(current_streak=5, last_streak_date=today)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 5
        assert updated is False


class TestStreakReset:
    """Test streak reset on gap > 1 day without freeze."""

    @pytest.mark.asyncio
    async def test_gap_3_days_resets(self, make_user, mock_db):
        """Gap of 3 days: streak resets to 1."""
        user = make_user(current_streak=10, longest_streak=10, last_streak_date=date(2025, 6, 12))
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1
        assert updated is True
        assert user.current_streak == 1
        # longest_streak should remain 10
        assert user.longest_streak == 10

    @pytest.mark.asyncio
    async def test_gap_7_days_resets(self, make_user, mock_db):
        """Gap of 7 days: streak resets to 1."""
        user = make_user(current_streak=30, longest_streak=30, last_streak_date=date(2025, 6, 8))
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1
        assert user.longest_streak == 30  # longest unchanged


class TestStreakFreeze:
    """Test freeze usage after this month's credit has already been granted."""

    @pytest.mark.asyncio
    async def test_freeze_used_on_1_day_gap(self, make_user, mock_db):
        """Gap of 2 days (1 missed day) with freeze credits: streak preserved."""
        user = make_user(
            current_streak=5,
            longest_streak=5,
            last_streak_date=date(2025, 6, 13),
            freeze_credits=1,
            last_freeze_grant_date=date(2025, 6, 1),
        )
        today = date(2025, 6, 15)  # 2-day gap

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 6  # streak continued
        assert updated is True
        assert user.freeze_credits == 0  # credit consumed

    @pytest.mark.asyncio
    async def test_no_freeze_no_credits(self, make_user, mock_db):
        """Gap of 2 days with 0 freeze credits: streak resets."""
        user = make_user(
            current_streak=5,
            longest_streak=5,
            last_streak_date=date(2025, 6, 13),
            freeze_credits=0,
            last_freeze_grant_date=date(2025, 6, 1),
        )
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1  # reset
        assert user.freeze_credits == 0  # no change

    @pytest.mark.asyncio
    async def test_freeze_not_used_on_3_day_gap(self, make_user, mock_db):
        """Gap of 3+ days: freeze cannot save the streak."""
        user = make_user(
            current_streak=5,
            longest_streak=5,
            last_streak_date=date(2025, 6, 12),
            freeze_credits=2,
            last_freeze_grant_date=date(2025, 6, 1),
        )
        today = date(2025, 6, 15)  # 3-day gap

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1  # reset
        assert user.freeze_credits == 2  # not consumed


class TestFreezeGrant:
    """Test freeze credit grant: 1 per 30 days."""

    def test_first_grant(self, make_user):
        """First ever freeze grant on first activity."""
        user = make_user(freeze_credits=0, last_freeze_grant_date=None)
        today = date(2025, 6, 15)

        _maybe_grant_freeze(user, today)

        assert user.freeze_credits == 1
        assert user.last_freeze_grant_date == today

    def test_grant_after_30_days(self, make_user):
        """Grant a new freeze credit after 30+ days."""
        user = make_user(
            freeze_credits=0,
            last_freeze_grant_date=date(2025, 5, 15),
        )
        today = date(2025, 6, 15)  # 31 days later

        _maybe_grant_freeze(user, today)

        assert user.freeze_credits == 1
        assert user.last_freeze_grant_date == today

    def test_no_grant_within_30_days(self, make_user):
        """No grant if less than 30 days since last grant."""
        user = make_user(
            freeze_credits=0,
            last_freeze_grant_date=date(2025, 6, 1),
        )
        today = date(2025, 6, 15)  # 14 days later

        _maybe_grant_freeze(user, today)

        assert user.freeze_credits == 0  # no grant
        assert user.last_freeze_grant_date == date(2025, 6, 1)  # unchanged

    def test_grant_exactly_30_days(self, make_user):
        """Grant on exactly 30 days."""
        user = make_user(
            freeze_credits=0,
            last_freeze_grant_date=date(2025, 5, 16),
        )
        today = date(2025, 6, 15)  # exactly 30 days

        _maybe_grant_freeze(user, today)

        assert user.freeze_credits == 1


class TestLongestStreak:
    """Test that longest_streak is updated correctly."""

    @pytest.mark.asyncio
    async def test_longest_updates_on_new_record(self, make_user, mock_db):
        """Longest streak should update when current exceeds it."""
        user = make_user(current_streak=10, longest_streak=10, last_streak_date=date(2025, 6, 14))
        today = date(2025, 6, 15)

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 11
        assert user.longest_streak == 11

    @pytest.mark.asyncio
    async def test_longest_unchanged_on_reset(self, make_user, mock_db):
        """Longest streak should not change on reset."""
        user = make_user(current_streak=10, longest_streak=15, last_streak_date=date(2025, 6, 10))
        today = date(2025, 6, 15)  # 5-day gap

        streak, updated = await update_streak(mock_db, user, today)

        assert streak == 1
        assert user.longest_streak == 15  # unchanged
