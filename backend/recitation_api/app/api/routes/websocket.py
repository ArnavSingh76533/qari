"""WebSocket routes for recitation.

Two endpoints:

* ``/ws/recitation/stream`` — **real-time streaming** recitation. The client
  streams audio continuously and receives word-by-word match events live
  (Tarteel-style live tracking + memorization mode). MUST be declared before
  the ``{session_id}`` route so ``stream`` isn't matched as a path param.
* ``/ws/recitation/{session_id}`` — result feed for the batch upload flow
  (subscribes to the session's Redis Pub/Sub channel).
"""

import asyncio
import json
from typing import Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
import redis.asyncio as redis

from app.core.config import settings
from app.core.logging import get_logger
from app.core.security import user_id_from_authorization, verify_access_token
from app.services.streaming_session import StreamingRecitationSession

logger = get_logger(__name__)
router = APIRouter(tags=["websocket"])

_redis: Optional[redis.Redis] = None


def _parse_ayah_refs(payload: object) -> Optional[list[tuple[int, int]]]:
    """Normalize a client-supplied ``ayahs`` field into a list of
    ``(surah, ayah)`` tuples. Accepts ``[[s, a], ...]`` or
    ``[{"surah": s, "ayah": a}, ...]``. Returns ``None`` when missing/invalid
    so the caller falls back to a single-surah range.
    """
    if not isinstance(payload, list) or not payload:
        return None
    refs: list[tuple[int, int]] = []
    for item in payload:
        try:
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                refs.append((int(item[0]), int(item[1])))
            elif isinstance(item, dict):
                refs.append((int(item["surah"]), int(item["ayah"])))
        except (ValueError, KeyError, TypeError):
            continue
    return refs or None


def _get_redis() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.redis_url, decode_responses=True)
    return _redis


async def _safe_close(websocket: WebSocket, code: int = 1000) -> None:
    try:
        await websocket.close(code=code)
    except Exception:
        pass


# NOTE: this MUST be registered before ``/ws/recitation/{session_id}`` below,
# otherwise Starlette matches ``stream`` as a session_id path parameter.
@router.websocket("/ws/recitation/stream")
async def recitation_stream(websocket: WebSocket):
    """Real-time streaming recitation (Tarteel-style live word tracking).

    Protocol
    --------
    client → server (first message, JSON text)::

        {"type": "start", "surah_number": 1, "ayah_number": 1,
         "ayah_from": 1, "ayah_to": 1, "mode": "memorization"|"tracking",
         "sample_rate": 16000, "access_token": "<backend JWT>"}

    Authenticate with an Authorization: Bearer upgrade header, or include
    access_token in the first message for browser clients. Tokens in query
    strings are not accepted.

    server → client::

        {"type": "ready", "session_id": ..., "words": [{index, text}...]}

    client → server: raw PCM16 mono audio frames as **binary** messages,
    streamed continuously (the session never times out server-side).

    server → client (as words resolve)::

        {"type": "word", "session_id": ..., "word_id": n, "word_index": i,
         "status": "match"|"error_skipped",   # NOT "matched"/"error"/"skipped"
         "expected": ..., "spoken": ..., "confidence": 0.0-1.0,
         "timestamp_ms": ...}

    NB the ``status`` values are the BLUEPRINT contract and are exactly two:
    ``match`` (correctly revealed) and ``error_skipped`` (skipped or
    mispronounced), keyed by the 1-BASED ``word_id``. An earlier version of this
    docstring advertised ``matched``/``error``/``skipped``, which the server has
    never emitted — a client written against it would mis-colour every word.

    client → server: ``{"type": "stop"}`` (or disconnect) → server replies with
    ``{"type": "final", "result": <RecitationAnalysisResult>}`` and closes.
    """
    authorization = websocket.headers.get("authorization")
    user_id = user_id_from_authorization(authorization)
    if authorization and user_id is None:
        await _safe_close(websocket, code=4401)
        return
    await websocket.accept()

    # --- Handshake: wait for the start message ---
    try:
        start = await asyncio.wait_for(
            websocket.receive_json(), timeout=settings.websocket_start_timeout_sec,
        )
    except asyncio.TimeoutError:
        await _safe_close(websocket, code=4401)
        return
    except (WebSocketDisconnect, json.JSONDecodeError, RuntimeError):
        await _safe_close(websocket)
        return

    if not isinstance(start, dict) or start.get("type") != "start":
        await websocket.send_json({
            "type": "error",
            "detail": "First message must be {'type': 'start', ...}",
        })
        await _safe_close(websocket, code=4000)
        return

    if user_id is None:
        user_id = verify_access_token(start.get("access_token"))
    if user_id is None:
        await _safe_close(websocket, code=4401)
        return

    surah = int(start.get("surah_number", 1))
    ayah_number = start.get("ayah_number")
    ayah_from = int(start.get("ayah_from", ayah_number or 1))
    ayah_to = int(start.get("ayah_to", ayah_number or ayah_from))
    mode = start.get("mode", "tracking")
    sample_rate = int(start.get("sample_rate", settings.audio_sample_rate))

    # Continuous (full-page / full-surah) mode sends an explicit ordered list
    # of [surah, ayah] pairs. Fall back to a single-surah range when absent.
    ayah_refs = _parse_ayah_refs(start.get("ayahs"))

    # Client-supplied word list (sent by the app) — used as a fallback reference
    # when the server's own reference store is empty.
    client_words = start.get("words")
    if not isinstance(client_words, list):
        client_words = None

    session = StreamingRecitationSession(
        surah=surah,
        ayah_from=ayah_from,
        ayah_to=ayah_to,
        ayah_refs=ayah_refs,
        mode=mode,
        sample_rate=sample_rate,
        client_words=client_words,
    )
    try:
        await asyncio.to_thread(session.load_reference)
    except Exception as exc:
        logger.error("ws.stream.load_ref_failed", error=str(exc))
        await websocket.send_json({
            "type": "error",
            "detail": str(exc) or "Live recitation could not be started.",
        })
        await _safe_close(websocket, code=1011)
        return

    # Bind ownership before acknowledging or accepting audio frames. Session
    # finalization merges this hash, preserving the verified owner field.
    r = _get_redis()
    try:
        await r.hset(
            f"qari:recitation:session:{session.session_id}",
            mapping={
                "session_id": session.session_id,
                "user_id": user_id,
                "status": "processing",
                "source": "stream",
                "surah_number": str(session.surah),
                "ayah_from": str(session.ayah_from),
                "ayah_to": str(session.ayah_to),
            },
        )
        await r.expire(f"qari:recitation:session:{session.session_id}", 86400)
    except Exception:
        logger.error("ws.stream.owner_storage_failed", session_id=session.session_id)
        await _safe_close(websocket, code=1011)
        return

    await websocket.send_json(session.ready_payload())
    logger.info(
        "ws.stream.started",
        session_id=session.session_id,
        surah=surah,
        ayah_range=f"{ayah_from}-{ayah_to}",
        mode=mode,
        words=len(session.reference_words),
    )

    finalized = False
    # A single background task owns transcription so the receive loop never
    # blocks on the (slow) Whisper call. Frames are buffered by `add_audio`
    # the instant they arrive; the background task re-transcribes on its own
    # cadence and emits `word` events. Without this, `maybe_transcribe` ran
    # inline on every binary frame, stalling `websocket.receive()` and making
    # the live tracker fall further and further behind real time on long
    # surahs ("tracker writing too slow").
    transcribe_task = asyncio.ensure_future(session.transcription_loop(websocket))
    try:
        while True:
            message = await websocket.receive()

            if message.get("type") == "websocket.disconnect":
                break

            data = message.get("bytes")
            if data:
                # Buffer only — transcription happens in the background task.
                session.add_audio(data)
                continue

            text = message.get("text")
            if text:
                try:
                    payload = json.loads(text)
                except json.JSONDecodeError:
                    continue
                if payload.get("type") == "stop":
                    # Tell the background task to stop looping, then do one
                    # forced final transcription + emit the `final` result.
                    await session.stop_transcription()
                    for event in await session.maybe_transcribe(force=True):
                        await websocket.send_json(event)
                    result = await session.finalize()
                    await websocket.send_json({
                        "type": "final",
                        "session_id": session.session_id,
                        "status": "completed",
                        "result": result,
                    })
                    finalized = True
                    break
                if payload.get("type") == "ping":
                    await websocket.send_json({"type": "pong"})

    except WebSocketDisconnect:
        logger.info("ws.stream.disconnected", session_id=session.session_id)
    except Exception as exc:
        logger.error("ws.stream.error", session_id=session.session_id, error=str(exc))
    finally:
        await session.stop_transcription()
        try:
            transcribe_task.cancel()
            await transcribe_task
        except (asyncio.CancelledError, Exception):
            pass
        if not finalized:
            # Persist whatever we captured so history / A/B playback still work.
            try:
                await session.finalize()
            except Exception:
                pass
        await _safe_close(websocket)


@router.websocket("/ws/recitation/{session_id}")
async def recitation_websocket(websocket: WebSocket, session_id: str):
    """WebSocket for real-time recitation results.

    The client connects after uploading audio and receiving a session_id.
    The server:
    1. Validates the session exists in Redis.
    2. Subscribes to the session's Redis Pub/Sub channel.
    3. Forwards progress updates and word results to the client.
    4. Closes when the session reaches a terminal state (completed/failed).
    """
    user_id = user_id_from_authorization(websocket.headers.get("authorization"))
    if user_id is None:
        await _safe_close(websocket, code=4401)
        return
    r = _get_redis()

    # --- Validate session ---
    session_data = await r.hgetall(f"qari:recitation:session:{session_id}")
    if not session_data or session_data.get("user_id") != user_id:
        await _safe_close(websocket, code=4404)
        return

    await websocket.accept()

    current_status = session_data.get("status", "queued")

    # If already terminal, send final result and close
    if current_status in ("completed", "failed"):
        await _send_final_result(websocket, r, session_id, session_data)
        await websocket.close()
        return

    # --- Send initial status ---
    await websocket.send_json({
        "session_id": session_id,
        "status": current_status,
        "message": "Connected, waiting for inference results...",
    })

    # --- Subscribe to Redis Pub/Sub channel ---
    channel = settings.recitation_results_channel.format(session_id=session_id)
    pubsub = r.pubsub()
    await pubsub.subscribe(channel)

    # --- Also poll session status as fallback ---
    try:
        while True:
            # Check for Pub/Sub messages
            message = await pubsub.get_message(ignore_subscribe_messages=True, timeout=1.0)
            if message and message["type"] == "message":
                try:
                    data = json.loads(message["data"])
                    await websocket.send_json(data)

                    # Check if terminal
                    if data.get("status") in ("completed", "failed"):
                        break
                except json.JSONDecodeError:
                    logger.warning("ws.invalid_message", session_id=session_id)

            # Fallback: poll session status
            session_data = await r.hgetall(f"qari:recitation:session:{session_id}")
            if session_data:
                new_status = session_data.get("status", "queued")
                if new_status in ("completed", "failed") and new_status != current_status:
                    await _send_final_result(websocket, r, session_id, session_data)
                    break
                current_status = new_status

            await asyncio.sleep(0.5)

    except WebSocketDisconnect:
        logger.info("ws.disconnected", session_id=session_id)
    except Exception as exc:
        logger.error("ws.error", session_id=session_id, error=str(exc))
    finally:
        await pubsub.unsubscribe(channel)
        await pubsub.close()
        try:
            await websocket.close()
        except Exception:
            pass


async def _send_final_result(websocket: WebSocket, r: redis.Redis, session_id: str, session_data: dict) -> None:
    """Send the final result payload over WebSocket (mobile-shaped)."""
    status_val = session_data.get("status", "completed")
    result_raw = await r.get(f"qari:recitation:result:{session_id}")
    result = json.loads(result_raw) if result_raw else None

    final_payload = {
        "session_id": session_id,
        "status": status_val,
        "error_message": session_data.get("error_message"),
        "completed_at": session_data.get("completed_at"),
        "result": result,
    }
    await websocket.send_json(final_payload)
