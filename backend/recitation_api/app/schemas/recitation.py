"""Recitation Pydantic schemas."""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class RecitationUploadRequest(BaseModel):
    """Metadata sent alongside the audio file (as form fields)."""
    surah_number: int = Field(..., ge=1, le=114)
    ayah_from: int = Field(..., ge=1)
    ayah_to: int = Field(..., ge=1)
    qari_id: Optional[int] = None


class RecitationUploadResponse(BaseModel):
    """202 Accepted response after upload."""
    session_id: uuid.UUID
    status: str = "queued"
    message: str = "Audio uploaded and queued for inference"
    estimated_wait_sec: int = 30


class PhonemeErrorOut(BaseModel):
    """Phoneme-level error (mirrors the mobile PhonemeError model)."""
    phoneme: str
    expected_phoneme: str
    actual_phoneme: str
    position: int
    severity: str = "minor"


class WordVerdictOut(BaseModel):
    """Per-word verdict — exact shape the Flutter RecitationResult.wordVerdicts
    expects (see mobile/lib/data/models/recitation_model.dart)."""
    word: str
    word_index: int
    is_correct: bool
    confidence: float = 1.0
    expected_text: Optional[str] = None
    actual_text: Optional[str] = None
    start_ms: Optional[int] = None
    end_ms: Optional[int] = None
    error_type: Optional[str] = None
    error_description: Optional[str] = None
    reference_audio_url: Optional[str] = None
    user_audio_url: Optional[str] = None
    phoneme_errors: list[PhonemeErrorOut] = []


class RecitationAnalysisResult(BaseModel):
    """Full analysis result matching the mobile RecitationResult model.

    Scores are normalised to 0..1 to match the mobile (which renders
    `overallScore * 100`).
    """
    session_id: str
    surah_number: int
    ayah_number: int
    overall_score: float
    pronunciation_score: float = 0.0
    tajweed_score: float = 0.0
    fluency_score: float = 0.0
    accuracy_score: float = 0.0
    # Missing flags mean the metric was not established as available. Legacy
    # numeric placeholders alone must never be interpreted as measurements.
    pronunciation_available: bool = False
    tajweed_available: bool = False
    fluency_available: bool = False
    word_verdicts: list[WordVerdictOut] = []
    reference_audio_url: Optional[str] = None
    user_audio_url: Optional[str] = None
    feedback: Optional[str] = None
    feedback_urdu: Optional[str] = None
    duration_seconds: int = 0
    created_at: str
    confidence: float = 1.0


class RecitationPollResponse(BaseModel):
    """Wrapper the mobile repository reads: {status, result}."""
    status: str
    result: Optional[RecitationAnalysisResult] = None
    error_message: Optional[str] = None


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "qari-recitation-api"
    version: str = "1.0.0"
