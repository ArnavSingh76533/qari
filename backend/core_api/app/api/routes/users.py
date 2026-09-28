"""User routes: onboarding, auth exchange, home aggregation."""

from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.deps import get_current_user, get_db
from app.core.exceptions import NotFoundError, ProblemException, ConflictError
from app.core.logging import get_logger
from app.core.security import create_access_token, verify_firebase_token
from app.core.config import settings
from app.models.content import Lesson
from app.models.corpus import Surah
from app.models.user import (
    Flashcard, RecitationSession, User, UserBadge, UserLessonProgress,
    UserStats, UserAyahProgress,
)
from app.models.content import Badge
from app.schemas.user import (
    AuthExchangeRequest, AuthExchangeResponse, HomeResponse,
    NextLesson, DueFlashcardBrief, ContinueReading, RecentBadge,
    OnboardingRequest, OnboardingResponse, UserOut,
    SignupRequest, LoginRequest,
)
from app.services.redis_service import cache_get, cache_set, cache_delete
from app.services.streak_service import update_streak
from shared import AppLanguage, RedisKeys

logger = get_logger(__name__)
router = APIRouter(prefix="/v1", tags=["users"])


# ---------------------------------------------------------------------------
# Onboarding
# ---------------------------------------------------------------------------

@router.post("/users/onboarding", response_model=OnboardingResponse)
async def complete_onboarding(
    body: OnboardingRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Complete onboarding — the ONLY onboarding write endpoint."""
    if user.is_onboarded:
        raise ConflictError("User has already completed onboarding")

    user.app_language = body.app_language.value
    user.starting_path = body.starting_path.value
    user.is_onboarded = True
    if body.display_name:
        user.display_name = body.display_name
    if body.timezone:
        user.timezone = body.timezone

    # Create user_stats row if missing. `user.stats` is a lazy relationship:
    # touching it here triggers a synchronous lazy-load inside async context
    # (sqlalchemy MissingGreenlet → 500 on POST /v1/users/onboarding). Query
    # the row explicitly instead — user_id is unique per user.
    stats_row = (
        await db.execute(select(UserStats).where(UserStats.user_id == user.id))
    ).scalar_one_or_none()
    if stats_row is None:
        db.add(UserStats(user_id=user.id))

    await db.commit()
    await db.refresh(user)

    # Invalidate home cache
    await cache_delete(RedisKeys.HOME_CACHE.format(user_id=str(user.id)))

    return OnboardingResponse(
        user_id=user.id,
        is_onboarded=True,
        app_language=body.app_language,
        starting_path=body.starting_path,
    )


# ---------------------------------------------------------------------------
# Email / password auth
# ---------------------------------------------------------------------------

def _issue_token(user: User) -> AuthExchangeResponse:
    """Build a JWT auth response for an existing user."""
    token = create_access_token(
        user_id=str(user.id),
        firebase_uid=user.firebase_uid or "",
        email=user.email,
    )
    return AuthExchangeResponse(
        access_token=token,
        expires_in=settings.jwt_access_token_expire_minutes * 60,
        user_id=user.id,
        is_onboarded=user.is_onboarded,
    )


@router.post("/auth/signup", response_model=AuthExchangeResponse)
async def signup(
    body: SignupRequest,
    db: AsyncSession = Depends(get_db),
):
    """Create a new account with email + password.

    The new user starts completely fresh: zero XP, zero progress, and is
    *not* onboarded yet.
    """
    existing = await db.execute(select(User).where(User.email == body.email))
    if existing.scalar_one_or_none() is not None:
        raise ConflictError("An account with this email already exists")

    user = User(
        email=body.email,
        display_name=body.display_name,
        is_onboarded=False,
    )
    user.set_password(body.password)
    db.add(user)
    await db.flush()

    # Create the companion stats row so downstream aggregation works.
    db.add(UserStats(user_id=user.id))

    await db.commit()
    await db.refresh(user)
    logger.info("auth.signup", user_id=str(user.id))
    return _issue_token(user)


@router.post("/auth/login", response_model=AuthExchangeResponse)
async def login(
    body: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    """Authenticate with email + password and return a JWT."""
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()

    # Constant-ish response: don't reveal whether the email exists.
    if user is None or not user.verify_password(body.password):
        raise ProblemException(
            status=401,
            title="Unauthorized",
            detail="Invalid email or password",
        )

    await db.commit()
    logger.info("auth.login", user_id=str(user.id))
    return _issue_token(user)


# ---------------------------------------------------------------------------
# Auth exchange (Firebase)
# ---------------------------------------------------------------------------

@router.post("/users/auth/exchange", response_model=AuthExchangeResponse)
async def exchange_firebase_token(
    body: AuthExchangeRequest,
    db: AsyncSession = Depends(get_db),
):
    """Exchange a Firebase ID token for a backend JWT.

    If the user does not exist yet, a new row is created (but not onboarded).
    """
    decoded = verify_firebase_token(body.firebase_token)
    if decoded is None:
        raise ProblemException(
            status=401,
            title="Unauthorized",
            detail="Invalid or expired Firebase token",
        )

    firebase_uid = decoded["uid"]
    email = decoded.get("email")

    # Find or create user
    result = await db.execute(
        select(User).where(User.firebase_uid == firebase_uid)
    )
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            firebase_uid=firebase_uid,
            email=email,
            display_name=decoded.get("name"),
            is_onboarded=False,
        )
        db.add(user)
        await db.flush()

        # Create stats row
        stats = UserStats(user_id=user.id)
        db.add(stats)
        await db.commit()
        await db.refresh(user)
    else:
        # Update email if changed
        if email and user.email != email:
            user.email = email
            await db.commit()
            await db.refresh(user)

    token = create_access_token(
        user_id=str(user.id),
        firebase_uid=firebase_uid,
        email=email,
    )

    return AuthExchangeResponse(
        access_token=token,
        expires_in=60 * 24 * 7 * 60,  # 7 days in seconds
        user_id=user.id,
        is_onboarded=user.is_onboarded,
    )


# ---------------------------------------------------------------------------
# Home aggregation
# ---------------------------------------------------------------------------

@router.get("/me/home", response_model=HomeResponse)
async def get_home(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Aggregated home screen: streak, xp, next lesson, due flashcards, continue reading."""
    cache_key = RedisKeys.HOME_CACHE.format(user_id=str(user.id))
    cached = await cache_get(cache_key)
    if cached is not None:
        return HomeResponse(**cached)

    # --- Due flashcards count ---
    now = datetime.now(timezone.utc)
    due_count_result = await db.execute(
        select(func.count(Flashcard.id)).where(
            and_(
                Flashcard.user_id == user.id,
                Flashcard.is_suspended == False,
                Flashcard.due_at <= now,
            )
        )
    )
    due_count = due_count_result.scalar() or 0

    # --- Due flashcards (first 5 for preview) ---
    due_cards_result = await db.execute(
        select(Flashcard)
        .options(selectinload(Flashcard.word))
        .where(
            and_(
                Flashcard.user_id == user.id,
                Flashcard.is_suspended == False,
                Flashcard.due_at <= now,
            )
        )
        .order_by(Flashcard.due_at.asc())
        .limit(5)
    )
    due_cards = []
    for card in due_cards_result.scalars().all():
        word = card.word
        due_cards.append(DueFlashcardBrief(
            id=card.id,
            text_arabic=word.text_arabic if word else "",
            translation=getattr(word, f"translation_{user.app_language}", None) if word else None,
            surah_number=card.surah_number,
            ayah_number=card.ayah_number,
        ))

    # --- Next lesson ---
    next_lesson = None
    # Find the first lesson in the user's starting path module that is not completed
    completed_lesson_ids_result = await db.execute(
        select(UserLessonProgress.lesson_id).where(
            and_(
                UserLessonProgress.user_id == user.id,
                UserLessonProgress.status == "completed",
            )
        )
    )
    completed_ids = {row[0] for row in completed_lesson_ids_result}

    # Determine module from starting_path
    module_map = {
        "beginner": "basics",
        "intermediate": "intermediate",
        "advanced": "advanced",
        "tajweed_focus": "tajweed",
        "memorization": "hifz",
    }
    target_module = module_map.get(user.starting_path or "beginner", "basics")

    lessons_result = await db.execute(
        select(Lesson)
        .where(
            and_(
                Lesson.review_status == "published",
                Lesson.module == target_module,
            )
        )
        .order_by(Lesson.lesson_order)
    )
    for lesson in lessons_result.scalars().all():
        if lesson.id not in completed_ids:
            next_lesson = NextLesson(
                id=lesson.id,
                title=getattr(lesson, f"title_{user.app_language}", None) or lesson.title_en,
                module=lesson.module,
                estimated_minutes=lesson.estimated_minutes,
            )
            break

    # --- Continue reading ---
    continue_reading = None
    last_ayah_result = await db.execute(
        select(UserAyahProgress)
        .where(UserAyahProgress.user_id == user.id)
        .order_by(UserAyahProgress.last_studied_at.desc())
        .limit(1)
    )
    last_ayah = last_ayah_result.scalar_one_or_none()
    if last_ayah:
        surah_result = await db.execute(
            select(Surah).where(Surah.surah_number == last_ayah.surah_number)
        )
        surah = surah_result.scalar_one_or_none()
        continue_reading = ContinueReading(
            surah_number=last_ayah.surah_number,
            surah_name=surah.name_transliteration if surah else f"Surah {last_ayah.surah_number}",
            next_ayah=last_ayah.ayah_number + 1,
        )

    # --- Recent badges ---
    recent_badges_result = await db.execute(
        select(UserBadge)
        .options(selectinload(UserBadge.badge))
        .where(UserBadge.user_id == user.id)
        .order_by(UserBadge.awarded_at.desc())
        .limit(5)
    )
    recent_badges = [
        RecentBadge(
            id=ub.badge.id,
            name=getattr(ub.badge, f"name_{user.app_language}", None) or ub.badge.name_en,
            icon_url=ub.badge.icon_url,
            tier=ub.badge.tier,
            awarded_at=ub.awarded_at,
        )
        for ub in recent_badges_result.scalars().all()
    ]

    response = HomeResponse(
        streak=user.current_streak,
        longest_streak=user.longest_streak,
        freeze_credits=user.freeze_credits,
        total_xp=user.total_xp,
        next_lesson=next_lesson,
        due_flashcards_count=due_count,
        due_flashcards=due_cards,
        continue_reading=continue_reading,
        recent_badges=recent_badges,
    )
    await cache_set(cache_key, response.model_dump(), ttl=RedisKeys.TTL_HOME)
    return response


# ---------------------------------------------------------------------------
# User profile
# ---------------------------------------------------------------------------

@router.get("/me", response_model=UserOut)
async def get_me(user: User = Depends(get_current_user)):
    """Get the current user's profile."""
    return user
