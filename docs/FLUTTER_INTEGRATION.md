# Flutter Mushaf UI — Integration Brief (Akeno)

**Backend:** Qari recitation service, 2-tier architecture (V50 Oracle for live
tracking + independent unprompted DP-aligner for word-level error evidence).
All URLs and payloads below were **verified live on 2026-09-26** against the
production stack, not written from the source alone.

Status of the numbers in §8: measured. Status of the 400 ms target: **not met
on current hardware** — read §8 before you design around it.

---

## 1. Base URLs

| Purpose | URL |
|---|---|
| REST base | `https://qari.pneumetron.com/v1` |
| WebSocket stream | `wss://qari.pneumetron.com/ws/recitation/stream` |

Note the WebSocket route is mounted at `/ws/...` and is **NOT** under `/v1`.
The Flutter app already derives this correctly in
`mobile/lib/core/constants/app_constants.dart` (`wsBaseUrl` swaps `https` →
`wss` and drops the `/v1` suffix). **Do not hardcode a different host.**

For a local/dev backend override with `--dart-define`:
```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8001 \
            --dart-define=WS_BASE_URL=ws://10.0.2.2:8001
```

---

## 2. Transport and TLS — no client changes required

* The domain sits behind **Cloudflare**, which terminates TLS with its own
  publicly-trusted certificate. Verified: `https://…/health` → `200`,
  `ssl_verify_result = 0`. `wss://…/ws/recitation/stream` handshake →
  `type: ready`, 62–67 ms.
* **Android:** `mobile/android/app/src/main/res/xml/network_security_config.xml`
  already whitelists `qari.pneumetron.com` on the **default system trust
  store** (no custom CA, no pinning) and permits cleartext **only** for
  `localhost` / `10.0.2.2`. You do **not** need to add a cleartext permission.
* **iOS:** no ATS exception is present and none is required for HTTPS/WSS.
* Origin nginx listens on **:80 only** — that is intentional and correct, because
  TLS terminates at the Cloudflare edge. Do not add `http://` URLs.



---

## 3. REST endpoints

| Endpoint | Method | Verified | Purpose |
|---|---|---|---|
| `/health` | GET | 200 | liveness |
| `/v1/recitations/ayahs/{surah}/{ayah}/words` | GET | 200, **1.7 ms** direct / **38 ms** via Cloudflare | Mushaf word list for a verse |
| `/v1/recitations/debug_echo` | POST | 200 `{"ok":true}` | device-side log echo (dev) |
| `/v1/recitations/{session_id}` | GET | 200 | fetch a past result |
| `/v1/recitations/{session_id}/audio` | GET | 200 | recorded audio playback |
| core-api `/v1/app/version` | GET | 200, **1.0.49 (71)** | OTA version check |

Latency note: the sub-5 ms figures are **direct to the origin** (`127.0.0.1:8001`).
Through Cloudflare expect **~30–150 ms** per REST call — that is TLS + edge
routing, not server time. Both paths were measured; neither is a problem at this
scale, but do not size a UX budget from the direct numbers.

### `GET /v1/recitations/ayahs/{s}/{a}/words` response

```json
{
  "surah_number": 109,
  "ayah_number": 1,
  "reference_audio_url": "",
  "words": [
    {"word_id": 1, "sequence_index": 1, "text_with_tashkeel": "قُلْ",
     "clean_text": "قل", "state": "active"},
    {"word_id": 2, "sequence_index": 2, "text_with_tashkeel": "يَـٰٓأَيُّهَا",
     "clean_text": "يايها", "state": "hidden"}
  ]
}
```

* `word_id` is **1-based** and is the join key against the WebSocket `word`
  event. Use it, not the array index.
* `text_with_tashkeel` → render the Mushaf text.
* `clean_text` → normalised, for search/highlight.
* `state`: the server sends `active` for the first word and `hidden` for the
  rest; the live stream then drives per-word state (§6).

Verified on 1:1 (4 words), 2:255 (**50 words** — the longest ayah, the layout
edge case), 18:10 (16), 112:1 (4).

---

## 4. WebSocket handshake

**Client → server**, first message, JSON text:

```json
{"type": "start", "surah_number": 1, "ayah_number": 1,
 "ayah_from": 1, "ayah_to": 1, "mode": "memorization",
 "sample_rate": 16000}
```

| Field | Notes |
|---|---|
| `type` | must be `"start"`; anything else closes with code **4000** |
| `surah_number` | 1-based |
| `ayah_number` | single-ayah mode |
| `ayah_from` / `ayah_to` | continuous range (full page / surah) |
| `mode` | `"memorization"` or `"tracking"` |

---

## 5. Audio contract — READ THIS, IT IS THE #1 SOURCE OF FEEL-BROKEN APP

| Property | Value |
|---|---|
| Container | **binary** WebSocket frames (not base64, not JSON) |
| Format | **PCM signed 16-bit little-endian** (mono) |
| Channels | **1** (mono) |
| Sample rate | **16000 Hz** exactly |
| Frame size | **3200 bytes = 100 ms** (accept 100–150 ms / 3200–4800 B) |
| Pacing | send in realtime as you capture |

### ⚠️ Do NOT buffer 1–2 second blocks before sending

This is the single most important rule in this document. Buffering on the device
adds your buffer time *on top of* the server's own analysis window, so a 2 s
device buffer guarantees ≥2 s of extra perceived latency before the server even
starts working on that audio.

Send each frame the moment it is captured. The server buffers frames itself
(`add_audio`) and re-transcribes on its own cadence in a background task — it
does **not** need, and does not want, a big client-side block.

**This was a real bug and it is fixed in the app.** The stream used to
accumulate every native mic chunk and flush the WHOLE buffer on a 250 ms timer
(`StreamingRecitationService._flushAudio`), which shipped 250 ms+ blobs — and
1–2 s blobs whenever the native cadence was slower. Framing is now
**size-driven**: whenever `_pcmFrameBytes` (3200) bytes are available they are
sent **immediately** (`_pumpFrames`, called from `_onNativeAudio`); the 100 ms
timer survives only as a safety net to release a *partial* trailing frame, never
to batch the stream. `mobile/test/audio_frame_contract_test.dart` (6 tests)
pins the invariant: no frame is ever > 3200 bytes, a partial frame is never
shipped early, and 1 s of audio yields exactly 10 frames.

Concretely: capture 100 ms → send → capture 100 ms → send. If you use
`MediaRecorder`/`AudioRecord`, read small buffers and forward immediately.

Resampling: the server expects 16 kHz. If the mic gives 44.1/48 kHz, resample
(or use the platform's 16 kHz source) — **do not** send a mismatched rate, the
handshake declares 16000 and the timing math depends on it.

Keep-alive: send `{"type":"ping"}`; the server replies `{"type":"pong"}`.
The session does not time out server-side.

Stop: send `{"type":"stop"}` → the server runs one final forced pass, sends
`{"type":"final", …}` and closes. Disconnecting mid-stream also persists
whatever was captured.

Close codes: `4000` bad first frame, `1011` session could not start,
`1000` normal.

---

## 6. Word verdict JSON + the frontend state machine

### The `word` event

```json
{"type": "word",
 "session_id": "…",
 "status": "match",
 "word_id": 1,
 "word_index": 0,
 "expected": "قُلْ",
 "spoken": "قُلْ",
 "confidence": 0.91,
 "timestamp_ms": 2140}

### Frontend word-state machine (contract — now implemented in the app)

The four states are enforced in code, not left to the caller:
`mobile/lib/features/recitation/presentation/word_view_state.dart` resolves every
word through `resolveWordViewState(serverStatus, index, cursor)`, and
`MushafRevealView` renders **only** the resolved view state — it never reads
`LiveWordStatus` directly for colour.

| state | how you get there | rendering rule |
|---|---|---|
| **unspoken** | index **>** cursor, or no verdict yet | neutral book ink. **Hard rule: never red, never a border/squiggle.** |
| **active** | index **==** cursor | primary colour + a 2.5 px underline pill |
| **correct** | behind the cursor, wire `status == "match"` | primary (green) |
| **mismatch** | behind the cursor, wire `status == "error_skipped"` | theme error colour (red) |

**Precedence (highest first):** `index > cursor` → unspoken; `index == cursor` →
active; then the wire status decides correct / mismatch.

THE RULE THAT KILLS THE RED SCREEN: a word ahead of the recitation cursor is
`unspoken` **even when the server says it was skipped**. The server can still
emit `error_skipped` for a word the reciter has not reached (a stale overlapping
window, or a mis-stitched hypothesis), and a client that trusts the wire blindly
is always one bad window away from painting the rest of the surah red. This was
the reported bug: *"on Ayah 2 the app turned the whole page red down to
الضالين"*. It is now covered by
`mobile/test/word_view_state_test.dart` (10 tests) and
`mobile/test/mushaf_red_wall_widget_test.dart` (5 widget tests that assert on
**rendered colours**), including the exact 25-word Al-Fatiha 1:1–1:7 page with
the cursor on 1:2.

Note the cursor moves **forward only**, and only to `idx + 1` of an accepted
event, so a duplicated or reordered server event can never drag it backwards.

### The `final` result

Sent after `{"type":"stop"}` (or on disconnect):

```json
{"type": "final", "session_id": "…", "status": "completed", "result": {
   "accuracy": 0.86,
   "confidence": 1.0,
   "tajweed_score": 0.0,
   "tajweed_issues": [],
   "word_verdicts": [
     {"word": "قُلْ", "word_index": 0, "is_correct": true, "confidence": 0.91,
      "expected_text": "قُلْ", "actual_text": "قُلْ",
      "error_type": null, "error_description": null,
      "reference_audio_url": null, "user_audio_url": "/v1/recitations/…/audio",
      "phoneme_errors": []}
   ]}}
```

`final` is the authoritative review: the whole recording is re-scored, so it may
correct a live call. Prefer it for the post-session summary screen.
`tajweed_*` is a best-effort pass that may be `0.0`/`[]`; never treat an empty
list as "no tajweed issues exist".

---

## 7. End-to-end flow

```
start ──▶ ready(words[])
           │

---

## 8. Measured latency baseline (2026-09-26) — read before designing

All figures measured on the live 4-vCPU VPS, real audio (3.11 s clip, ayah 109:1,
3 words), 5 repeats.

| Metric | Measured |
|---|---|
| `ready` handshake, direct (`:8001`) | **2.5 ms** |
| `ready` handshake, via Cloudflare | **62 – 67 ms** |
| **First `word` event, single session** | **2089 – 2118 ms** (≈2.1 s) |
| Words correctly identified | **3/3 `match`** every run |
| Single-window decode (repo benchmark) | p50 **0.977 s**, p95 **0.991 s**, RTF 0.16, budget 1.2 s |
| Same decode with a 2.5 s window instead of 7.5 s | p50 **0.977 s**, p95 **0.977 s** — **no change** |

### The 400 ms target is NOT met, and here is exactly why

The ~2.1 s first-word latency decomposes as **~1.2 s waiting for the first
transcription interval + ~1.0 s for the unprompted Whisper decode**.

The decode term is a **hard floor on this hardware**. Whisper pads every input
to 30 s internally, so decode cost is independent of window length — proven by
measurement above: 7.5 s and 2.5 s windows both take **0.977 s**. Therefore no
amount of window/interval tuning can get below ~1 s per pass on this CPU.

**An "early first pass" was built, measured, and deliberately left OFF.** It
fired pass #1 after 0.5 s of audio instead of 1.2 s. Result:

| Setting | First-word latency (5 runs) |
|---|---|
| **OFF (shipped default)** | 2081 / 2093 / 2112 / 2118 ms — **p50 ≈ 2103 ms** |
| ON (tried) | 3137 / 3139 / 3142 / 3145 ms — **p50 ≈ 3141 ms, ~1 s WORSE** |

0.5 s of audio is below what Whisper needs to emit a usable transcript, so the
"early" pass burned a full ~1 s decode producing nothing and pushed the real
first word out by exactly that. The flag stays in the code
(`QARI_EARLY_FIRST_PASS=1` re-enables it) so the negative result is reproducible
rather than folklore, and a unit test pins the default OFF.

* `TRANSCRIBE_WINDOW_SEC = 6.0` and `VERIFY_EVERY_N_PASSES = 1` are deliberately
  **unchanged** — a 5 s window previously "lost the boundary-word context and
  stalled the end of the surah", and `VERIFY_EVERY_N_PASSES=2` produced 5–13 s
  apparent latency. Both are pinned by a contract test.
* **To actually reach ~400 ms** you need the planned AWS G4dn/G5 GPU
  migration, or replacing the per-pass Whisper decode with a VAD +
  forced-alignment path. Do not design the UI around sub-second word reveal on
  the current VPS.

### Live tracking quality (verified on a real Al-Fatiha recitation, 1:1–1:7)

| Metric | Result |
|---|---|
| Expected words | 29 |
| Word events emitted | 24, **all `match`** |
| False red marks (`error_skipped`) | **0** |
| Reveal progression | strictly monotonic, max step **1 word** |
| `tajweed_score` computed | 0.381 |

The last 5 words are the natural tail of the clip, not a stall: word_ids advanced
one at a time to the end with no jump and no false red.

### ⚠️ Concurrency ceiling (important for release planning)

| Concurrent sessions | First-word p50 | Under 2 s |
|---|---|---|
| 1 | ~2.1 s | marginally |
| **3** | **6.72 s** (max 6.95 s) | **0 / 3** |

4 vCPU, two decode threads per session, no container CPU limit. Three
simultaneous users oversubscribe the box ~3×. **Plan for a single active
session per user, and expect degradation with several concurrent users** until
the GPU migration lands.

### Operational switches (server-side; Akeno does not set these)

| Env var | Default | Effect |
|---|---|---|
| `QARI_EARLY_FIRST_PASS` | `0` | early first pass — **measured slower, left OFF** |
| `QARI_EARLY_FIRST_PASS_SEC` | `0.5` | audio required before pass #1 (only if enabled) |
| `QARI_EARLY_FIRST_PASS_WINDOW_S` | `2.5` | window length for pass #1 (only if enabled) |
| `QARI_LIVE_REACH` / `QARI_LIVE_REACH_WIDE` | `3` / `8` | live aligner search bounds |
| `QARI_AYAH_LOOKAHEAD` | `1` | how many ayahs ahead the aligner may anchor |
| `QARI_STREAM_DEBUG` | `0` | set `1` for verbose per-pass aligner logs |

---

## 9. Dev-only cleartext fallback (raw IP testing)

**Only if** you must test against a raw IP such as
`http://15.252.136.111:8001` / `ws://15.252.136.111:8001`. The app's existing
`network_security_config.xml` already permits cleartext for `localhost` and
`10.0.2.2` (emulator). To add a raw-IP host, append to
`mobile/android/app/src/main/res/xml/network_security_config.xml`:

```xml
    <!-- DEV ONLY: raw-IP cleartext. NEVER ship this in a release build. -->
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">15.252.136.111</domain>
    </domain-config>
```

Release builds must use `wss://qari.pneumetron.com` and must **not** carry this
block. iOS would additionally need
`NSAppTransportSecurity → NSAllowsLocalNetworking` for local testing.

---

## Quick checklist for Akeno

- [ ] Use `wss://qari.pneumetron.com/ws/recitation/stream` (no `http`, no port).
- [ ] First message is `{"type":"start", …, "sample_rate":16000}`.
- [ ] Send **binary** PCM16 mono 16 kHz, 3200-byte frames, sent immediately.
- [ ] **Never buffer 1–2 s of audio before sending.**
- [ ] Branch on `status == "match"` / `"error_skipped"` — not `matched`/`error`.
- [ ] Join events to words by **`word_id`** (1-based), not array index.
- [ ] Keep ahead-of-cursor words neutral — no red, no squiggle.
- [ ] Treat `final` as the authoritative summary.
- [ ] Expect **~2.1 s** for the first word, and **worse with concurrent users**,
      until the GPU migration. Do not design around sub-second reveal.

           ├── binary PCM frames (100 ms)  ──▶ word{status:"match"|"error_skipped"}
           │                                      (keyed by word_id)
           ├── ping ──▶ pong
           │
           └── stop  ──▶ final{result{…}}  ──▶ close
```


```

> **`status` has exactly two values: `"match"` and `"error_skipped"`.**
> The server's own docstring used to advertise `matched` / `error` / `skipped`;
> that was wrong and is fixed. If you code against the old names, **every word
> renders incorrectly**. `word_id` is the 1-based id from `ready` / the REST
> words endpoint; `word_index` is the 0-based index (kept for debugging).

`confidence` is the aligner's score for that word — it is **not** a calibrated
probability. Do not present it as a percentage of correctness.


| `sample_rate` | **16000** |
| `words` | *optional* fallback word list, only if the server has no reference |
| `ayahs` | *optional* explicit ordered `[[surah, ayah], …]` list |

**Server → client**, `ready`:

```json
{"type": "ready", "session_id": "...", "surah_number": 109,
 "ayah_from": 1, "ayah_to": 1, "mode": "tracking",
 "words": [{"word_id": 1, "sequence_index": 1,
            "text_with_tashkeel": "قُلْ", "clean_text": "قل",
            "state": "active"}]}
```

Handshake measured **2.5 ms** direct / **62 ms** through Cloudflare.
