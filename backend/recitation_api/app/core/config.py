"""Core configuration for the Qari recitation_api service."""

from functools import lru_cache
from typing import Optional

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings for the recitation API service."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="QARI_",
        case_sensitive=False,
        extra="ignore",
    )

    # --- App ---
    app_name: str = "qari-recitation-api"
    app_version: str = "1.0.0"
    debug: bool = False
    environment: str = "production"

    # Same signing key/algorithm as core_api. The issuer remains the core
    # service's app_name so existing backend access tokens keep working.
    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    jwt_issuer: str = "qari-core-api"
    websocket_start_timeout_sec: int = 10

    # --- Redis ---
    redis_url: str = "redis://localhost:6379/0"
    redis_max_connections: int = 20

    # --- Audio upload ---
    max_upload_size_mb: int = 25
    allowed_audio_formats: list[str] = ["wav"]
    audio_sample_rate: int = 16000
    audio_channels: int = 1

    # --- Redis Streams ---
    recitation_stream: str = "qari:recitation:jobs"
    recitation_results_channel: str = "qari:recitation:results:{session_id}"
    recitation_consumer_group: str = "qari-inference-workers"
    recitation_consumer_name: str = "worker-1"
    stream_max_len: int = 10000
    poll_timeout_ms: int = 5000

    # --- CORS ---
    cors_origins: list[str] = []

    # --- Storage (audio files) ---
    audio_storage_path: str = "/tmp/qari_audio"
    # Publicly reachable base URL of THIS recitation_api service. Used to build
    # absolute URLs for uploaded user audio so the mobile can stream them
    # back (the worker only knows the server-local filesystem path).
    # Example: https://api.qari.app/recitation-api
    recitation_api_public_url: str = ""

    # --- Reference (Qari) audio ---
    # When a reference ayah has no audio URL of its own, the worker synthesises
    # one from this CDN so the mobile can play the "Reference (Qari)" track.
    # everyayah.com is the same CDN the Flutter app already uses for reciter
    # playback, so it is reliably reachable and trusted by the audio player.
    reference_audio_base_url: str = "https://everyayah.com/data"
    reference_audio_reciter: str = "Alafasy_128kbps"

    # --- Recitation ML engine ---
    # When True, the worker uses the deterministic stub instead of loading the
    # real ML pipeline. Useful for local dev without GPU / model weights.
    ml_use_stub: bool = False
    # Directory of per-ayah reference JSON files ({surah}_{ayah}.json) consumed
    # by ml.tajweed.reference_store.ReferenceStore. See scripts/build_reference_bundle.py.
    reference_data_dir: str = ""
    # Base URL of core_api, used to lazily fetch reference words/tajweed when a
    # prebuilt reference file is not present.
    core_api_base_url: str = "http://localhost:8000"

    # --- Worker ---
    worker_enabled: bool = False
    worker_poll_interval_sec: int = 5

    @field_validator("jwt_secret_key")
    @classmethod
    def validate_jwt_secret(cls, value: str) -> str:
        if len(value.strip().encode("utf-8")) < 32:
            raise ValueError("QARI_JWT_SECRET_KEY must contain at least 32 bytes; supply a securely generated secret")
        return value

    @field_validator("jwt_algorithm")
    @classmethod
    def validate_jwt_algorithm(cls, value: str) -> str:
        if value not in {"HS256", "HS384", "HS512"}:
            raise ValueError("QARI_JWT_ALGORITHM must be a supported shared-secret HMAC algorithm")
        return value

    @model_validator(mode="after")
    def validate_production_settings(self):
        if self.is_production:
            if self.debug:
                raise ValueError("QARI_DEBUG cannot be enabled in production")
            if "*" in self.cors_origins:
                raise ValueError("Production CORS requires explicit origins")
        return self

    @property
    def is_production(self) -> bool:
        return self.environment.lower() not in {"dev", "development", "test"}


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
