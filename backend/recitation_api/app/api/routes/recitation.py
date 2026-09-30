"""Recitation upload route: multipart audio upload with validation."""

import json
import os
import uuid
import wave
from typing import Optional

from fastapi import APIRouter, Depends, Form, File, UploadFile, HTTPException, status, Request
from pydantic import ValidationError

from app.core.config import settings
from app.core.logging import get_logger
from app.core.security import get_current_user_id
from app.schemas.recitation import (
    RecitationUploadResponse,
    RecitationPollResponse,
    RecitationAnalysisResult,
)
import redis.asyncio as redis

logger = get_logger(__name__)
router = APIRouter(prefix="/v1/recitations", tags=["recitation"])

_redis: Optional[redis.Redis] = None


def _get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.redis_url, decode_responses=True)
    return _redis


@router.post("/debug_echo")
@router.post("/tarteel_debug_echo")  # legacy path — older APKs in the field
async def debug_echo(request: Request, user_id: str = Depends(get_current_user_id)) -> dict:
    """DEV-ONLY: logs whatever the app POSTs here (e.g. native crash stacks) so
    it can be inspected from the server logs without pulling logs off the
    phone. Harmless no-op; returns 200.
    """
    if settings.is_production:
        raise HTTPException(status_code=404, detail="Not Found")
    try:
        body = await request.body()
        ctype = request.headers.get("content-type", "")
        if "application/json" in ctype:
            try:
                parsed = json.loads(body)
                logger.info("debug_echo.json", size=len(body), payload=parsed)
            except Exception:
                logger.info("debug_echo.text", size=len(body), body=body.decode("utf-8", "replace"))
        else:
            # Binary frame — log a hex preview so we can see the structure.
            preview = body[:128].hex()
            logger.info("debug_echo.binary", size=len(body), hex_preview=preview)
    except Exception as e:  # never fail the caller
        logger.warning("debug_echo.error", error=str(e))
    return {"ok": True}


def _validate_wav_header(content: bytes) -> tuple[int, int, int]:
    """Validate WAV header and return (sample_rate, channels, bits_per_sample).

    Raises HTTPException if the file is not a valid mono 16kHz WAV.
    """
    if len(content) < 44:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Audio File",
                "status": 422,
                "detail": "File too small to be a valid WAV",
            },
        )

    # Check RIFF header
    if content[:4] != b"RIFF" or content[8:12] != b"WAVE":
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Audio File",
                "status": 422,
                "detail": "Not a valid WAV file (missing RIFF/WAVE header)",
            },
        )

    # Parse fmt chunk
    import struct
    try:
        # Find fmt chunk
        idx = 12
        fmt_found = False
        sample_rate = channels = bits_per_sample = 0
        while idx < len(content) - 8:
            chunk_id = content[idx:idx+4]
            chunk_size = struct.unpack_from("<I", content, idx+4)[0]
            if chunk_id == b"fmt ":
                fmt_found = True
                audio_format = struct.unpack_from("<H", content, idx+8)[0]
                channels = struct.unpack_from("<H", content, idx+10)[0]
                sample_rate = struct.unpack_from("<I", content, idx+12)[0]
                bits_per_sample = struct.unpack_from("<H", content, idx+22)[0]
                break
            idx += 8 + chunk_size + (chunk_size % 2)  # pad to even

        if not fmt_found:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={
                    "type": "about:blank",
                    "title": "Invalid Audio File",
                    "status": 422,
                    "detail": "WAV file missing fmt chunk",
                },
            )

        return sample_rate, channels, bits_per_sample

    except struct.error:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Audio File",
                "status": 422,
                "detail": "Corrupted WAV header",
            },
        )


@router.post("/upload", response_model=RecitationUploadResponse, status_code=status.HTTP_202_ACCEPTED)
async def upload_recitation(
    surah_number: int = Form(..., ge=1, le=114),
    ayah_number: Optional[int] = Form(None, ge=1, description="Single ayah (MVP mobile client)."),
    ayah_from: Optional[int] = Form(None, ge=1),
    ayah_to: Optional[int] = Form(None, ge=1),
    qari_id: Optional[int] = Form(None),
    audio: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    # Normalise the ayah range: the Flutter client sends a single `ayah_number`,
    # while the REST contract also supports an explicit `ayah_from`..`ayah_to`.
    if ayah_number is not None:
        if ayah_from is None:
            ayah_from = ayah_number
        if ayah_to is None:
            ayah_to = ayah_number
    if ayah_from is None or ayah_to is None:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Request",
                "status": 422,
                "detail": "Provide either 'ayah_number' or both 'ayah_from' and 'ayah_to'",
            },
        )
    if ayah_to < ayah_from:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Request",
                "status": 422,
                "detail": "'ayah_to' must be greater than or equal to 'ayah_from'",
            },
        )
    """Upload a recitation audio file for AI evaluation.

    Accepts mono 16kHz WAV files. Returns 202 with a session_id.
    The audio is enqueued onto a Redis Stream for GPU inference.
    """
    # --- Validate file size ---
    max_bytes = settings.max_upload_size_mb * 1024 * 1024
    content = await audio.read()
    if len(content) > max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={
                "type": "about:blank",
                "title": "Payload Too Large",
                "status": 413,
                "detail": f"Audio file exceeds {settings.max_upload_size_mb}MB limit",
            },
        )

    # --- Validate content type ---
    content_type = audio.content_type or ""
    if "wav" not in content_type.lower() and not audio.filename.lower().endswith(".wav"):
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail={
                "type": "about:blank",
                "title": "Unsupported Media Type",
                "status": 415,
                "detail": f"Only WAV files are accepted, got '{content_type or audio.filename}'",
            },
        )

    # --- Validate WAV format ---
    sample_rate, channels, bits_per_sample = _validate_wav_header(content)

    if sample_rate != settings.audio_sample_rate:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Audio Format",
                "status": 422,
                "detail": f"Sample rate must be {settings.audio_sample_rate}Hz, got {sample_rate}Hz",
            },
        )

    if channels != settings.audio_channels:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "type": "about:blank",
                "title": "Invalid Audio Format",
                "status": 422,
                "detail": f"Audio must be mono (1 channel), got {channels} channels",
            },
        )

    # --- Compute duration ---
    # Duration = (data_size) / (sample_rate * channels * bits_per_sample/8)
    # Approximate: total file size minus header
    data_size = len(content) - 44
    bytes_per_sample = bits_per_sample // 8
    duration_sec = data_size / (sample_rate * channels * bytes_per_sample) if bytes_per_sample > 0 else 0

    # --- Generate session ID ---
    session_id = str(uuid.uuid4())

    # --- Save audio file ---
    storage_path = os.path.join(settings.audio_storage_path, session_id)
    os.makedirs(storage_path, exist_ok=True)
    file_path = os.path.join(storage_path, "audio.wav")
    with open(file_path, "wb") as f:
        f.write(content)

    # --- Store session metadata in Redis ---
    r = _get_redis()
    session_meta = {
        "session_id": session_id,
        "user_id": user_id,
        "surah_number": str(surah_number),
        "ayah_from": str(ayah_from),
        "ayah_to": str(ayah_to),
        "qari_id": str(qari_id) if qari_id else "",
        "status": "queued",
        "audio_path": file_path,
        "audio_duration_sec": str(round(duration_sec, 2)),
        "queued_at": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    }
    await r.hset(f"qari:recitation:session:{session_id}", mapping=session_meta)
    await r.expire(f"qari:recitation:session:{session_id}", 86400)  # 24h TTL

    # --- Enqueue job onto Redis Stream ---
    job_payload = {
        "session_id": session_id,
        "surah_number": str(surah_number),
        "ayah_from": str(ayah_from),
        "ayah_to": str(ayah_to),
        "audio_path": file_path,
        "audio_duration_sec": str(round(duration_sec, 2)),
    }
    if qari_id:
        job_payload["qari_id"] = str(qari_id)

    entry_id = await r.xadd(
        settings.recitation_stream,
        job_payload,
        maxlen=settings.stream_max_len,
        approximate=True,
    )

    logger.info(
        "recitation.uploaded",
        session_id=session_id,
        surah=surah_number,
        ayah_range=f"{ayah_from}-{ayah_to}",
        duration_sec=round(duration_sec, 2),
        stream_entry_id=entry_id,
        size_bytes=len(content),
    )

    return RecitationUploadResponse(
        session_id=uuid.UUID(session_id),
        status="queued",
        message="Audio uploaded and queued for inference",
        estimated_wait_sec=30,
    )


@router.get("/{session_id}/audio")
async def get_recitation_audio(session_id: uuid.UUID, user_id: str = Depends(get_current_user_id)):
    """Stream back the user's uploaded audio for A/B comparison playback.

    The mobile app cannot open the server-local filesystem path stored in the
    job, so the worker publishes this absolute URL (built from
    ``recitation_api_public_url``) in ``user_audio_url``.
    """
    session_id = str(session_id)
    await _get_owned_session(session_id, user_id)
    file_path = os.path.join(settings.audio_storage_path, session_id, "audio.wav")
    if not os.path.isfile(file_path):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "type": "about:blank",
                "title": "Not Found",
                "status": 404,
                "detail": f"No audio found for session '{session_id}'",
            },
        )
    from fastapi.responses import FileResponse

    return FileResponse(
        file_path,
        media_type="audio/wav",
        filename=f"{session_id}.wav",
    )


@router.get("/{session_id}", response_model=RecitationPollResponse)
async def get_recitation_result(session_id: uuid.UUID, user_id: str = Depends(get_current_user_id)):
    """Poll for recitation results by session_id.

    Returns ``{"status": ..., "result": <RecitationAnalysisResult>}`` — the exact
    shape the Flutter ``RecitationRepository.getRecitationResult`` parses.
    """
    session_id = str(session_id)
    r = _get_redis()
    session_data = await _get_owned_session(session_id, user_id)

    status_val = session_data.get("status", "queued")

    # The completed analysis blob is stored as a single JSON document.
    result: Optional[RecitationAnalysisResult] = None
    if status_val == "completed":
        raw = await r.get(f"qari:recitation:result:{session_id}")
        if raw:
            try:
                result = RecitationAnalysisResult(**json.loads(raw))
            except (json.JSONDecodeError, ValidationError) as exc:
                logger.error("recitation.bad_result_blob", session_id=session_id, error=str(exc))

    return RecitationPollResponse(
        status=status_val,
        result=result,
        error_message=session_data.get("error_message"),
    )


async def _get_owned_session(session_id: str, user_id: str) -> dict:
    session_data = await _get_redis().hgetall(f"qari:recitation:session:{session_id}")
    if not session_data or session_data.get("user_id") != user_id:
        # The same response hides both another user's and pre-auth legacy jobs.
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "type": "about:blank",
                "title": "Not Found",
                "status": 404,
                "detail": f"Recitation session '{session_id}' not found",
            },
        )
    return session_data


@router.get("/ayahs/{surah_number}/{ayah_number}/words", tags=["recitation"])
async def get_ayah_words(surah_number: int, ayah_number: int):
    """Serve the Quranic text at the individual word level for Hifz / follow-along.

    Returns the blueprint word-level data model::

        {
          "surah_number": 1, "ayah_number": 1,
          "words": [
            {"word_id": 1, "text_with_tashkeel": "بِسْمِ", "clean_text": "بسم",
             "sequence_index": 1, "state": "hidden"}, ...
          ]
        }

    ``text_with_tashkeel`` is for UI rendering, ``clean_text`` (diacritics
    stripped) is the key used by the ASR / alignment engine. ``state`` starts
    as ``hidden`` except the first word (``active``). Falls back to an empty
    word list when no reference data is available for this ayah.
    """
    from app.services.streaming_session import resolve_reference_words

    display, norm, audio_url, entries = resolve_reference_words(
        surah_number, ayah_number
    )
    if not entries:
        return {
            "surah_number": surah_number,
            "ayah_number": ayah_number,
            "reference_audio_url": audio_url,
            "words": [],
        }

    words = []
    for i, entry in enumerate(entries):
        words.append({
            "word_id": i + 1,
            "sequence_index": i + 1,
            "text_with_tashkeel": entry.get("text_with_tashkeel", display[i]),
            "clean_text": entry.get("clean_text", norm[i]),
            "state": "active" if i == 0 else "hidden",
        })
    return {
        "surah_number": surah_number,
        "ayah_number": ayah_number,
        "reference_audio_url": audio_url,
        "words": words,
    }


# ─── Verse identification (Shazam-style) ──────────────────────────────────────
# Accepts a short recitation clip, transcribes it with the Quran-fine-tuned
# Whisper model (tarteel-ai/whisper-base-ar-quran), then finds the ayah(s) whose
# expected word sequence best matches the transcript as an ordered subsequence.

_IDENTIFY_MAX_SECONDS = 25


@router.post("/identify", tags=["recitation"])
async def identify_verse(
    audio: UploadFile = File(...),
    top_k: int = Form(5),
    user_id: str = Depends(get_current_user_id),
):
    """Identify which Quranic verse (surah:ayah) a recited clip corresponds to.

    The clip can be a few words or a full ayah. Returns the top ``top_k``
    matching verses with a 0..1 confidence score and the matched Arabic text.

    Requires the Whisper ASR model to be available; if it cannot be loaded the
    endpoint returns 503 so the client can show a clear "model unavailable"
    message rather than a silent failure.
    """
    content = await audio.read()
    if not content or len(content) < 44:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"type": "about:blank", "title": "Invalid Audio", "status": 422,
                     "detail": "Empty or too-small audio clip."},
        )

    # Decode PCM16 WAV → float32 numpy for the ASR (numpy-free header parse).
    try:
        import struct
        import numpy as np
        import array

        if content[:4] != b"RIFF" or content[8:12] != b"WAVE":
            raise ValueError("not a WAV")
        sample_rate = struct.unpack_from("<I", content, 24)[0]
        samples = array.array("h")
        # data chunk starts at 44 for a canonical WAV
        samples.frombytes(content[44:])
        audio_np = np.array(samples, dtype=np.float32) / 32768.0
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"type": "about:blank", "title": "Invalid Audio", "status": 422,
                     "detail": f"Could not decode WAV: {exc}"},
        )

    if len(audio_np) / max(sample_rate, 1) > _IDENTIFY_MAX_SECONDS:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail={"type": "about:blank", "title": "Clip Too Long", "status": 413,
                     "detail": f"Keep the clip under {_IDENTIFY_MAX_SECONDS}s."},
        )

    # --- Transcribe with the Quran ASR (lazy import; heavy torch stack) ---
    try:
        from ml.inference.asr import QuranASR, normalize_arabic, tokenize_words

        asr = QuranASR()
        asr.load()
        result = asr.transcribe(audio_np, sample_rate, return_timestamps=False)
        transcript_words = result.normalized_words
    except Exception as exc:  # torch/whisper missing → graceful degradation
        logger.error("identify.asr_failed", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"type": "about:blank", "title": "ASR Unavailable",
                     "status": 503,
                     "detail": "Verse identification needs the Quran ASR model, "
                               "which is not loaded on this server."},
        )

    if not transcript_words:
        return {
            "transcript": result.raw_text,
            "candidates": [],
            "message": "No speech detected in the clip.",
        }

    # --- Score every reference ayah as an ordered subsequence match ---
    try:
        from ml.tajweed.reference_store import ReferenceStore

        store = ReferenceStore(settings.reference_data_dir or None)
    except Exception as exc:
        logger.warning("identify.refstore_unavailable", error=str(exc))
        return {
            "transcript": result.raw_text,
            "candidates": [],
            "message": "Reference corpus is not available on this server.",
        }

    candidates = []
    for (surah, ayah) in store.list_ayahs():
        ref = store.get(surah, ayah)
        if ref is None:
            continue
        ref_words = [normalize_arabic(w.word) for w in ref.words]
        ref_words = [w for w in ref_words if w]
        score = _ordered_subsequence_score(transcript_words, ref_words)
        if score <= 0:
            continue
        candidates.append({
            "surah_number": surah,
            "ayah_number": ayah,
            "score": round(score, 4),
            "text": ref.text or "",
        })

    candidates.sort(key=lambda c: c["score"], reverse=True)
    candidates = candidates[: max(1, top_k)]

    return {
        "transcript": result.raw_text,
        "candidates": candidates,
        "message": None if candidates else "No matching verse found.",
    }


def _ordered_subsequence_score(transcript: list[str], ref: list[str]) -> float:
    """Fraction of the recited ``transcript`` that appears, in order, inside the
    reference ayah's word sequence (allowing gaps). 0 if nothing matches."""
    if not transcript or not ref:
        return 0.0
    i = 0
    for w in ref:
        if i < len(transcript) and w == transcript[i]:
            i += 1
    if i == 0:
        return 0.0
    # Coverage of the recited clip + a small bonus for a tight (exact) match.
    coverage = i / len(transcript)
    exact_bonus = 0.1 if (i == len(ref) and len(ref) == len(transcript)) else 0.0
    return min(1.0, coverage + exact_bonus)
