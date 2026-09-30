"""Protocol fixtures at the external Redis/token boundaries."""

import time

from jose import jwt

OWNER_ID = "12345678-1234-1234-1234-123456789012"
OTHER_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
TEST_SECRET = "test-only-signing-key-for-security-regressions-2026"


def access_token(user_id=OWNER_ID, **claims):
    payload = {
        "sub": user_id,
        "iat": int(time.time()),
        "exp": int(time.time()) + 3600,
        "iss": "qari-core-api",
    }
    payload.update(claims)
    return jwt.encode(payload, TEST_SECRET, algorithm="HS256")


def auth_headers(user_id=OWNER_ID):
    return {"Authorization": f"Bearer {access_token(user_id)}"}


class MemoryRedis:
    """Small Redis boundary substitute preserving hash-merge semantics."""

    def __init__(self):
        self.hashes = {}
        self.values = {}
        self.jobs = []

    async def hset(self, key, mapping):
        self.hashes.setdefault(key, {}).update(mapping)

    async def hgetall(self, key):
        return dict(self.hashes.get(key, {}))

    async def expire(self, key, seconds):
        return True

    async def xadd(self, stream, payload, **kwargs):
        self.jobs.append((stream, dict(payload)))
        return "1-0"

    async def get(self, key):
        return self.values.get(key)

    async def set(self, key, value, **kwargs):
        self.values[key] = value

    async def aclose(self):
        pass
