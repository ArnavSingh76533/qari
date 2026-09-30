"""Verify the backend JWT contract without importing the core API app."""

import uuid
from typing import Optional

from fastapi import Header, HTTPException, status
from jose import JWTError, jwt

from app.core.config import settings


def verify_access_token(token: object) -> Optional[str]:
    """Return the verified user UUID, or None for any invalid token."""
    if not isinstance(token, str) or not token:
        return None
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            issuer=settings.jwt_issuer,
            options={"require_exp": True, "require_iss": True, "require_sub": True},
        )
        return str(uuid.UUID(payload["sub"]))
    except (JWTError, ValueError, TypeError, KeyError, AttributeError):
        return None


def user_id_from_authorization(authorization: Optional[str]) -> Optional[str]:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer":
        return None
    return verify_access_token(token.strip())


async def get_current_user_id(authorization: Optional[str] = Header(None)) -> str:
    user_id = user_id_from_authorization(authorization)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "type": "about:blank",
                "title": "Unauthorized",
                "status": 401,
                "detail": "A valid backend access token is required",
            },
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_id
