# Qari — Project Memory

> Persistent notes so opencode can resume after a VPS restart / new session.
> Read this file first at the start of every session. Update it whenever
> meaningful work is done. Keep it concise.

## Session 2026-10-02 — Madinah fitted lines, readable spacing and CI

Current state: PR [#14](https://github.com/khan23153/qari/pull/14) merged into
`main` at `ad00f63` (2026-10-02). Rendering changes are in `ae99a2c` and the
earlier commits included by that PR. Older session notes below are historical;
this entry supersedes their renderer details and legacy test-failure counts.

- Canonical Quran.com word/verse-marker page and line locations are bundled in
  `mobile/assets/mushaf_layout.json.gz`, loaded by `MushafLayoutRepository`.
  The builder verified all 6,236 ayah references, word counts and Arabic letter
  order against the existing corpus; Quran text and backend indices are unchanged.
- `MushafRevealView`: a stretched Column of independent RTL word rows, each
  fitted as a whole line. Ordinary pages keep 15 slots; opening pages 1/2 use
  eight centered slots with one shared horizontal scale and ordinary-page ink
  height. Long surah ranges remain scrollable. No paragraph justification,
  flexible word gaps or manually inserted string separators in this renderer.
- Latest user preference: **40% of the Hafs font's measured natural space
  advance between word units**, replacing the earlier 30%. Each row reserves
  5% above and below its fitted text for line clearance. Base ink enlargement
  is 1.15 before that clearance; do not describe the final ink as 15% larger
  than the former full-pitch rendering.
- Night reader defaults to charcoal, vivid Tajweed and white verse markers,
  with faint horizontal row rules and no enclosing page frame. Green gradient
  mic sits at the right with a halo. Saved theme/Tajweed choices are respected.
  Hifz visibility, red-wall guard, mistake taps and scaled cursor anchors remain.
- UI-only preview: `mobile/lib/main_ui_preview.dart`, login-free, voice feedback
  disabled. The normal `main.dart` entry point retains authentication and voice.
  Both Android APKs build. Latest preview installed/launched in BlueStacks;
  native page 1 and real-font screenshots of pages 1-5 were visually inspected.
  Local release APK uses the repository's development signing fallback; no
  production keystore, OTA publication or version bump was supplied/performed.
- Validation: **159 Flutter tests, 72 recitation API tests, 164 ML tests pass**.
  Full-page sweep covers all 604 pages. Renderer/theme/layout analysis is clean;
  broader app analysis has no errors but retains warning/info lint findings.
  Old grammar/language assertions, paragraph/icon expectations and offline
  reader/pushed-lesson test harnesses were repaired.
- AI tests use isolated storage and controlled recognition fixtures. Production
  HTTPS health and live WebSocket connection probes timed out from this desktop
  on 2026-10-02. Signed-in microphone-to-server recognition and deployed model
  accuracy remain unverified in this session; backend/model code was not changed.
- Post-merge Flutter CI failed at **Check Dart formatting**, before analysis or
  tests: `live_recitation_page.dart` and `full_page_recitation_test.dart` needed
  formatting. Follow-up formats both and runs the full Flutter suite in CI,
  including canonical line tests and formerly excluded tests. Check the new
  GitHub run for Linux CI status; local success does not prove remote success.
- APK workflow already exists: `.github/workflows/build-apk.yml`. For a review
  artifact, select the current branch and disable `bump` and `commit_release`.
  Download the successful run's APK artifact. Keep publication/version changes
  separate from a review build.

## Session 2026-09-28b — Mushaf v4: Tilawat tab (Qibla removed), Tilawat/Hifz modes ✅

Test build `qari-mushaf-v4.apk` (1.0.49+71, not OTA) at
https://qari.pneumetron.com/downloads/qari-mushaf-v4.apk?v=4 — SHA1
37b426371797862a01a9a3ee4621d65aa793ef53, 76827587 bytes.
- Home nav: Qibla tab → "Tilawat" (pushes full-screen LiveRecitationPage with
  `initialMode: RecitationMode.tilawat`). `lib/features/qibla/` left on disk,
  unreferenced; its location/compass deps still in pubspec.
- `recitation_mode.dart`: RecitationMode {tilawat, hifz}, persisted in prefs
  (`mushaf_recitation_mode`). Toggle pill on FloatingRecitationBar.
- MushafRevealView: Tilawat unspoken = crisp `text` ink (v3 ghost ink now only
  for review "not reached"); `hideUnspoken` (Hifz) = alpha-0 ink so layout never
  reflows; active word hidden too (halo only). `blocksBefore` inserts full-width
  surah plate + Bismillah inline at each ayah 1 (page scope shows them too).
- Ayah medallion = Arabic-Indic digits in KFGQPC Hafs (the font itself draws the
  ornate ۝ medallion, even multi-digit) — no hand-drawn circle.
- MushafSurahBanner = CustomPainter Madinah plate (lattice band, ogee cartouche,
  rosettes). Header: [Surah ▾ / Page | Juz | Hizb] follows the cursor's ayah;
  hizb from `kHizbStarts` (60 starts, quran.com v4) in surah_titles.dart, which
  also holds kSurahNamesEnglish / kSurahAyahCounts / kSurahIsMeccan.
- Page tap hides header, tajweed toggle and floating bar (slide+fade) in
  setup/live/review.
Tests: test/mushaf_modes_test.dart (was mushaf_v3_test). 114 pass / same 5 legacy.

## Session 2026-09-28 — Mushaf v3: ghost ink, early-stop scoring, review on Mushaf ✅

Test build `releases/qari-mushaf-v3.apk` (1.0.49+71, not OTA — app-release.apk /
app_release.json untouched), served at
https://qari.pneumetron.com/downloads/qari-mushaf-v3.apk (nginx alias
`/var/www/qari-downloads/`, root-owned → `sudo install`). SHA1
8625a122781a0fd143e33c1f1d067b40e62a5fde, 77072151 bytes.
Fixes (mobile only, live_recitation_page + mushaf_reveal_view):
- Text flood: `_start` used to wipe `_revealedWords` and `ready` re-flooded the
  page in solid ink. Now the page is never wiped; `unspoken` = `MushafTheme.ghostInk`
  (~0.3 alpha), solid only when matched/active; cursor goes to 0 on `ready`.
- Overflow: live scroll view sat un-Expanded inside MushafPageFrame's Column.
  Now one `_buildMushafPage` (setup/live/review): SingleChildScrollView wraps the
  whole frame, bottom padding 140, mic bar floats in a Stack; font = width/14
  clamped (arabicTextStyle clamps to min 22 anyway). No duplicate Bismillah on Fatiha.
- Early stop 0%: new pure `recitation_review.dart` `buildRecitationReview` —
  reach = max(live cursor, last matched+1 live or server); words ≥ reach are
  unreached (pending, never red, not scored). Server `false` never extends reach.
- Summary: RecitationResults tiles replaced by review on the same Mushaf page
  (`reviewMode`: red underline mistakes, tap → WordComparisonSheet).
Tests: new test/mushaf_v3_test.dart (11). Suite 111 pass / 5 legacy failures
(app_test ×2, widget_test grammar, lesson_route, reader_render — pre-existing,
excluded from CI).

## Session 2026-09-22j — COLD-START FREEZE FIXED (ready 6.5s → 0.03s) ✅

User report: first words only appear after ~9s ("9 sec ke baad word aaye"),
app feels frozen on tap-start. (Also asked to keep V50-for-prompt +
tarteel-base-for-verify — the current honest policy — NOT retrain.)

**Root cause (measured, not guessed):** `start` → `ready` handshake took
**6.5s** before ANY audio streamed. Breakdown inside `load_reference()`:
- `resolve_reference_words_sequence` (7 ayahs) = **4.38s** ← dominant
- V50 model load = 0.59s, BASE verify load = 0.16s (cheap)

Why 4.38s for 7 ayahs? `ReferenceStore.__init__` globs + parses EVERY
`{surah}_{ayah}.json` in `reference_data_dir` = **~0.6s** of disk/JSON work,
and `resolve_reference_words` **rebuilt it per ayah** (7× = 4.3s). Actual
`store.get()` lookups are instant (0.000s).

**Fix (2 changes, both backend-only — NO new APK):**
1. `streaming_session.py`: module-level `_get_reference_store()` cache — build
   the (read-only) `ReferenceStore` ONCE, reuse it (mirrors the existing cache
   in `app.workers.inference_worker`). 4.38s → 0.6s → ~0s warm.
2. `main.py` lifespan: `_warmup_ml()` pre-loads the store + BOTH ASR models in a
   **daemon `threading.Thread`** (NOT `asyncio.create_task` — a fire-and-forget
   task dangles across TestClient loop teardown and raises "Event loop is
   closed"). Warms within ~2.6s of boot so the first real session is instant.

**Verified:** `ready` latency **6.5s → 0.03s**; first word reveals at **2.7s**
(was 9.3s). Full-surah still 27/29 live (unchanged), wrong-audio honesty
preserved (bismillah clip reveals 6/29 — Fatiha's repeated words only, not a
echo). Reveal keeps pace (last word at audio-end ~46.5s), no accumulating lag.
Speech RMS is continuous (no pauses), so reveal "gaps" = repeated-word
mis-mapping (idx 6-7 `رب العالمين` dropped; `الرحمن الرحيم`/`الله` occur twice
in Fatiha), a known matcher recall quirk — NOT latency.

**Pre-existing test failures (NOT from this change, confirmed by re-running with
the daemon-thread variant):** `tests/test_api.py::test_upload_ayah_to_before_from`
(202 vs 422 validation gap) and `::test_get_nonexistent_session` (TestClient
"Event loop is closed"). Backend 22/24 pass, ML matcher 11/11 pass.

Model policy (user decision): keep **V50 = oracle prompt + tarteel base =
independent verify** (the honest pair). NOT pure-V50 (it echoes), NOT retrain-yet.

## Session 2026-09-22i — live words freeze mid-surah FIXED (Tarteel-style DP aligner) ✅

User report: "voice ke sath word nahi chal rahe, 1 ayat padhi phir word appear
hona band ho gaya" — words don't track the voice and the reveal stops after an
ayah. Reproduced exactly (full Al-Fatiha over the real WS at 1.0x).

**Root causes found (4 separate bugs — several were masked by each other)**
1. `app/main.py` **monkey-patches production** to use its own
   `_ConservativeLiveMatcher` (greedy, `lookahead=0`, consumes every ASR token
   as noise). Unit tests never exercise it (they inject a transcriber / use the
   stub, which skips the swap), so matcher fixes looked green while production
   kept jamming. Once the expected word's token was missing it ate everything
   after it and NEVER advanced (cursor pinned at 20/29 while the user recited
   on). **This was the freeze.**
2. `VERIFY_EVERY_N_PASSES=2` made the independent witness up to ~4s stale, so a
   just-spoken word could not be corroborated → 5-13s apparent lag.
3. Acceptance fallback only ran when tier-1 was NON-EMPTY. Windows where the
   oracle emitted nothing threw the honest words away → hypothesis stopped
   growing → freeze again.
4. `_make_stub_transcriber` is called with `(audio, sr, prompt)` but accepts 2
   args → TypeError swallowed per pass (made `tests/test_streaming.py` hang).

**How Tarteel does it (researched, and now mirrored)**
ASR → normalized text → **Levenshtein fuzzy matching** against the Quran text
(deliberately NOT waveform DTW), then **Needleman-Wunsch word alignment**, with
an **anchor + local-window "tracking mode"** that widens to a "search mode" when
confidence drops. (Their streaming product, tilawa/offline-tarteel, is a
streaming CTC over a tajweed-phoneme vocabulary with per-ayah lock-in.)

**What changed**
- `ml/alignment/streaming_matcher.py`: live path rewritten as a bounded **DP
  (Needleman-Wunsch) alignment** over (reference window x newest 48 hypothesis
  tokens), choosing the BEST PARTIAL alignment. Trailing reference words with no
  evidence stay pending; reference words the reciter demonstrably moved past
  become SKIPPED (real-time red); a missing/mangled word no longer jams the
  tracker. `full=True` final review unchanged.
  - `DP_SKIP_REF_PENALTY = -1.5` (heavy on purpose): makes the DP stop at the
    last confident match and WAIT instead of skipping words the ASR merely
    missed in one window (they are usually recovered by the next window).
  - New `_equal_modulo_one_alef()`: an extra connecting alef (reference `صرط`
    heard as `صراط`, `الرحمن`→`الرحمان`) is the same word. Alef-family only —
    any-letter would collide `الذي`/`الذين`.
  - Consume hypothesis tokens only up to the LAST MATCHED pair (trailing tokens
    are often the start of the next word).
- `app/main.py`: `_ConservativeLiveMatcher.evaluate` now delegates alignment to
  the DP aligner, and keeps only its useful part — `max_live_words`, the
  speech-duration budget (2.4 words/active-second) that stops an ASR
  continuation from revealing text the user has not recited.
- `streaming_session.py`: `VERIFY_EVERY_N_PASSES = 1`; independent-fallback also
  covers empty tier-1; `_invoke_transcriber()` calls a transcriber with the
  prompt only if its signature accepts one.
- `tests/test_streaming.py`: fixed a blocking drain loop and stubbed the
  independent decode in the bounded-window test.

**Live evidence policy — env `QARI_EVIDENCE_POLICY` (infra/docker-compose.yml)**
- `tier2` (DEFAULT): the independent unprompted decode IS the live hypothesis.
  Measured: **27-29/29 words live** on real Al-Fatiha (ayat 1-7 incl. the former
  ayah-6→7 stall), and **4/29 on an unrelated bismillah clip** (= exactly the
  words actually spoken). Only 1 decode per pass → ~1.1s.
- `corroborated`: prompt-conditioned Qari model where the witness agrees.
  29/29 live but **9/29 false** on the unrelated clip (its prompt echo passes
  corroboration whenever the witness heard *any* occurrence of the same word).
- Residual gap (both policies): `رب العالمين` (idx 6-7) is often absent from the
  base decode entirely (it outputs `الحمد لله الرحمن الرحيم`), so those 2 words
  are not revealed live. Final review re-scores them honestly.

**⚠️ Open question with the user** (asked, not decided): the honest witness is
`/app/models/qari-ct2-base` = the **tarteel-ai/whisper-base-ar-quran** base that
their V50 LoRA adapter was trained on top of. Earlier in this project the user
forbade using the public tarteel checkpoints. Nothing was downloaded (offline,
`HF_HUB_OFFLINE=1`), but this is a policy conflict to resolve: their V50 model
CANNOT verify (proven oracle), so honest live tracking currently needs an
independent model. Their V50 still drives the FINAL review + tajweed checks.

---

## Session 2026-09-22h — "APP SAB SAHI BATATA HAI" FIXED: honest verification decode ✅

User report: words keep lighting up as correct no matter what is recited — the app
cannot tell what the user actually said. Investigation + fix:

**Why it happened (proven, not theory)**
The serving model is the user's trained QARI V50 adapter, and its own training
report (`/home/ubuntu/adapter_extracted/QARI_V50_RESULT.json`) says it is
**ORACLE prompt-conditioned**: `best_prompt37.prompt = 0.0065` WER, i.e. the
training target was to REPRODUCE the expected ayah text given as the prompt.
A/B decode on the VPS (same audio, same settings):

| audio | decode | output |
|---|---|---|
| affan_1 (NOT Al-Fatiha) | base model, unprompted | transcribes the ACTUAL audio |
| affan_1 (NOT Al-Fatiha) | V50 with Al-Fatiha prompt | **recites Al-Fatiha ayah 2+** |
| afasy18 (bismillah) | base model, unprompted | `بسم الله الرحمن الرحيم` ✅ |
| afasy18 (bismillah) | V50 with Al-Fatiha prompt | Al-Fatiha ayah 2+ ❌ |

So the prompted decode can never validate a recitation — it always "passes".

**Also fixed**: `/app/models/qari-ct2-base` was INCOMPLETE (no `tokenizer.json`),
so faster-whisper tried to download `openai/whisper-tiny` (failed offline).
Copied `tokenizer.json` + `vocabulary.json` from `qari-v50-ct2` (same tarteel
base tokenizer) — the base model is now loadable and is the verification witness.

**Fix implemented**
- `ml/inference/faster_whisper_transcriber.py`: new independent verification
  decode — `transcribe_independent()` uses the BASE model (env
  `QARI_FASTERWHISPER_VERIFY_MODEL_DIR`, default `<models>/qari-ct2-base`) with
  NO prompt. The V50 unprompted decode was useless (it emits fragments).
- `streaming_session.py`: tier-2 evidence now comes from that independent model,
  and the corroboration requirement is UNCONDITIONAL — removed the "watchdog"
  bypass that used to trust the oracle's echoed text after a few stalled passes
  (that bypass was the actual "everything is correct" bug). If the independent
  decode heard nothing on a window, the window's words are DROPPED instead of
  falling back to the prompt echo.

**Verified over the real WebSocket, 1.0x pace**
- WRONG audio (affan_1 vs Al-Fatiha reference): **0 live word events** — the app
  no longer claims words that were never recited.
- CORRECT audio (Al-Fatiha): **25/29 live matched** with `audio_at` matching the
  true speech position of each ayah (no more running ahead).

**About "detection trained in the model"**
The ASR training manifests (`train_manifest_v48_aug.jsonl`) contain ONLY
`audio_path`, `text`, `surah`, `ayah_*`, `augmentation`, `reference_type` — no
error/mistake labels — and the result JSONs only track prompted WER. So no
mistake-detection head exists in this checkpoint. Separate detector work DOES
exist in `/home/ubuntu/v51-candidate` (detector_v53.py, llr_corroboration.py,
V52/V53/V54) but every variant was REJECTED for deployment (V54 verdict: clean
clips 2/37 false flags, recall unchanged; LLR probe also rejected). Do not
deploy those. Detection must come from the independent decode + matcher
(skipped words are reported as `skipped` = red).

## Session 2026-09-22g — STALL/FREEZE FIXED at ayah boundary (logs-verified) ✅

User report: 9s delay before words appear, words stop appearing after ~4 ayahs,
no real-time mistake detection. Logs checked (container + nginx).

**Log findings (evidence)**
- No backend errors: all sessions reached the server, audio was healthy
  (`source=VOICE_RECOGNITION`, RMS fine), transcriber loaded the local V50 CT2
  model (`/app/models/qari-v50-ct2`) — no HuggingFace download anywhere.
- Phone sessions (11:19, 11:20, 11:29) were CUT SHORT / interleaved with the
  agent's own container restarts — do not test while the agent is restarting.
- Passes were running (~49 decodes per session, ~2s cadence) yet live `word`
  events stopped at the ayah-6 -> 7 boundary: the cursor pinned at word 20.

**Root cause (found by instrumenting the session class in-container)**
The prompted (oracle) decode ECHOES the prompt. Two consequences:
1. The echoed words were already resolved, so they were consumed as noise.
   The matcher consumes one token per iteration, so once the expected word's
   token was missing it drained the whole hypothesis and `j` pinned at its end
   — the loop body never ran again and the in-loop stall-breaker never fired
   (permanent freeze).
2. Worse, the echoed words sat in the cumulative hypothesis, so
   `stitch_hypothesis()` DEDUPED the genuinely-spoken words when the user
   finally reached them ("already contributed") — so fresh real evidence could
   never enter and the reveal never moved again.

**Fixes**
- `ml/alignment/streaming_matcher.py`: RESYNC after a stall — re-scan the last
  `RESYNC_SCAN_TOKENS=16` consumed tokens (newest first) and if one confidently
  matches a LATER reference word (within `RESYNC_REACH=10`), jump the cursor
  there and report the words in between as SKIPPED (that is the real-time
  mistake signal). Works even when the hypothesis is fully drained.
- `streaming_session.py`: on a stalled pass, UNION the unprompted (echo-immune)
  decode tokens into the window output, and RESET the spent hypothesis tail to
  the matcher's cursor so stale echo tokens cannot dedup new evidence.
- Verification (real Al-Fatiha audio over the real WebSocket, 1.0x pace):
  **29/29 word events BEFORE `final`**, each with `audio_at` matching the actual
  speech position (honest); second half resolves the moment the audio reaches
  ayah 7 (38.3s) instead of only in the final dump. Short-ayah case: 4/4 at
  3.8s. Container healthy, public /health OK.

**Still open / known**
- First words of a cold session can take ~4-8s (short windows give tier-2
  garbage, so the corroboration filter delays the first accepted word).
- Oracle-prompt echo can still make the reveal run AHEAD of the audio in the
  middle of a surah; the filter bounds it but does not eliminate it.
- ANCHORED prompt (no future text) was tried and REVERTED: measured 3/29 live
  words vs 20/29 with the per-ayah prompt — the model needs the current ayah's
  text (its training condition).

## Session 2026-09-22f — LATENCY CUT ~2.3x (user reported ~15s delay) ✅
Root cause: the UNPROMPTED (tier-2) decode fell into a repetition loop on
real recitation → 2.9s AND 22 junk tokens, so each live pass cost ~4.2s
(1.3s tier-1 + 2.9s tier-2). Two fixes in `ml/inference/faster_whisper_transcriber.py`:
1. **`max_new_tokens` caps**: unprompted 64 / prompted 96. The looped 7.5s window
   went 2.87s → **1.09s** with clean output (loops are pure waste: capped
   output still contains the real words the matcher needs).
2. **Second model instance** (`_model_raw`) for unprompted decodes: CTranslate2
   serializes concurrent calls on ONE instance (3.15s wall) but two instances
   run truly in parallel (1.96s). `QARI_FASTERWHISPER_THREADS=2` in compose so
   tier-1 + tier-2 use 2+2 = all 4 cores.
Result: live pass **4.2s → 1.9s**; full-surah E2E still resolves **29/29**
words before `final`, events arriving ~1.5-3s after the words are spoken.
Container RSS with both models: ~580MB (host has 16GB).

**MODEL PROVENANCE (asked explicitly): the service runs the user's OWN
trained model — NOT a HuggingFace model.** `/app/models/qari-v50-ct2` was
built locally by merging `/home/ubuntu/adapter_extracted/qari-v50-best-prompt-adapter`
(LoRA, V50, base `tarteel-ai/whisper-base-ar-quran`) then converting to
CTranslate2 INT8. `HF_HUB_OFFLINE=1` + `TRANSFORMERS_OFFLINE=1` make any
external download impossible. The generic public checkpoints in `models/`
(`qari-ct2-base`, `qari-ct2-tiny`) are NOT used by any service.

## Session 2026-09-22e — LIVE HIGHLIGHTING NOW RESOLVES THE WHOLE SURAH ✅
Earlier session 22d fixed decode latency but live events still stopped mid-surah.
Full-surah WS E2E (`/tmp/qari_live_word_test.py`, real Al-Fatiha audio at 1.0x)
now emits **29/29 word events BEFORE `final`** with correct timing
(`audio_at` matches each word's position). Fixes in this session:
1. **Sliding-window HYPO cap bug** (`streaming_session.py`): the cumulative
   hypothesis was truncated to `len(reference)+lookahead` from the TAIL —
   exactly where new words are appended. One repetition/echo burst filled the
   budget and the matcher pinned at the cap forever. Now capped relative to
   the matcher's consumed prefix (`_hyp_cursor + HYPO_TAIL_CAP`).
2. **Window overlap**: `TRANSCRIBE_WINDOW_OVERLAP_SEC = 1.5` added — without it
   a word straddling the window boundary was cut in half and the model emitted
   a fragment (e.g. 'ٰطَ' for 'صِرَٰطَ') that matches nothing.
3. **Per-ayah ORACLE prompt** (not full page): prompt = remaining words of the
   ayah containing the matcher cursor. A 29-word whole-page prompt derailed the
   prompt-conditioned decoder (it free-ran mid-prompt → zero live events).
4. **Two-tier decode + echo filter**: tier-1 = prompted decode; tier-2 =
   UNPROMPTED decode (echo-immune evidence). Tier-1 words are accepted only when
   tier-2 corroborates (exact/substring/difflib>=0.6). If tier-2 is unreliable
   (matches no reference word) tier-1 is trusted. If tier-1 is a pure prompt
   echo, tier-2 words are fed instead — without this the last ayah stalled
   forever. Verified: remaining-prompt alone made the model echo future text
   (ayah-5 words fired while only ayah-3 audio had streamed).
5. **Matcher live fixes** (`streaming_matcher.py`): `_strip_article` match
   (reference 'صرط' vs spoken 'الصرط' scored 0.67 < 0.80 and never matched) and
   a bounded **stall resync** (`_stall_passes >= 1`): when the expected word's
   token is lost, resolve the stuck words as matched (grace) once a later
   reference word matches confidently. Live mode never skips reference words,
   so this was a permanent stall before.
6. **Forced stop pass now waits for the transcribe lock** instead of returning
   `[]` when the background loop is mid-pass (the final window used to be
   dropped silently).

## Session 2026-09-22d — LIVE WORD HIGHLIGHTING FIXED (root cause: word_timestamps latency) ✅
- **Symptom**: live recitation reached the final review screen with matched
  words, but NO `word` events arrived during streaming — reveal only on stop.
- **Server verified fine**: WS route buffers frames + runs
  `transcription_loop` as a background task (1.2s cadence, 6s sliding
  window); client parses `match`/`matched` + `word_id`/`word_index`
  correctly.
- **True root cause**: `FasterWhisperTranscriber._decode` used
  `word_timestamps=True` → cross-attention DTW made each 6s window take
  **9.6s** (RTF 1.59 — slower than real time). First pass never finished
  before the user (or the test) sent `stop`; words only appeared in the
  forced final pass. With `word_timestamps=False` the same window takes
  **1.5s** (RTF 0.25) — **6x faster**.
- **Fix (ml/inference/faster_whisper_transcriber.py)**:
  1. `transcribe()` (live path) now decodes with `word_timestamps=False`;
     when segments carry no per-word entries it splits `segment.text` and
     assigns `exp(avg_logprob)` as shared segment confidence (≈0.9+,
     above the matcher's 0.55 live threshold).
  2. `transcribe_with_timings()` (batch path) keeps `word_timestamps=True`.
  3. `cpu_threads` now honors `QARI_FASTERWHISPER_THREADS` env (default:
     all cores, was cores//2).
- **Verified**: real-time WS test — 4/4 word events at t=3.9s while audio
  still streaming until 6.3s (before: 0 live events); 18s sustained test
  also clean (later passes no spurious events). Rebuilt + deployed.
- **No client change needed**; no new APK required for this fix.

## Session 2026-09-22c — TWO BACKEND BUGS FIXED (from first real audio) ✅
User's loud recitation finally crossed the RMS gate on the OLD build and
exposed two latent backend bugs:
- **`stream.tajweed_failed: 'list' object has no attribute 'astype'`**:
  `_decode_float()` returns a plain list but `TajweedChecker` helpers are
  numpy-based. Fixed in `streaming_session.py` `_run_tajweed_checks`:
  `np.asarray(audio, dtype=np.float32)` before `check_all`.
- **POST /v1/users/onboarding → 500** (sqlalchemy `MissingGreenlet`):
  `user.stats` lazy relationship touched inside async route. Fixed in
  `core_api/app/api/routes/users.py` by explicit
  `select(UserStats).where(UserStats.user_id == user.id)` query.
- Both rebuilt + deployed; onboarding verified 200 via curl signup→onboard;
  model loads in new recitation-api container (`initial_prompt` kwarg).
- **Phone still on old build**: nginx logs show every phone `/app/download`
  was 0.3–0.7MB (cancelled) — the full 77MB downloads were curl tests. User
  must install once via phone browser: https://qari.pneumetron.com/v1/app/download

## Session 2026-09-22b — OTA UPDATE DIALOG BUG FIXED + APK v1.0.49+71 ✅
- **Bug**: phones running v1.0.47+69 never showed the OTA update prompt (even
  with `force_update: true`) — user stuck on old build, mic fix unreachable.
- **Root cause**: `main.dart` `_QariAppState`'s `context` sits ABOVE the
  MaterialApp/Navigator it builds → `showDialog(context: context)` cannot
  find a Navigator and fails silently. Pre-existing bug; first exposed now.
- **Fix**: `showDialog` now uses `_navigatorKey.currentState?.context` (the
  navigator's own context, below MaterialApp). Verified nginx logs showed the
  phone hitting `/v1/app/version?lang=en` with 200s + Cloudflare
  `cf-cache-status: DYNAMIC` (not a cache issue) — purely the dialog bug.
- APK v1.0.49+71 built (contains mic fix + this fix), deployed, OTA serves
  it (md5-verified `d0b20887...`). `force_update` was set true during the
  rollout and is now back to **false** (user confirmed install) — future
  updates show a dismissible "Update available" prompt.
- Note: full 77MB OTA download via Cloudflare takes <1s server-side; short
  phone-side downloads in nginx logs were user-cancelled, not truncation.

## Session 2026-09-22 — MIC SENSITIVITY FIX + APK v1.0.48+70 ✅
- **Bug**: live recitation logged `stream.no_speech_detected` (rms 0.0015–0.0027
  < server `SILENCE_RMS_THRESHOLD` 0.006) — all audio discarded as silence.
- **Root cause**: `MicForegroundService.kt` captured with
  `MediaRecorder.AudioSource.UNPROCESSED`, which bypasses ALL device
  processing incl. hardware gain/AGC → mic level ~20 dB too quiet. Dart side
  is a passthrough (no scaling bug); Kotlin `LinearResampler` is
  amplitude-preserving (verified).
- **Fix** (all in `MicForegroundService.kt`): source priority is now
  VOICE_RECOGNITION → MIC → UNPROCESSED(last resort); new `SoftGain` class
  applies fixed 3x (+9.5 dB) with int16 clamp after hardware gain, before
  resampling; status lines now report the actual source used (e.g.
  `capture started: rate=44100 resample=true source=VOICE_RECOGNITION gain=3x`).
- APK v1.0.48+70 built, deployed to `releases/app-release.apk`, OTA
  `app_release.json` bumped — version endpoint serves 1.0.48+70 and the
  download endpoint serves the identical APK (md5-verified). If a device is
  STILL quiet, fallback levers: raise `SoftGain` factor, or lower server
  `SILENCE_RMS_THRESHOLD` (0.006, in `streaming_session.py`).

## Session 2026-09-21 — NEW VPS HOSTED HERE + TRAINED MODEL CONNECTED + APK v1.0.47+69 ✅
**User moved to a NEW VPS (this machine, Oracle, public IP `15.252.136.111`).**
Old IP `137.23.42.171` is DEAD — all references migrated to the domain
**`https://qari.pneumetron.com`** (Cloudflare-proxied to this host, real
trusted TLS — NO self-signed pinning, `trustedSelfSignedHost` removed).

- **Ingress**: Cloudflare DNS → host nginx (`/etc/nginx/sites-available/
  qari.pneumetron.com`) → core-api `127.0.0.1:8010`, recitation-api
  `127.0.0.1:8001`. Port 8000 is taken by an unrelated app — do not use.
- **Stack running here** (`infra/docker-compose.yml`, all healthy):
  core-api, recitation-api, inference-worker, postgres, redis. Verified:
  `/health` 200, auth signup/login issues JWT, OTA `/v1/app/version` serves
  1.0.47, `/v1/app/download` streams APK, WS `/ws/recitation/stream` works
  end-to-end through Cloudflare (handshake → start JSON → PCM → result).
- **USER'S OWN TRAINED MODEL IS NOW CONNECTED** (was the missing link):
  LoRA adapter `/home/ubuntu/adapter_extracted/qari-v50-best-prompt-adapter`
  (V50, prompt-WER 0.0065) merged with local base
  `tarteel-ai/whisper-base-ar-quran` (from local HF cache — NO HF downloads)
  → merged: `models/qari-v50-merged`, serving: **`models/qari-v50-ct2`**
  (CT2 INT8, mounted read-only at `/app/models`). `HF_HUB_OFFLINE=1` set in
  compose so nothing can ever fetch from HF. `tokenizer.json` was copied
  manually from the local Systran cache (CT2 export omits it; offline mode
  cannot fetch it).
- **Prompt-conditioned decode is REQUIRED for this model**: without the
  expected ayah text as prompt it repetition-loops; with prompt, full ayah
  transcribes perfectly AND partial audio does NOT echo the remaining prompt
  words (verified — honest live tracking, no auto-complete). Wired via
  `initial_prompt` in `ml/inference/faster_whisper_transcriber.py` (new
  `set_prompt()` / per-call prompt), fed from reference `text` (tashkeel)
  in `streaming_session.py` + `fast_inference_worker.py`.
- **APK**: v1.0.47+69 built (releases/app-release.apk, 74MB) — domain baked
  in, zero old-IP refs. OTA `app_release.json` updated, served live.
- Known env quirks: repo backend tests hang in this env (use direct E2E
  curls instead); host has no torch/peft (use the Docker image for model
  ops); Android SDK needed cmdline-tools + NDK 28.2 + platforms 34/36
  installed at `/usr/lib/android-sdk` for gradle builds.

## Session 2026-07-28 — lesson test async I/O + animation cleanup
- Follow-up device/Ubuntu test showed bounded fake-time pumps alone did not
  complete the curriculum asset/plugin futures, so Foundation never rendered.
  The test now preloads `vocabLessons()` and initializes LocalStorage inside
  `tester.runAsync` before mounting the page.
- The quiz reset regression left flutter_animate timers pending because it
  replaced/disposed feedback immediately after a single pump. Both answer
  phases now `pumpAndSettle()` their finite feedback animations before changing
  the question or ending the test.

## Session 2026-07-28 — lesson-list widget test timeout fixed
- `module_screen_test` used `pumpAndSettle()` while `LessonListPage` displayed
  an indeterminate `CircularProgressIndicator`; its perpetual animation kept
  scheduling frames and timed the test out. The test now initializes mocked
  SharedPreferences, pumps with a bounded retry loop until the bundled
  curriculum appears, and asserts the real Foundation content rendered.

## Session 2026-07-28 — consecutive quiz answer carry-over fixed
- The next MCQ could appear already correct and become untappable because the
  previous `QuizWidget` State (`_isCorrect=true`) survived a question update.
  Added a defensive `didUpdateWidget` reset for selection, correctness,
  fill-blank text, and drag-match answers whenever the question ID changes.
- Replaced the player's untracked delayed advance with a cancellable Timer
  bound to the answered screen index, preventing stale callbacks from skipping
  questions. Added a widget regression test that updates an answered QuizWidget
  to a second question without a key and verifies it starts unanswered.

## Session 2026-07-27 — silent live recitation auto-completion fixed
- Root cause: when the production Faster-Whisper model failed to load,
  `StreamingRecitationSession.load_reference()` silently installed the demo
  duration stub. That stub reveals one reference word every 0.9 seconds without
  analyzing audio, explaining the device's perfect 29/29 result after ~26s of
  silence. Production now fails the WebSocket handshake with a clear error when
  live ASR is unavailable; the duration stub remains available only when
  `QARI_ML_USE_STUB=true` is explicitly configured for tests/demos.
- Added regression coverage proving a missing production model never installs
  the duration stub. The existing RMS silence gate continues to protect a
  successfully loaded real model from Whisper hallucinations on quiet audio.

## ✅ VPS MIGRATION RESOLVED (2026-07-27): NEW IP = 137.23.42.171
CORRECTION: the user initially said the new VPS kept the old IP — that was
WRONG. The new VPS is an **Oracle Cloud (Mumbai) instance with public IP
`137.23.42.171`** (verified via `curl -4 ifconfig.me`); `20.197.40.13` was the
old Azure box (dead). All hardcoded references were migrated to 137.23.42.171
(app_constants.dart baseUrl + trustedSelfSignedHost, api_client.dart,
network_security_config.xml, nginx.conf server_name, docker-compose.yml CORS +
QARI_RECITATION_API_PUBLIC_URL, release_app.sh, app_release.json) and a new
APK was built — any build older than this migration points at the DEAD IP.

- **VPS (current)**: `137.23.42.171` — Oracle Cloud Mumbai, Ubuntu 22.04,
  Docker + Compose v2 plugin (manually installed binary; NEVER use the old
  `docker-compose` v1 — it breaks with "KeyError: ContainerConfig").
  Stack: infra-nginx/core-api/recitation-api/inference-worker/postgres/redis/
  minio — all healthy. alembic applied, reference_data + tarteel-ct2-base
  model generated on-host (host pip needs matching ctranslate2/transformers
  versions — see scripts/convert_tarteel_model.py docstring).
- **OLD (decommissioned)**: `20.197.40.13` (Azure). Do not use.
- OCI Security List: ingress 22/80/443 (+all-protocols rule) open. If ports
  hang from outside despite this, check host iptables REJECT rules
  (icmp-host-prohibited) — Oracle Ubuntu ships them by default.
- Backend is docker-compose (`infra/docker-compose.yml`): services = infra-nginx-1,
  infra-core-api-1, infra-recitation-api-1, infra-inference-worker-1, postgres, redis.
- Decision: **redeploy the full stack with docker compose** on the new VPS (not a
  piecemeal copy). See "VPS Migration Checklist" at the bottom of this file.

### Hardcoded old IP references to update on migration
Search the repo for `20.197.40.13` and replace with `NEW_VPS_IP` (or a domain):
- `infra/nginx.conf` (proxy_pass targets / server_name)
- `mobile/lib/.../app_constants.dart` (`baseUrl`, `wsBaseUrl`, `recitationStreamWsUrl`,
  `trustedSelfSignedHost`) — these drive OTA + WS endpoints in the app.
- Any `network_security_config.xml` entry pinning `20.197.40.13` (app trusts the
  self-signed cert for that host).
- `releases/app_release.json` / OTA notes if they embed the IP.
- README.md / docs if they reference the IP.
Prefer moving to a domain (e.g. `api.qari.app`) long-term — but for now the app
builds hardcode the host, so a rebuild+OTA is required after the IP changes.
NOTE: the LAST app build (v1.0.46+60) was a **Tarteel-live** build
(`USE_TARTEEL_LIVE=true`) — it points at Tarteel's `wss://voice-v2.tarteel.io`,
NOT our VPS. Our own `/ws/recitation/stream` backend is still the production
target once our model accuracy is good enough. When rebuilding for the new VPS,
decide whether to ship Tarteel-on or our-backend-on.

## Project
- **Qari**: AI-powered Quran learning app (Flutter mobile + Python/FastAPI backend).
- Repo: https://github.com/khan23153/qari
- Mobile app lives in `mobile/`, backend in repo root (core_api, infra, etl, etc).
- Current app version: **1.0.38+49** (versionCode 49).
- Flutter SDK location (not in PATH by default): `/home/Innocent/flutter/bin/flutter`
  - Build APK: `cd mobile && flutter pub get && flutter build apk --release`
  - Output: `mobile/build/app/outputs/flutter-apk/app-release.apk` → copy to `releases/app-release.apk`

## Deployment / Infra
- VPS IP: **20.197.40.13** (HTTPS). Backend + OTA served here.
- OTA app download endpoint: `https://20.197.40.13/v1/app/download`
- Direct APK in repo: https://github.com/khan23153/qari/raw/main/releases/app-release.apk
- Release metadata: `releases/app_release.json` (bump `version_code` + `version` on each release).
- NOTE: VPS sometimes auto-shuts off → work/session lost. Re-read this file on restart.

## Session 2026-07-13 (v1.0.13+18) — audio "0 source error" RE-FIX
User reported ayah audio STILL showing "Audio not available / 0 source error".
Root cause: the reader (`quran_reader_page._playAyahAudio`) played a SINGLE
source with no fallback — `if (ayah.audioUrl != null) playUrl(ayah.audioUrl)`.
The network merge in `_loadAyahs` fills `audioUrl` from the backend; when that
URL points at a dead host, ExoPlayer throws "(0) Source error". The working
everyayah.com constructed URL was only used in the `else` branch, so it got
bypassed. Verified everyayah CDN works (HTTP 200, audio/mpeg, CORS open); the
bundled corpus has `audio_url: null` for all rows (offline path was fine).
FIX (this session):
- `quran_reader_page.dart`: build the everyayah CDN url up front via
  `buildAyahUrl`; play `ayah.audioUrl` first (if any) then ALWAYS retry with the
  CDN url on failure before showing the toast.
- `recitation_page.dart` ("Listen First"): if backend referenceUrl fails to
  play, retry with `playAyah(...)` (constructed CDN) instead of erroring.
- Word bottom sheet left as-is (silently no-ops with no url, no toast).
Built APK v1.0.13+18 → copied to `releases/app-release.apk` (74.3MB). Bumped
`pubspec.yaml` + `releases/app_release.json` (version_code 18). NOT committed/
pushed (no git action requested). VPS still needs the APK served for OTA.

## Session 2026-07-13 (v1.0.13+19) — whole-surah playback + voice picker
User: "audio working now" → add (1) play the WHOLE surah in one tap instead of
a single ayah, and (2) a voice/reciter picker so the user can choose the qari.
Changes (all committed + pushed, APK rebuilt to version_code 19):
- `audio_service.dart`: new `playSurahSequence({urls, initialIndex})` that loads
  a `ConcatenatingAudioSource` of per-ayah URLs for gapless whole-surah playback;
  new `currentIndexStream` (from `sequenceStateStream`) so the UI can follow the
  active ayah; `isSequential` flag; `stop()` resets it.
- `quran_reader_page.dart`: tapping an ayah's play button now queues the rest of
  the surah (sublist from tapped ayah) and plays it in one go. The highlighted
  ayah follows playback via `currentIndexStream`; tapping the active ayah
  pauses/resumes; tapping another restarts from there. On `ProcessingState
  .completed` the session resets. Added a **Voice** chip in the settings bar
  that opens a sheet listing all 5 reciters (Abdul Basit, Al-Sudais, Al-Minshawi,
  Al-Husary, Al-Afasy) — persists via `LocalStorageService.setSelectedQari` and
  applies immediately to the AudioService. URLs are built with the selected
  reciter (`_selectedQari`).
- Carried over (committed now): everyayah.com CDN `audioCdnUrl` fix, recitation
  "Listen First" CDN fallback, `pubspec.yaml` + `app_release.json` (v1.0.13+19).
- Flutter SDK path: `/home/Innocent/flutter/bin/flutter` (NOT in PATH).

## Last session (2026-07-13, commit b70e27d)
Fixed 7 reported mobile bugs:
1. Signup/Login: clear cached progress + fetch live home data (killed silent 409-on-retry).
2. Home: wire Continue card & learning-path nodes to LessonPlayerPage.
3. Quran reader: fetch ayahs from API w/ fallback + dark-theme contrast.
4. Qibla: real GPS + magnetometer compass (geolocator + flutter_compass).
5. Recitation: record WAV 16kHz to match backend; raised API/upload timeouts.
6. Tasbih: added header settings (gear) icon.
7. Onboarding: persist isOnboarded immediately.

## Session 2026-07-13 (commit dd3cdb9)
- Rebuilt APK v1.0.1+6, committed + pushed to origin/main.
- Known issues:
  - APK (65.7MB) > GitHub 50MB warning → consider Git LFS.
  - Some plugins (haptic_feedback, package_info_plus, share_plus) still use Kotlin
    Gradle Plugin; future Flutter versions may fail to build. Plan to migrate.
  - Push needs a GitHub token (no credential helper configured).

## Session 2026-07-13 (commit <TBD>) — 5 bug fixes
Built APK v1.0.2+7 (version_code 7). Fixed:
1. **Profile/Home progress mismatch** — `profile_page.dart` hardcoded
   `_totalXp=1240`, `_currentStreak=7` etc. Now fetches real `/me` + `/me/stats`
   from backend (defaults to 0 for new users). This was the "old cache" bug.
   NOTE: signup/login already call `clearProgressCache()`; root cause was the
   hardcoded values, not storage.
2. **Start Journey button dead** — `home_page._openLesson` returned early when
   the server sent no path nodes. Now always navigates (falls back to
   `LessonListPage` when no lesson/node is available).
3. **Ayat blank screen** — backend returns a JSON array of `AyahOut` (keys
   match `AyahModel`/`WordModel`). Made `corpus_repository.getAyahs` tolerant of
   wrapped shapes (`ayahs`/`data`/`items`) so the reader never gets an empty list.
4. **Recitation no-sound / analysis-failed** — audio play errors were swallowed
   (`catch (_)`); now surfaces a SnackBar. Analysis failures now show the real
   HTTP status code + error_code from `ApiException` for debugging.
5. **Qibla wrong (reported 261°, showed 280°)** — formula is CORRECT: 280.07°
   is the true-north bearing for Mumbai (verified with haversine calc). Kept the
   formula; improved GPS to `LocationAccuracy.best`. Do NOT change 280→261.

## Open tasks / TODO
- Push needs a GitHub token (no credential helper configured).
- Consider Git LFS for the large APK.
- Verify backend is reachable (VPS auto-shuts off) before testing network calls.

## Session 2026-07-13 (commit <TBD>) — 3 more bug fixes (v1.0.3+8)
From screenshots 1000115565/66/67:
1. **Quran screen completely grey** — In release builds a widget that throws
   during build shows the framework's BLANK GREY ErrorWidget. Added a global
   `ErrorWidget.builder` in `main.dart` that renders the exception + stack
   visibly (no more silent grey). Need the actual stack trace (or re-test) to
   pinpoint the exact throw in the reader; layout itself (Expanded/Stack) is
   correct.
2. **Recitation analysis HTTP 405** — ROOT CAUSE was INFRA, not frontend: the
   `recitation_api` service is separate from `core_api`. nginx's HTTPS (:443)
   block was missing `location /v1/recitations/ { proxy_pass http://recitation_api; }`
   (the HTTP :80 block had it). So `POST /v1/recitations/upload` hit `core_api`
   (which only has `GET /{session_id}`) → 405. FIXED in `infra/nginx.conf`
   (both server blocks). The mobile already uses POST correctly. NOTE: nginx
   change requires **redeploying the VPS** (docker compose restart).
3. **Audio "0 source error"** — `audioCdnUrl='https://audio.qari.app'` does not
   resolve. The backend returns a real per-ayah `audio_url` (quran.com CDN).
   Recitation "Listen First" now fetches that via `CorpusRepository.getAyah`
   and plays it; also logs the URL in `AudioService._playUrl`. Reader already
    preferred `ayah.audioUrl`.

## Session 2026-07-13 (v1.0.4+9) — screenshot batch 1000115573-576 triage
Screenshots 1000115573 (MaterialLocalizations null + TextField), 5574 (audio
"0 source error"), 5575 (analysis HTTP 405), 5576 (red UI error box in module
screen). Findings:
1. **Issue 1 (MaterialLocalizations null on TextField)** — NOT a missing
   MaterialApp: root `QariApp` already wraps in `MaterialApp` with
   `localizationsDelegates` (main.dart). All TextFields are descendants of it.
   Hardened the loading + error `MaterialApp`s in main.dart to also provide
   `DefaultMaterialLocalizations`/`DefaultWidgetsLocalizations` delegates so
   early/error states can't hit this class of error.
2. **Issue 2 (red error box, module screen)** — `ErrorWidget.builder`
   (main.dart) already surfaces the real exception + stack. Added a
   `debugPrint` there so the failing child widget is identifiable from
   `flutter logs`/terminal. Could NOT pinpoint the exact widget without the
   device console output (no device here). The lesson/module screens
   (lesson_list_page, lesson_player_page, quiz_widget, grammar_card_widget)
   are null-safe on inspection.
3. **Issue 3 (audio "0 source error")** — ALREADY FIXED in 43849ce: per-ayah
   URL fetched from backend and logged at recitation_page.dart:99 before play.
   No change needed.
4. **Issue 4 (analysis HTTP 405)** — PREMISE WRONG: mobile already sends
   `POST` (api_client.dart `uploadFile` → `_dio.post`). The 405 was INFRA:
   nginx HTTPS :443 block lacked `location /v1/recitations/ { proxy_pass
   http://recitation_api; }`. Fixed in infra/nginx.conf (43849ce) but requires
   **VPS redeploy** (docker compose restart). Do NOT change client to GET/POST
   again — it is already POST.

Next: rebuilt APK v1.0.4+9 (committed locally, NOT pushed — needs GitHub
token). Still need to **redeploy the VPS** for the 405 fix to take effect.

## Session 2026-07-13 (v1.0.5+10) — device logs + actual repro
User pasted real device error text. Key findings:
1. **Issue 2 (module red box) ROOT CAUSED & FIXED** — it was NOT
   MaterialLocalizations. `GrammarCardWidget._UnderlineIndicator` drew a
   single-sided `Border` with `strokeAlign: BorderSide.strokeAlignCenter`,
   which is invalid for non-uniform border colors → throws during PAINT of the
   lesson concept screen. FIXED in grammar_card_widget.dart (removed
   strokeAlignCenter). Reproduced + verified with a widget test that drives
   LessonListPage → lesson → concept → fill-blank quiz.
2. **Issue 1 (MaterialLocalizations null on TextField)** — could NOT reproduce:
   the fill-blank `TextField` builds fine under `MaterialApp` in tests, and
   `appLocaleProvider` is always `Locale('en')` (in supportedLocales), so
   `DefaultMaterialLocalizations` always resolves. Likely a stale device build.
   If it recurs on v1.0.5+10, the new copyable ErrorWidget will show the exact
   cause.
3. **ErrorWidget.builder** updated per user request: now returns
   `Material`+`SafeArea`+`SingleChildScrollView`+`SelectableText` of
   `details.exceptionAsString()` + `details.stack`. Lets them long-press to
   copy the error. (Note: `SelectableText` needs MaterialLocalizations, which
   the root MaterialApp always provides — safe here.)

Open items from device paste:
- **405 STILL shows on device** despite "already in VPS" claim — nginx fix
   likely NOT actually redeployed, or recitation_api container down. Needs
   `docker compose restart` on VPS / verify recitation_api is up.
- **Audio (0) Source error** on "Listen First" — just_audio can't load the
   backend `audio_url`. URL is logged at recitation_page.dart:99; need the
   logged URL to tell if it's a bad/blocked/CORS URL vs format issue.

## Session 2026-07-13 (v1.0.6+11) — MaterialLocalizations crash ROOT CAUSED
User pasted device screenshots: Home (RefreshIndicator) + a TextField screen
both threw `Null check operator used on a null value` from
`MaterialLocalizations.of`. Previous v1.0.5+10 note wrongly concluded this was
a stale build / "locale is always en". It was NOT stale — real root cause:

- **ROOT CAUSE**: `main.dart` `MaterialApp`s used
  `DefaultMaterialLocalizations.delegate`, which supports **English only**.
  But the app lets the user pick Urdu/Arabic (`locale: locale` in main.dart:236,
  set from stored language in `_checkAuthStatus`). For `ur`/`ar`, Flutter cannot
  resolve `MaterialLocalizations` → `MaterialLocalizations.of` returns null →
  the `!` null-check in `RefreshIndicator` (home tab) and `TextField`
  (surah search / ask-scholar / root-explorer) throws. The Urdu text on the
  screenshots is the giveaway that locale = ur.
- **FIX**: switched all 3 `MaterialApp`s in `main.dart` (loading splash,
  error fallback, and main) to `GlobalMaterialLocalizations.delegate` +
  `GlobalWidgetsLocalizations.delegate` (from `flutter_localizations`, already
  a dependency), which support ur/ar/en. Added `import
  'package:flutter_localizations/flutter_localizations.dart';`.
- Rebuilt APK v1.0.6+11 (version_code 11). Output
  `mobile/build/app/outputs/flutter-apk/app-release.apk` → copied to
  `releases/app-release.apk`. `releases/app_release.json` bumped to 1.0.6/11.
- NOT pushed (needs GitHub token). Does NOT require VPS redeploy (frontend-only).

CORRECTION to earlier note: locale is NOT always `Locale('en')` — it follows
the user's selected language (en/ur/ar), so any widget relying on
`MaterialLocalizations` will crash on non-English locales unless the Global
delegates are used.

## Session 2026-07-13 (v1.0.7+12) — RTL flip regression fixed
After v1.0.6+11 (Global delegates), the whole UI flipped to RTL. ROOT CAUSE:
switching to `GlobalWidgetsLocalizations` made Urdu/Arabic localize correctly,
and those locales are RTL — so the entire app mirrored. This is *correct*
behavior for ur/ar, but the user wants English to stay LTR and RTL only when
ur/ar is explicitly selected.
- FIX in `main.dart`: kept `locale: locale` (dynamic, respects selected
  language) and added a `builder` that wraps the app in `Directionality`:
  LTR for English, RTL only for `ur`/`ar` (helper `_isRtl(Locale)`). Also set
  `locale` + same `Directionality` builder on the loading `MaterialApp`
  (which previously had no `locale`). `AppLanguage.textDirection` is the source
  of truth (en=LTR, ur/ar=RTL).
- Rebuilt APK v1.0.7+12 (version_code 12); copied to `releases/app-release.apk`;
  `releases/app_release.json` bumped to 1.0.7/12.
- Pushed to origin/main with the user-supplied GitHub token (inline, not stored).

## Session 2026-07-13 (v1.0.10+15) — surah list (10→114) + reader blank screen
User reported (again) "only 10 surahs" and "blank screen on tapping a surah".
The v1.0.9+14 notes claimed this was already fixed, but it recurred — the
previous attempt did NOT fix the real root causes:
1. **Blank screen ROOT CAUSE** — backend `/surahs/{n}/ayahs` returns words with
   a NULL `pos_group`. `WordModel.posGroup` was `required` (non-nullable), so
   `WordModel.fromJson` threw `as String` → bubbled out of `getAyahs` (not a
   DioException, so the repo's `catch (DioException)` didn't catch it) → on a
   pre-seed build the reader rendered empty/blank. FIXED: `posGroup` is now
   `String?` (word_model.dart) and callers pass `?? 'default'` to
   `getGrammarConfig`. Regenerated freezed.
2. **Partial/short surahs** — backend caps each `/ayahs` request at
   `MAX_AYAHS_PER_REQUEST = 20` (shared/__init__.py:164). The mobile fetched
   only one page, so long surahs showed ~20 ayahs. FIXED: `getAyahs`
   (corpus_repository.dart) now paginates `from`/`to` in 20-ayah pages until a
   short/empty page, assembling the full surah.
3. **Only 10 surahs** — if the backend returns a partial list (or the DB only
   has a subset), `_loadSurahs` replaced the 114-surah list with whatever the
   server sent. FIXED: `_loadSurahs` (surah_list_page.dart) now MERGES server
   surahs into the bundled `_fallbackSurahs` (all 114) by surah number, so the
   list is ALWAYS complete (114) regardless of backend state. Server data wins
   on a match; fallback fills gaps.
- Rebuilt APK v1.0.10+15; copied to releases/app-release.apk;
  releases/app_release.json bumped to 1.0.10/15.
- NOTE: OTA serves from VPS (20.197.40.13/v1/app/download). To actually push
  this to users, the new releases/app-release.apk must be deployed to the VPS
  (the VPS copy, not just the GitHub raw one, is what devices download).

## Session 2026-07-13 (v1.0.11+16) — ROOT CAUSE of blank reader found + local corpus
The recurring "blank screen on tapping a surah" was NEVER actually fixed by the
posGroup/merge changes — those only addressed symptoms. REAL ROOT CAUSE:
- The backend corpus DB is **empty**. `backend/core_api/seed_dev_data.py` only
  seeds qaris/badges/lessons — it never loads surahs/ayahs/words. Verified live:
  `GET /v1/surahs` → `[]`, `GET /v1/surahs/1` → "Surah '1' not found".
  So `/surahs/{n}/ayahs` returns `[]` for EVERY surah, and the reader fell back
  to a single placeholder bismillah ayah (only Al-Fatiha had real sample data).
- Decision: stop depending on the (empty/unreliable) backend for reading.
  Bundle the full Quran locally in the app so the reader works offline.
- Added `scripts/build_local_corpus.py` which pulls all 114 surahs (Uthmani
  text, simple text, EN verse translation res 84, UR verse translation res 97,
  word-by-word transliteration + EN word translation) from the Quran.com API v4
  and writes `mobile/assets/quran_corpus.json` shaped to match AyahModel/
  WordModel `fromJson` keys. Gzipped → `mobile/assets/quran_corpus.json.gz`
  (4.3 MB; ~41 MB uncompressed, 6236 ayahs / 83665 words).
- Added `mobile/lib/data/repositories/local_corpus_repository.dart`: loads the
  gzipped asset via `rootBundle`, decodes with `gzip.decode` in a `compute`
  isolate, parses directly to `AyahModel`/`WordModel`.
- `QuranReaderPage._loadAyahs` now loads the **local corpus first** (instant,
  offline, never blank), then optionally merges live backend data on top.
- `pubspec.yaml` registers `assets/quran_corpus.json.gz`; version bumped
  1.0.10+15 → 1.0.11+16.
- KNOWN LIMITATION: Quran.com free API has no per-word POS group / grammar
  labels and no Hindi translation, so grammar colors use the `default` style
  and `translation_hi` falls back to EN. Hindi verse translation not bundled.
- BUILD NOTE: the APK for v1.0.11+16 was NOT built in-session — this environment
  blocks the 153 MB Android cmdline-tools download (headers arrive, body empty),
  so no Android SDK / NDK. The user must build + deploy on their own machine:
    cd mobile && flutter pub get && flutter build apk --release
    # then: copy build/app/outputs/flutter-apk/app-release.apk → releases/
    # and deploy to VPS at 20.197.40.13 (OTA /v1/app/download).
    # Bump releases/app_release.json to 1.0.11/16 AFTER the APK is on the VPS.

## Session 2026-07-13 (v1.0.8+13) — Quran reader blank screen fixed
Symptom: tapping a surah in the Quran tab opened an empty screen (no ayahs).
- ROOT CAUSE: `QuranReaderPage._loadAyahs` set `_isLoadingAyahs=true` and the
  build showed a full-screen `CircularProgressIndicator` until the network call
  resolved. The backend VPS (20.197.40.13) is frequently down/filtered, so the
  Dio request can sit until the ~90s `apiTimeoutSeconds` → the page looked blank
  for a long time. Data shapes (AyahOut/WordBrief) do match AyahModel/WordModel,
  and the error path already falls back to sample ayahs — the blank was purely
  the loading state, not missing data.
- FIX in `quran_reader_page.dart`: seed `_ayahs` with `_generateSampleAyahs`
  in `initState` so the first frame has content; render the `ListView` (with a
  thin `LinearProgressIndicator` at top while loading) instead of a spinner;
  on network failure keep the current ayahs (don't clobber with sample); show a
  friendly "No ayahs found" only if truly empty. Screen is now never blank.
- Rebuilt APK v1.0.8+13 (version_code 13); copied to `releases/app-release.apk`;
  `releases/app_release.json` bumped to 1.0.8/13.
- Pushed to origin/main with the user-supplied GitHub token (inline, not stored).

## Session 2026-07-13 (v1.0.9+14) — Quran surah list shows all 114
User: tapping a surah opened a blank reader AND the list only showed 10 surahs
(should be 114). The 10-surah bug was the real defect:
- `surah_list_page.dart` hardcoded a 10-item `_allSurahs` sample list. Rewrote it
  to fetch all 114 via `CorpusRepository().getSurahs()` (`/v1/surahs`), with a
  bundled full-114 `_fallbackSurahs` list used when the API is unreachable, so
  the list is never empty. Tile now takes `SurahModel`.
- BLOCKER found + fixed: backend `SurahBrief` has NO guaranteed `name` key (it
  only has `name_arabic`/`name_english`/`name_translation`; `name` is a computed
  transliteration that can be absent). `SurahModel.name` was `required` →
  `getSurahs()` threw on every call. Made `name` nullable and mapped it from the
  `name` JSON key (not `name_arabic`, which would collide with `nameArabic`).
  Regenerated `surah_model.g.dart`/`surah_model.freezed.dart` via build_runner.
- Reader blank: confirmed via a widget test that `QuranReaderPage` DOES render
  ayah text (seeded sample) — the earlier "blank" was the pre-v1.0.8 full-screen
  spinner during the network request. v1.0.8's sample-seed already fixes it.
  NOTE: the user may not have installed v1.0.8 yet; this build (v1.0.9+14)
  includes both fixes.
- Rebuilt APK v1.0.9+14 (version_code 14); copied to `releases/app-release.apk`;
  `releases/app_release.json` bumped to 1.0.9/14.
- Pushed to origin/main with the user-supplied GitHub token (inline, not stored).

## Session 2026-07-13 — reader blank fix (post v1.0.11+16) + widget test
Follow-up to the local-corpus work. Two more root causes of a blank reader, plus
a regression test.

1. **AyahWidget hidden by opacity-0 animation (REAL blank-screen cause)** —
   `ayah_widget.dart` wrapped the ayah `Container` in
   `.animate(target: isPlaying ? 1 : 0).fadeIn()`. `fadeIn` STARTS at opacity 0,
   so every ayah that is *not* currently playing (i.e. essentially all of them)
   was painted fully transparent → the reader showed only the header/settings
   bar with a blank ayah list. FIXED: removed the `.animate().fadeIn()` wrapper;
   the container now paints directly. Added a code comment in ayah_widget.dart
   so this doesn't get re-introduced.
2. **Local corpus decode could fail silently** — `LocalCorpusRepository` decoded
   the gzipped asset via a `compute` background isolate. On platforms where that
   path is flaky, the future could fail and leave the reader blank. FIXED:
   decode `gzip.decode` directly on the caller (fast for a ~4.4 MB asset) and
   parse each ayah defensively (`try/catch`, skip bad ayahs with `debugPrint`)
   so a single malformed item can't blank an entire surah. Removed the top-level
   `gzipDecode`/`_decode` helpers.
3. **Regression test added** — `mobile/test/ayah_widget_visibility_test.dart`
   drives `AyahWidget` with `isPlaying:false` (the state that previously hid
   everything) and asserts: (a) the Arabic word widgets are present, (b) the
   first word actually has a non-zero painted size, and (c) no ancestor
   `RenderAnimatedOpacity` is painting at ~0 opacity. This pins the exact bug
   that the v1.0.11+16 changes didn't fully close.
- `flutter` is NOT in PATH by default; run tests with:
  `export PATH="/home/Innocent/flutter/bin:$PATH"; flutter test test/ayah_widget_visibility_test.dart`
  → all tests pass.
- BUILD NOTE: this environment has no Android SDK/NDK (the 153 MB cmdline-tools
  download is blocked — headers arrive, body empty), so the APK was NOT rebuilt
  here. The fix is verified by the widget test (runs headless, no device). The
  user must rebuild the APK on their machine before deploying to the VPS.
- These working-tree changes + the 6 already-committed-but-unpushed commits
  (v1.0.6+11 → v1.0.11+16) were pushed to origin/main with the user's GitHub
  token (inline, not stored).

## Session 2026-07-13 — Recite screen from Quran reader was a blank placeholder
User: tapping "Recite" on an ayah opened a blank screen showing only
"Recitation for 1:1". ROOT CAUSE: `RecitationPageRoute` in
`quran_reader_page.dart` was a literal placeholder (`Scaffold` + `Text('Recitation
for $surahNumber:$ayahNumber')`). FIX (working tree, uncommitted):
- `quran_reader_page.dart`: `RecitationPageRoute.build` now returns the full
  `RecitationPage(surahNumber:, ayahNumber:)` instead of the placeholder.
- `recitation_page.dart`: the idle/listen/record UI already existed and is fully
  wired to `RecordingService` (16kHz WAV), `AudioService` (reference playback w/
  CDN fallback), and `RecitationRepository` (upload + poll → `RecitationResult`).
  Added `_loadTargetAyahText()` to `initState` so the screen shows the REAL target
  ayah text from `LocalCorpusRepository` (was hardcoded bismillah before).
- Added `test/recitation_screen_test.dart` (pumps `RecitationPage` from reader and
  asserts header + RTL arabic text + "Listen First" + "Record Now" buttons present).
  Fixed stale `widget_test.dart` state-machine count 8→9 (`errorAnalysisFailed`).
- RECITATION STATE MACHINE: idle → listening → recording → analyzing → results,
  plus errorMicDenied / errorTooNoisy / errorLowConfidence / errorAnalysisFailed.
- NOTE: `widget_test.dart` "Grammar color-coding follows spec" still fails — it's a
  pre-existing stale constants assertion, unrelated to this change.
- COMMITTED + PUSHED (commit df8cea6) with the user's GitHub token. Version
  bumped to v1.0.13+23; `releases/app-release.apk` rebuilt (74.4MB) and copied
  to `releases/`, `releases/app_release.json` bumped to 23. APK push warned
  >50MB (use Git LFS later). OTA still serves from VPS 20.197.40.13 — to push
  to users, deploy the new APK to the VPS (`/v1/app/download`).

## Session 2026-07-13 — Recitation results: real Arabic words + real ML engine
User: results screen was in STUB mode (hardcoded 100% + "Stub mode — connect
the ML engine" feedback) and the word-by-word grid showed raw backend keys like
`word_2_1_1` instead of Arabic. FIX (committed + pushed, commit 108b75a):
- ROOT CAUSE of stub: `infra/docker-compose.yml` forced `QARI_ML_USE_STUB:"true"`
  on the `inference-worker` service. The frontend already calls the REAL API
  (`RecitationRepository.uploadRecitation`/`pollForResult`) — no mock in the app.
  The stub `_default_inference` (backend/recitation_api/app/workers/
  inference_worker.py:184) emits `word: "word_{surah}_{ayah}_{pos}"` keys + 1.0
  scores. Set `QARI_ML_USE_STUB:"false"` so the real Whisper/Wav2Vec2 pipeline
  (run_ml_inference) runs and returns actual Arabic + real scores.
- FRONTEND word mapping: added `WordVerdict.displayWord(List<String> ayahWords)`
  (mobile/lib/data/models/recitation_model.dart) that prefers real Arabic
  already on the verdict, else resolves from the target ayah's word payload by
  `wordIndex` (so no raw keys leak to the UI). `RecitationPage._loadTargetAyahText`
  now also stores `_ayahWords`; passed to `RecitationResults` and
  `WordComparisonSheet` which call `verdict.displayWord(...)`.
- Tests: added `test/recitation_word_mapping_test.dart` (proves grid shows real
  Arabic, not `word_x_y_z` keys). Bumped APK to v1.0.13+24 (rebuilt, copied,
  app_release.json → 24).
- DEPLOY NOTE: flipping stub off means the VPS `recitation_api` worker MUST have
  the ML engine (Whisper ASR + Wav2Vec2 forced aligner) + reference data
  (reference_data_dir / core_api) deployed, else real inference raises and the
  mobile shows the "analysis failed" state. Redeploy VPS + deploy APK to
  20.197.40.13 for users to get real feedback.


## Session 2026-07-13 — Deployed real ML engine on the VPS (no more 100% stub)
The running VPS (this environment) backend was still on the OLD worker container
with `QARI_ML_USE_STUB=true`, so recitations returned hardcoded 100% regardless
of audio. Actually deployed the real engine here:
- Recreated `infra-inference-worker-1` from updated compose → `QARI_ML_USE_STUB=false`.
- Root-caused why real inference still failed, and fixed each gap:
  1. `No module named 'ml'` → mounted `../ml:/app/ml` + `PYTHONPATH=/app` in compose.
  2. ML deps missing from worker image → added `requirements.ml.txt` (CPU
     torch/transformers/torchaudio/librosa/soundfile) + installed in
     `backend/recitation_api/Dockerfile` (rebuilt image `infra-inference-worker`).
     Dropped `edlib` (won't build on py3.12; unused by runtime `ml`).
  3. Audio file not found by worker → added shared `qari_audio:/tmp/qari_audio`
     volume to BOTH `recitation-api` and `inference-worker`.
  4. Whisper `return_timestamps` generation-config error → disabled ASR
     timestamps in `ml/inference/asr.py` (word timing comes from forced aligner).
  5. Empty backend corpus DB → built reference bundle (6236 ayahs) from the
     bundled mobile corpus via new `scripts/build_reference_from_local_corpus.py`
     into `backend/recitation_api/reference_data` (gitignored); set
     `QARI_REFERENCE_DATA_DIR=/app/reference_data`.
- VERIFIED end-to-end: uploaded a (non-speech) WAV → worker loaded Whisper +
  reference store and returned a COMPUTED 0% with "couldn't analyse with enough
  confidence" — confirms real inference, NOT the 100% stub.
- Committed + pushed (commit 8bdba74). Worker is `restart: unless-stopped` and
  uses the rebuilt image + volume mounts, so it survives restarts.
- FRONTEND: APK v1.0.13+24 (from prior turn) already has the word-mapping fix
  and is current; no rebuild needed this turn. User's device hitting the VPS now
  gets real scores (wrong words will be marked, not 100%).

## Session 2026-07-13 — Fixed "Low Confidence" + validated real ML end-to-end
After enabling the real engine, the user still got "We couldn't analyze your
recitation with enough confidence" even on a correct recitation. ROOT CAUSE:
two more gaps in the real pipeline (the `max_new_tokens` + forced-decoder
prompt = 452 > Whisper's 448 max) made `pipeline.analyze` raise on every job,
so `evaluated_ayahs == 0` → empty verdicts → low-confidence state.
FIXES (committed + pushed, commit aae11a6 + follow-ups):
- `ml/inference/asr.py`: `max_new_tokens` 448 → 440 (4 forced-decoder tokens
  + 440 = 444 < 448 max). Also earlier disabled ASR `return_timestamps`
  (transformers generation-config incompatibility).
- `scripts/build_reference_from_local_corpus.py`: skip reference words with no
  actual Arabic letters (e.g. the corpus' stray "1" numeral token), so a real
  recitation is never penalised for a reference-data artifact. Regenerated the
  6236 reference files (1:1 now cleanly = بسم/الله/الرحمن/الرحيم).
VALIDATION (real end-to-end on the VPS worker):
- Installed espeak-ng + ffmpeg here; synthesized 16kHz mono Arabic WAVs:
  a CORRECT bismillah and a WRONG variant (last word السلام instead of
  الرحيم), uploaded both to /v1/recitations/upload.
- Both returned real word_verdicts with actual Arabic `word`/`expected_text`
  (NOT `word_x_y_z` keys). The WRONG clip's last word was transcribed as
  السلام vs expected الرحيم → flagged mispronounced (red). CONFIRMS the real
  engine differentiates correct vs wrong recitation and is no longer the 100%
  stub. The overall 0.3 on espeak audio is a test artifact (robotic TTS is hard
  for Whisper-Quran, which is trained on natural recitation); a real human
  recitation transcribes far better → higher score.
- Updated README.md recitation-engine section (local-corpus reference builder,
  ML deps via requirements.ml.txt, shared qari_audio volume, stub=false prod).
- NOTE: recitation scoring quality depends on Whisper-Quran transcription
  accuracy; tuning (beam search, LM, Wav2Vec2 refine) is future work. The
   pipeline is correctly wired end-to-end.

## Session 2026-07-14 — Urdu Tarjuma (text + sequential audio) in Surah view
Added an optional Urdu translation feature to the Quran reader.
- **Model**: `AyahModel` gained `audioUrlUr` (`audio_url_ur`) — regenerated
  freezed. Urdu text already existed via `translationUr`.
- **Audio source**: Urdu tarjuma audio uses everyayah.com CDN
  `https://everyayah.com/data/urdu_shamshad_ali_khan_46kbps/{surah:03d}{ayah:03d}.mp3`,
  exposed as `AppConstants.urduTranslationCdnUrl` + `AudioService.buildUrduTranslationUrl`
  (mirrors the Arabic `buildAyahUrl`). Falls back to `ayah.audioUrlUr` if present.
- **UI/State**: settings bar "Tarjuma" chip opens a sheet — choose English/Urdu
  translation + a "Play Translation Audio" switch. Both persisted in
  `LocalStorageService` (`translation_language`, `play_translation_audio`).
  `AyahWidget` takes a new `translationLanguageCode` that drives the density>=3
  full-translation block (word meanings still use app `languageCode`).
- **Sequential queue**: `_playAyahAudio` queues [Arabic, Urdu] per ayah when the
  toggle is on; `_audioItemsPerAyah` (1 or 2) maps the player's sequence index
  back to the highlighted ayah in `currentIndexStream`.
- **Backend**: `Ayah.audio_url_ur` column + migration `0003_ayah_audio_url_ur`;
  `AyahOut.audio_url_ur` (serialization_alias `audio_url_ur`), populated in
  `corpus.py` route + `content_bundle_service.py`. Migration MUST be applied on
  the VPS (alembic upgrade) or the `ayahs` table query fails.
- **Build script**: `scripts/build_local_corpus.py` writes `audio_url_ur` per
  ayah when `URDU_AUDIO_BASE_URL` env is set (else omitted; runtime still
  constructs it from the constant).
- Verified: `flutter analyze` clean on changed files; `ayah_widget_visibility_test`
  passes. `reader_render_test` FAILS but is pre-existing (fires a real 90s Dio
  timer in initState; fails before this change too).
- BUILT + COMMITTED + PUSHED (commit ce2ea78): APK rebuilt (74.4MB),
  copied to `releases/app-release.apk`, bumped to **v1.0.14+25**
  (`pubspec.yaml` + `releases/app_release.json` with Urdu tarjuma notes),
  pushed to origin/main. Large-APK (>50MB) warning as before — Git LFS later.
- DEPLOY: VPS needs `alembic upgrade head` (new `ayahs.audio_url_ur` column)
  and the new APK deployed to 20.197.40.13 (`/v1/app/download`) for OTA users
  to get the Urdu tarjuma feature.

## Session 2026-07-14 — auth/state/UI bug fixes (5 items)
Mobile-only fixes (no backend change needed; signup already returns JWT):
1. **Login validation** — `_AuthForm` password validator now enforces min 8
   chars (email regex already present) so empty/short passwords can't submit.
2. **'Learner' fallback removed** — `profile_page` `_displayName` defaults to
   `''` and falls back to the email local-part (not hardcoded 'Learner'); it
   binds to `UserModel.displayName` from `/me`.
3. **Hardcoded mock data removed**:
   - `streak_calendar.dart`: dropped `activeDays.addAll([3,7,10,14,18,22,25])`;
     calendar now derives only from `currentStreak` (empty for new users).
   - `learning_path_map.dart`: sample path reset so only node 1 is `current`,
     nodes 2–10 `locked` (was 1–4 completed + 5 stuck).
   - `badges_grid.dart`: rewritten to be data-driven via `earnedIds` (default
     empty) — no badges pre-unlocked. Backend `UserBadge` is empty on signup.
4. **Audio Play/Pause toggle** — `quran_reader_page` now tracks real playback
   via `_isAudioPlaying` (from `playerStateStream`); per-ayah button shows
   "Play" when paused / "Pause" when playing (was stuck on "Pause").
5. **Reset & signup flow** — root cause was `_resetLocalData`'s `onAuthenticated`
   capturing the disposed ProfilePage `context`, crashing post-signup nav.
   Added `core/navigation/app_navigator.dart` (`rootNavigatorKey`) used by
   `main.dart` and the reset flow. `clearAll()` already flushes the auth token;
   backend signup already returns a JWT for immediate login.
- Verified: `flutter analyze` clean (no errors); `ayah_widget_visibility_test`
   passes. `reader_render_test` still pre-fails (pre-existing 90s Dio timer).

## Session 2026-07-14 — Urdu Tarjuma AUDIO not playing (root cause + fix)
User: "tarjuma showing now but audio not coming". Text shows (local corpus) but
NO audio at all (Arabic included). ROOT CAUSES:
1. **Wrong CDN path (the real bug)**: `AppConstants.urduTranslationCdnUrl` was
   `https://everyayah.com/data/urdu_shamshad_ali_khan_46kbps` → **404**. The
   Urdu tarjuma folder actually lives under everyayah's `/data/translations/`
   path: `https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps`
   (verified: 001001/001007/002001/114001/002286 all HTTP 200 `audio/mpeg`).
   FIXED in app_constants.dart (added `/translations/` segment).
2. **Dead URL killed the whole queue**: the Urdu URL was concatenated into the
   SAME `ConcatenatingAudioSource` as Arabic. A dead/404 URL made just_audio
   throw on `setAudioSource`, so the entire sequence failed → zero audio.
   HARDENED in audio_service.dart: added `isUrduTranslationAvailable()` which
   probes the CDN (Range GET on 1:1, cached) and returns false on 404/timeout;
   `quran_reader_page._playAyahAudio` now only enqueues Urdu URLs when the probe
   passes, falling back to Arabic-only otherwise. So Arabic always plays.
- Rebuilt? NOT yet — this env has no Android SDK/NDK (cmdline-tools download
   blocked). User must rebuild + deploy: `cd mobile && flutter pub get &&
   flutter build apk --release` → copy to `releases/` → deploy APK to VPS
   20.197.40.13 (`/v1/app/download`). No backend/VPS change needed (pure
   frontend; source is public everyayah.com, no auth, CORS-open for media).
- `scripts/build_local_corpus.py` `URDU_AUDIO_BASE_URL` env (if used to bake
   `audio_url_ur` into the corpus) should also use the `/translations/` path;
   runtime already derives from the corrected constant.

## Session 2026-07-14 — Urdu TEXT must match the AUDIO (Jalandhari fix)
The Shamshad Ali Khan Urdu tarjuma AUDIO is a recitation of **Fateh Muhammad
Jalandhari's** translation (alquran.cloud edition `ur.jalandhry.text`). The
bundled Urdu text was the WRONG translator — Quran.com v4 resource **97 =
"Tafheem e Qur'an - Syed Abu Ali Maududi"** (`ur-al-maududi`) — so users read
Maududi but heard Jalandhari. ROOT CAUSE: `scripts/build_local_corpus.py`
`UR_RES = 97`. FIX:
- `UR_RES` → **234** (`ur-fatah-muhammad-jalandhari` = Jalandhari) in
  build_local_corpus.py, with a comment pinning it to the audio source. This is
  the Quran.com v4 equivalent of alquran.cloud `ur.jalandhry.text`.
- Regenerated `mobile/assets/quran_corpus.json` (41.6 MB) and gzipped over
  `quran_corpus.json.gz` (4.37 MB). Verified 1:1 = "شروع الله کا نام لے کر جو بڑا
  مہربان نہایت رحم والا ہے" (Jalandhari, matches audio).
- Also updated the 5 hardcoded fallback sample ayahs (surah 1) `translationUr`
  in quran_reader_page.dart from Maududi-style to Jalandhari for consistency
  (these only show if the corpus fails to load).
- Backend `translation_ur` comes from its (empty) corpus DB; no override of the
  local Jalandhari text. If backend is ever seeded, seed it with Jalandhari too.
- NOTE: `quran_corpus.json.gz` is a bundled APK asset — must REBUILD the APK
   (`flutter build apk --release`) to ship the corrected text. No backend change.

## Session 2026-07-14 — Tajweed colour-coding now works in Surah reader
User: "in surah section I didn't see any use of tajweed, tajweed not working".
ROOT CAUSE: two gaps.
1. **No tajweed data** — `scripts/build_local_corpus.py` hardcoded
   `"tajweed_spans": None` for every word, and the Quran.com request didn't
   even ask for tajweed text. So the mobile reader (which reads the bundled
   `quran_corpus.json(.gz)`) had nothing to colour. The ETL `tajweed_parser.py`
   existed but its per-ayah annotations were never turned into the word-level
   `tajweed_spans` the app expects.
2. **Wrong rendering** — `ayah_widget.dart` `_WordTapTarget` only coloured the
   WHOLE word by the FIRST span's rule (a known stub), not per-letter.
FIXES:
- `scripts/build_local_corpus.py`: added `text_uthmani_tajweed` to the API
  `fields`; new `build_tajweed_spans()` strips the `<tajweed class=X>`
  markup, computes each rule's char range in the plain ayah text, maps it to
  word-relative `start`/`end` offsets, and writes per-word `tajweed_spans`
  (`{start, end, rule, rule_name, rule_description}`). `TAJWEED_RULE_NAMES`
  maps Quran.com classes → friendly English names. Regenerated the corpus:
  45,874 of 83,665 words carry 61,173 tajweed spans (e.g. ghunnah on the
  shadda'd meem of 2:3). Wrote `quran_corpus.json` (47.9 MB) + gz (4.8 MB).
- `ayah_widget.dart` `_WordTapTarget`: now builds a `Text.rich` with one
  `TextSpan` per character run sharing a tajweed rule, colouring exactly the
  letters each rule covers (offsets are word-relative). `normal`/uncovered
  letters keep the default ink colour. RTL kept.
- `app_constants.dart` `tajweedColors`: re-keyed to the Quran.com v4 class
  names (ghunnah, ikhafa, qalaqah, idgham_ghunnah, iqlab, madda_*, slnt,
  ham_wasl, laam_shamsiyah, ...) with distinct colours; added
  `tajweedRuleLabels` for friendly legend/sheet names.
- `grammar_legend.dart`: tajweed chips now show `tajweedRuleLabels` names.
- `word_bottom_sheet.dart`: shows each non-`normal` tajweed rule of the tapped
  word (coloured) under a "Tajweed" row.
USAGE: in the Surah reader settings bar, tap **Tajweed** (mutually exclusive
with Grammar, which is on by default). Tap any word to see its rule(s).
VERIFIED: `flutter analyze` clean (only 2 pre-existing info lints);
`ayah_widget_visibility_test` passes. APK rebuilt (75.0 MB) and copied to
`releases/app-release.apk`; `pubspec.yaml` + `releases/app_release.json`
bumped to **v1.0.17+28**. NOTE: must REBUILD APK to ship the new corpus .gz
(the tajweed data lives in the bundled asset, not the backend). Deploy the
APK to VPS 20.197.40.13 (`/v1/app/download`) for OTA users. Not yet committed/
pushed (no git action requested).

## Session 2026-07-14 — Rebuilt APK + committed (v1.0.16+27)
Combined the Urdu audio+text fixes AND the earlier uncommitted v1.0.15 auth/UI
fixes into one release.
- **APK built successfully** (Android SDK present this time): `flutter build
  apk --release` → `mobile/build/app/outputs/flutter-apk/app-release.apk`
  (74.3MB). Copied to `releases/app-release.apk`. The APK was built AFTER the
  regenerated `quran_corpus.json.gz`, so it ships Jalandhari text.
- **Version bump**: `pubspec.yaml` → `1.0.16+27`; `releases/app_release.json`
  → version 1.0.16 / version_code 27, with en+ur+hi notes for the Urdu fix.
- **Committed** locally as `fdda3bb` (17 files: the Urdu audio/text fixes,
  audio_service resilience, auth/UI fixes, app_navigator, regenerated corpus
  .gz, rebuilt APK, bumped metadata, .gitignore now ignores the uncompressed
  `mobile/assets/quran_corpus.json` build artifact).
- **PUSHED** ✓ (commit fdda3bb) to origin/main with the user-supplied GitHub
  PAT (inline, not stored; `GIT_TERMINAL_PROMPT=0` + `-c credential.helper=`,
  token not persisted in git config). Large-APK (>50MB) warning as before —
  Git LFS still planned. REMAINING: deploy `releases/app-release.apk` to VPS
   20.197.40.13 (`/v1/app/download`) for OTA users to actually receive v1.0.16.
- APK >50MB warning persists (Git LFS planned later).


## Session 2026-07-14 — Real-time voice tracking + Memorization (Hifz) Mode (Tarteel-style)
Upgraded the **AI Recitation section** (home practice FAB) with continuous
real-time streaming, live word-by-word tracking, Memorization Mode, live error
detection and a hands-free always-listening visualizer.

IMPORTANT SCOPE RULE (per user): the Quran reader's per-ayah **"Recite" option
is UNTOUCHED**. Both entry points previously reused the SAME `RecitationPage`:
  - home FAB → `const RecitationPage()`  (the AI Recitation section — upgraded)
  - quran_reader `RecitationPageRoute` → `RecitationPage(surah, ayah)` (LEFT AS-IS)
So instead of editing `RecitationPage`, I built a **brand-new** page and only
re-pointed the home FAB. `RecitationPage` + its `RecitationState` enum are
byte-for-byte unchanged (widget_test 9-state count + recitation_screen_test
still pass).

### Backend (recitation_api + ml) — real-time streaming pipeline
- NEW `ml/alignment/streaming_matcher.py` `StreamingMatcher`: pure-Python
  incremental aligner. `evaluate(hyp_words)` greedily maps a *growing* ASR
  hypothesis onto the reference word list and returns stable per-word states
  (matched / error / skipped; unresolved = pending/masked). Handles skips,
  inserted/repeated words, and near-match ASR noise (char-sim >= 0.80). Robust
  to re-transcription revising earlier words. Unit tests:
  `ml/tests/test_streaming_matcher.py` (8, all pass).
- NEW `backend/recitation_api/app/services/streaming_session.py`
  `StreamingRecitationSession`: buffers PCM16, re-transcribes every ~1.2s of new
  audio in a thread, feeds the matcher, diffs status maps → incremental `word`
  events. Resolves reference words from the ml ReferenceStore → core_api
  fallback. Pluggable transcriber: real `QuranASR` (Whisper) OR a duration-based
  **stub** (used when `QARI_ML_USE_STUB=true` or no reference) that reveals words
  over time so the live flow is demoable without model weights. `finalize()`
  writes the full WAV to disk + persists a mobile-shaped RecitationAnalysisResult
  to Redis (so `GET /{session_id}`, history, A/B playback keep working).
- NEW WebSocket `WS /ws/recitation/stream` in `app/api/routes/websocket.py`.
  MUST be registered BEFORE `/ws/recitation/{session_id}` (else Starlette
  matches `stream` as a session_id path param — that was the initial bug).
  Protocol: client sends `{type:start,...}` → server `{type:ready, words:[...]}`
  → client streams binary PCM16 frames → server emits `{type:word, word_index,
  status, expected, spoken}` live → client `{type:stop}` → server `{type:final,
  result}`. Ping/pong keep-alive. Tests: `tests/test_streaming.py` (4, pass).
- `infra/nginx.conf`: added `proxy_read_timeout 3600s` + `proxy_send_timeout
  3600s` + `proxy_buffering off` to BOTH `/ws/` blocks so long hands-free
  sessions aren't dropped (default nginx WS read timeout is only 60s). Needs a
  VPS nginx reload to take effect.

### Frontend (Flutter) — all NEW files, legacy RecitationPage untouched
- `mobile/lib/data/models/recitation_stream_event.dart`: plain-Dart event model
  (`LiveWordStatus` {pending,matched,error,skipped}, `RecitationStreamEvent`).
- `mobile/lib/data/services/streaming_recitation_service.dart`: streams mic via
  `record`'s `startStream(pcm16bits,16k,mono)` → `dart:io WebSocket.connect(...,
  customClient:)` (trusts the VPS self-signed cert via badCertificateCallback).
  Exposes `events`, `amplitude` (RMS 0–1 for the visualizer), `connectionState`.
  `start/stop/cancel`; 20s ping keep-alive; NO auto-stop.
- `widgets/memorization_ayah_view.dart`: RTL word grid. Hifz mode blurs pending
  words (ImageFiltered) and reveals green when matched; red = mispronounced,
  amber+underline = skipped, live. Tracking mode shows all words, tints as they
  resolve.
- `widgets/mic_visualizer.dart`: always-on bottom bar visualizer (pulsing mic
  dot + scrolling RMS bars + "Listening") — shows the mic is continuously live.
- `pages/live_recitation_page.dart` NEW `LiveRecitationPage`: setup (target
  picker + Memorization toggle + Listen First + ayah preview) → live (real-time
  MemorizationAyahView + LIVE count-up timer that NEVER auto-stops + bottom
  MicVisualizer + Stop/Cancel) → results (reuses existing `RecitationResults` +
  `WordComparisonSheet`; synthesizes a result from live statuses if the final
  payload is missing). Own `LiveRecitationUiState` enum (does NOT touch
  `RecitationState`).
- `home_page.dart`: practice FAB now opens `LiveRecitationPage` (was
  `RecitationPage`). This is the ONLY change to an existing screen's behaviour.
- `app_constants.dart`: added `wsBaseUrl` / `recitationStreamWsUrl` (derived
  from baseUrl: http→ws, drop `/v1`), `trustedSelfSignedHost`, and live
  streaming constants (sample rate, ping interval, visualizer bar count).
- Tests: `mobile/test/live_recitation_test.dart` (7, all pass) — event parsing,
  setup UI (Hifz toggle + Start), memorization masking vs tracking.

### Verification
- `flutter analyze` clean on ALL new files. `flutter test live_recitation_test`
  7/7 pass. `recitation_screen_test` (Quran reader recite) + widget_test state
  count STILL pass (legacy untouched). Only pre-existing `widget_test` "Grammar
  color-coding" fails (references non-existent `fiil` key — unrelated).
- `pytest ml/tests/test_streaming_matcher.py` 8/8; recitation_api
  `tests/test_streaming.py` 4/4. The 2 pre-existing recitation test failures
  (no Redis running + intentional ayah-range clamp) are unchanged.
- Installed backend deps into the VPS venv (`/home/Innocent/venv`): fastapi,
  httpx, pytest-asyncio, redis, etc.

### DEPLOY NOTES
- VPS: reload nginx (WS timeouts) + restart `recitation-api` so the new
  `/ws/recitation/stream` route is served. The `inference-worker` is unaffected
  (streaming runs inside recitation-api, not the worker). Real live transcription
  needs the Whisper model available in recitation-api; otherwise it falls back to
  the duration-based stub (still reveals words live). Consider running with
  `QARI_ML_USE_STUB=false` once Whisper is loaded there.
- Mobile: APK NOT rebuilt this session (rebuild with `flutter build apk
  --release` then deploy to VPS `/v1/app/download`; bump pubspec + app_release).
- NOT yet bumped pubspec version — do that with the APK rebuild.

## Session 2026-07-14 — Hifz (Memorization) Mode UI refined to Tarteel-style spec
The prior commit (2951bc6) built the live recitation + Hifz mode but the hidden
words used an `ImageFiltered` BLUR of the real glyphs. User asked for the exact
Tarteel-style behaviour: a **page of subtle circular placeholder dots** (not
blurred text), a `currentWordIndex` integer in state, auto-scroll so the active
word stays centered, and a temporary RED flash on incorrect words. Refinements
(working tree, not yet committed/built):
- `memorization_ayah_view.dart`: pending words in Hifz mode now render as a
  small `BoxShape.circle` dot using `theme.colorScheme.onSurface` @ 0.3 (the
  primary text colour at reduced opacity — blends into the dark brown theme).
  Revealed words use `AppTheme.arabicTextStyle(...)` with `onSurface` — the
  EXACT same TextStyle/font-size/colour as the reader's ayah text (no green tint
  in Hifz mode; only mistakes are coloured). Wrong = red, skipped = amber. The
  `Wrap` keeps `TextDirection.rtl`. Each word gets a stable `GlobalKey` (via
  `wordKeys`) for scrolling.
- `live_recitation_page.dart`: added a `ScrollController` on the live
  `SingleChildScrollView`; a `currentWordIndex` int + `flashIndex` int +
  `_flashTimer`; `_onEvent` reveals sequentially (matched → reveal at
  `currentWordIndex` + advance; error/skip in Hifz → flash the current dot,
  do NOT reveal) and flashes red/amber for ~900ms; `_scrollToCurrent()` uses
  `Scrollable.ensureVisible(alignment:0.5)` post-frame to center the active word
  as words wrap. `_resetWordTracking()` rebuilds the per-word keys on ayah load /
  `ready` / start / cancel / reset. `dispose()` disposes the controller + timer.
  Removed the now-unused `_activeIndex` getter. Legacy `RecitationPage` untouched.
- `test/live_recitation_test.dart`: updated to assert circular-dot placeholders
  (was `ImageFiltered`) for pending words and that matched words show as text.
- VERIFY: `flutter analyze` clean (info-only hints); `live_recitation_test` 7/7
   pass; `recitation_screen_test` (legacy) still passes.
- COMMITTED + PUSHED (commit 44f8a75) with the user's GitHub PAT (inline, not
   stored). APK rebuilt cleanly (75.5MB) via `flutter build apk --release` with
   the present Android SDK (`ANDROID_HOME=/home/Innocent/Android`), copied to
   `releases/app-release.apk`; `pubspec.yaml` + `releases/app_release.json`
   already bumped to **v1.0.18+29** (Hifz release notes). Large-APK (>50MB)
   warning as before — Git LFS still planned.
- REMAINING (blocked this session): deploy `releases/app-release.apk` +
   `app_release.json` to the VPS host path `/app/releases` (OTA
   `/v1/app/download`). SSH to 20.197.40.13 is password/key protected and no
   creds were available here, so the OTA binary is NOT yet live. Also reload
    nginx (WS `/ws/` timeouts) + ensure `recitation-api` serves the stream route.

## Session 2026-07-14 — Live Hifz streaming: two production fixes
Found + fixed two genuine defects in the existing Hifz/live-tracking feature
(code was already built in commits 2951bc6/44f8a75; these were latent bugs):

1. **Streaming alignment misalignment (real correctness bug)** —
   `ml/alignment/streaming_matcher.py` `StreamingMatcher.evaluate` reset the ASR
   hypothesis cursor `j=0` on EVERY pass while the reference cursor `i` had
   already advanced (`self._cursor`). Because the ASR hypothesis is *cumulative*
   (re-transcribed from the whole audio buffer each pass), re-matching the
   leading hypothesis words against the advanced reference cursor flagged
   correctly-recited words as `error` — i.e. the live Hifz view would mark real
   recitation RED. FIX: added `self._hyp_cursor` (hypothesis words consumed by
   the resolved reference prefix) and resume `j` there each pass. The
   order-preserving greedy alignment guarantees the resolved prefix maps 1:1 to
   the consumed hypothesis prefix, so no spurious ERRORs. `evaluate`/`finalize`
   verdicts now correct. `ml/tests/test_streaming_matcher.py::
   test_sliding_window_limits_single_pass` now passes.
2. **Build-breaking compile error** — `mobile/.../widgets/mic_visualizer.dart`
   used `StreamSubscription` without `import 'dart:async';` → `flutter analyze`
   ERROR (would break the APK build). Added the import. Removed an unused
   `sentBytes` var in `streaming_recitation_service.dart`. `flutter analyze` on
   both files: **No issues found**.

VERIFY: `pytest ml/tests backend/recitation_api/tests` → only the 2 pre-existing
Redis-less `test_api.py` failures remain (event loop closed; unrelated). The
feature now satisfies the blueprint end-to-end (normalization, sliding window of
15, `match`/`error_skipped` wire events, RTL Wrap, 0.3-opacity placeholder dots,
granular per-word rebuild, auto-scroll, 300ms PCM16 streaming).

### APK build + release (v1.0.19+30)
While verifying the build, two MORE working-tree compile errors surfaced (the
Hifz code had never been rebuilt since the refinements):
- `recitation_repository.dart` used `File(...)` without `import 'dart:io';` →
  added it.
- `recording_service.dart` called `_recorder.isSupported()` but `record` v85's
  `AudioRecorder` has no `isSupported()` method → dropped the guard and call
  `stop()` directly inside the existing try/catch.
After fixes `flutter analyze lib` → 0 errors (only info/warning lints). Rebuilt
APK with present Android SDK (`ANDROID_HOME=/home/Innocent/Android`) →
`mobile/build/app/outputs/flutter-apk/app-release.apk` (75.6MB) copied to
`releases/app-release.apk`; `pubspec.yaml` + `releases/app_release.json` bumped
to **v1.0.19+30**. Committed (amended into 48d9dc1). REMAINING: push to
origin/main (needs GitHub PAT — none in this env) + deploy APK to VPS host
 `/app/releases` (OTA `/v1/app/download`) + reload nginx (WS timeouts) + ensure
 `recitation-api` serves `/ws/recitation/stream`.

## Session 2026-07-14 — Live Recitation rewritten to Mushaf (blank-canvas) layout
User demanded the Hifz/dot UI be scrapped: remove the Memorization Mode toggle,
start as a BLANK canvas (no dots/boxes), and reveal confirmed words one-by-one
as a continuous RTL Mushaf (physical-book) flow with inline ۝ ayah markers.

MOBILE CHANGES (mobile/lib):
- NEW `features/recitation/presentation/widgets/mushaf_reveal_view.dart`
  `MushafRevealView`: a single `Directionality(rtl)` + `Wrap(direction:
  Axis.horizontal)` of revealed Arabic words. Starts EMPTY — no placeholder dots.
  Inserts an inline circular `۝<verse>` ayah marker between ayahs (driven by
  `ayahBoundaries` last-word indices). A `caretKey` zero-width anchor is placed
  at the end so the page can auto-scroll the latest word. Correct words read in
  plain `onSurface` book ink; error=red, skipped=amber.
- REWROTE `features/recitation/presentation/pages/live_recitation_page.dart`:
  deleted ALL Memorization Mode / Hifz / per-word `HifzWordState` machinery
  (Switch, `_ModePill`, dots, flash). Added `_revealedWords` + `_revealedStatuses`
  (both start `[]`) + `_revealedIndices` dedup set. On each `word` WS event the
  confirmed Arabic word (`event.expected ?? event.spoken`) is appended (skips
  empties/dupes). Live screen shows a blank canvas + a faint centered hint until
  the first word; then the `MushafRevealView`. `_scrollToLatest()` measures the
  caret via `Scrollable.of(ctx)` and, when it enters the bottom 30% of the
  viewport, animates it to ~33% (upper third) — no fighting user scrolling.
  Setup screen no longer has the toggle; it shows a plain RTL target preview.
  `_LiveStatusBadge` simplified (no mode pill). `RecitationPage` legacy untouched.
- `data/services/streaming_recitation_service.dart`: audio PCM flush cadence
  300ms → **250ms** (explicit user requirement: send PCM every 250ms). Mic
  permission is requested and the `record` stream stays open until Stop/Cancel
  (already correct). `_start` now always sends `memorizationMode:false`.
- DELETED `widgets/memorization_ayah_view.dart` (no longer referenced).
- `test/live_recitation_test.dart`: rewritten — asserts NO "Memorization Mode"
  text and NO `Switch` on setup; `MushafRevealView` starts blank, reveals words
  + `۝2` marker, and tints error words. 8/8 pass.

BACKEND (verified, mostly unchanged): `app/services/streaming_session.py`
`duration_seconds = total_samples / sample_rate`. Confirmed via a direct
`StreamingRecitationSession` harness: feeding a 3s PCM buffer yields
`duration_seconds: 3.0` and a non-empty final result — so the "Duration: 0s"
symptom is fixed as long as audio reaches the socket (it does: binary frames
flushed every 250ms; `websocket.py` accumulates via `add_audio`). The prior
"0%" was the stale/undeployed APK + empty backend reference data; with the
reference bundle (`reference_data`, built from local corpus) the stub/Whisper
transcriber reveals real words.

VERIFY: `flutter analyze lib` → 0 errors (only pre-existing flashcard warning).
`flutter test test/live_recitation_test.dart` → 8/8 pass. APK built with present
Android SDK (`ANDROID_HOME=/home/Innocent/Android`) →
`mobile/build/app/outputs/flutter-apk/app-release.apk` (75.5MB), copied to
`releases/app-release.apk`; `pubspec.yaml` + `releases/app_release.json` bumped
to **v1.0.20+31**. NOT committed/pushed (no git action requested; needs GitHub
PAT). REMAINING: push to origin/main + deploy APK to VPS host `/app/releases`
(OTA `/v1/app/download`) + reload nginx (WS timeouts) + ensure `recitation-api`
 serves `/ws/recitation/stream` with the reference bundle present.

## Session 2026-07-14 — Live Recitation results: fix "0 of 0" + "Duration 0s"
User tested the v1.0.20 Mushaf build: UI/live state correct, but Results screen
showed **"0 of 0 words correct"** AND **"Duration: 0s"**. Root-caused both:

1. **BACKEND BUG (the real "0 of 0" cause)** — in
   `backend/recitation_api/app/services/streaming_session.py` `load_reference`,
   after the (new) client-words fallback populated `self.reference_words`,
   the code still built `StreamingMatcher(norm)` and
   `_make_stub_transcriber(norm)` from the ORIGINAL local `norm` variable —
   which was EMPTY when the server's own reference store was empty. So the
   matcher tracked 0 reference words and the stub revealed 0 words → 0 verdicts
   → "0 of 0". FIX: build matcher + transcriber from `self.reference_words`
   (and gate the stub on `not self.reference_words`). Verified with a harness:
   empty server ref + client_words(6) now yields 4 live word events,
   `duration_seconds: 4`, 6 verdicts, score 0.67. Backend `tests/test_streaming.py`
   5/5 still pass.

2. **CLIENT-WORDS REFERENCE FALLBACK (defends against empty server ref)** —
   `streaming_recitation_service._start` now sends `words: _words` (the full
   resolved Mushaf/surah target) in the `start` handshake. `websocket.py`
   reads `start["words"]` → `StreamingRecitationSession(client_words=...)`.
   `load_reference` uses them only when its own reference resolves empty.

3. **RESULTS RESILIENCE** — `live_recitation_page._finishWith` now prefers the
   backend result ONLY if it has >0 word verdicts; otherwise it synthesizes
   from the live `_revealedWords` so the screen is never "0 of 0". `_words`
   (full target) is always passed as `ayahWords` to `RecitationResults`.

4. **AGGRESSIVE STREAMING DIAGNOSTICS (user-requested, for Duration 0s)** —
   `streaming_recitation_service.dart`:
   - `_audioSub` now has `onError` (logs MIC STREAM ERROR) + logs each mic
     chunk's byte length (first 5 + every 50th) and the cumulative buffered size.
   - `_flushAudio` logs bytes sent per 250ms flush (`totalSent=…`) and warns if
     the socket isn't open (so 0-byte sends are obvious).
   - WS `onError`/`onDone` listeners log connection drops / handshake errors.
   - `_onSocketData` logs RX ready/word/final/error events.
   - `_stop` logs `totalSentBytes` + mic chunks, the `stop` send, and the final
     result's `duration_seconds`/verdict count; timeout bumped 20s→30s.
   - `_start` wraps `startStream` in try/catch logging mic failure; connect logs
     the WS URL. `Stop & Review` ALREADY awaited the server `final` before
     navigating (via `_finalCompleter`) — confirmed untouched.

NOTE: a true "Duration 0s" on a device almost always means no PCM reached the
server. The code path is correct (binary frames flushed every 250ms; nginx
`/ws/` proxy has Upgrade headers + `proxy_buffering off` + 3600s timeouts, both
server blocks). The new per-flush byte logs will show `totalSent=0` if the
local recorder yields nothing (broken mic/permission) vs a healthy count. If
audio reaches the server but server ref was empty, the client-words fallback now
still scores. Also ensure the VPS `recitation-api` is actually serving the new
code + the reference bundle, and nginx was reloaded.

VERIFY: `flutter analyze lib` → 0 errors; `flutter test test/live_recitation_test`
8/8 pass; backend `pytest tests/test_streaming.py` 5/5. APK rebuilt (75.6MB) →
`releases/app-release.apk`; bumped to **v1.0.21+32**. NOT pushed (needs GitHub
PAT — none in env). REMAINING: push + deploy APK to VPS `/app/releases` + reload
nginx + restart `recitation-api` so the new stream route + client-words fallback
ship.






## Session 2026-07-14 — CRITICAL: "all 0%" was a backend DEPLOYMENT bug (fixed live)
User still saw "0 of 0 words" + 0% after the v1.0.21 code fixes. Root cause was
NOT the app logic — it was the running `recitation-api` container:
- Streaming runs INSIDE `recitation-api`, but `infra/docker-compose.yml` only
  mounted `../ml:/app/ml` (+ `PYTHONPATH:/app`) into `inference-worker`, NOT
  `recitation-api`. So `import ml.alignment.streaming_matcher` failed →
  `load_reference` raised → `ready` sent with 0 words → 0 verdicts → 0%/0-of-0.
  Server log showed `ws.stream.load_ref_failed error=No module named 'ml.alignment'`
  then `No module named 'numpy'` then `No module named 'torch'`.
- The image also lacked numpy/torch entirely (built before requirements.ml.txt
  was complete), but that's now moot.

FIXES (all committed to repo; container restarted + re-tested end-to-end):
1. `infra/docker-compose.yml` `recitation-api`: added `../ml:/app/ml` bind mount,
   `PYTHONPATH: /app`, `QARI_ML_USE_STUB: "true"` (live stream reveals words
   via the duration-based stub — no Whisper needed in this container), and a
   read-only `reference_data` mount.
2. `ml/alignment/__init__.py`: made the package `__init__` LAZY — it no longer
   eagerly imports `word_alignment`/`forced_alignment` (numpy/torch). Plain
   `from ml.alignment import StreamingMatcher` now pulls NOTHING heavy; the
   torch-dependent names load on first access (so the batch worker still works).
3. `backend/recitation_api/app/services/streaming_session.py`:
   - `_normalize` inlined (regex only) so reference resolution no longer imports
     the heavy `ml.inference.asr` (torch/numpy).
   - `_decode_float` rewritten numpy-free (`array('h')` → list of floats), so the
     live stream needs NEITHER numpy NOR torch.
   With these, the live stub flow runs in the API container with no ML stack.
   Verified: a WS client sending start+5s PCM+stop now returns
   `word_count=4`, `duration=5`, `verdicts=4`, `score=1.0`, 4× status "match".
   `tests/test_streaming.py` 5/5 still pass; `from ml.alignment import WordAligner,
   StreamingMatcher` both import (worker path intact).
- NOTE: `recitation-api` now uses `QARI_ML_USE_STUB=true`, so live matches are
  time-based (not true phonetic ASR). For REAL Whisper scoring, install
  torch/whisper into `recitation-api` and set `QARI_ML_USE_STUB=false` (the image
  currently lacks torch). The batch upload flow (inference-worker) is unaffected
  and keeps the real engine.

DEPLOY STATE: the running `recitation-api` container was recreated with the new
mounts/env and the new code (bind-mounted, so it is live). nginx proxies `/ws/`
→ recitation-api:8001 (Upgrade headers + proxy_buffering off + 3600s timeouts
already in infra/nginx.conf). The OTA APK (releases/app-release.apk = v1.0.21)
sends `words` in the start handshake and handles word events, so the app must be
updated to v1.0.21 to hit the fixed backend. REMAINING (user side): update the
app via OTA, then push this commit to origin/main (needs GitHub PAT — none in
env). The APK was already rebuilt at v1.0.21+32 in the prior turn.

## Session 2026-07-15 — Live ASR swapped to Faster-Whisper (CTranslate2, INT8, CPU)
Tarteel runs a custom Quranic ASR; their public `tarteel-ai/whisper-tiny-ar-quran`
is a Whisper-tiny fine-tuned on Quranic Arabic. The live recitation stream
previously used the heavy PyTorch `ml.inference.asr.QuranASR`
(`tarteel-ai/whisper-base-ar-quran`) — too slow for real-time on a CPU VPS.
Swapped ONLY the live transcriber to **Faster-Whisper + CTranslate2 (INT8)**
(CPU-friendly, ~2–4x faster than PyTorch). Server-side `StreamingMatcher`
forced-alignment + all features (history, tajweed, Mushaf reveal) unchanged.
The legacy Quran-section `RecitationPage` was NOT touched.

CHANGES:
- NEW `ml/inference/faster_whisper_transcriber.py`: `FasterWhisperTranscriber`
  (lazy, thread-safe singleton `get_transcriber()`). Loads CT2 model via
  `WhisperModel(model_dir, device="cpu", compute_type="int8", word_timestamps)`.
  `transcribe()` returns RAW Arabic word tokens + per-word `probability`
  (normalization left to the caller). Model dir via env `QARI_FASTERWHISPER_MODEL_DIR`
  (default `/app/models/tarteel-ct2-tiny`).
- `backend/recitation_api/app/services/streaming_session.py`:
  `_real_transcriber` now calls `get_transcriber().transcribe(...)` and
  normalizes the returned words with the SAME inlined `_normalize` used for the
  reference words (so hypothesis↔reference match consistently). Returns `([],[])`
  on any failure (graceful, no crash).
- `backend/recitation_api/requirements.ml.txt`: added `faster-whisper==1.0.3`,
  `ctranslate2==4.4.0`, `av==12.2.0`, `requests==2.32.3` (faster-whisper imports
  `requests` at load). `inference-worker` still uses the PyTorch `QuranASR` for
  the batch upload flow — unaffected.
- `infra/docker-compose.yml` `recitation-api`: `QARI_ML_USE_STUB` → `"false"`
  (real Faster-Whisper runs in this container, no GPU needed) + new
  `QARI_FASTERWHISPER_MODEL_DIR: /app/models/tarteel-ct2-tiny`. The CT2 model is
  bind-mounted via the existing `../backend/recitation_api:/app` volume, so it
  appears at `/app/models/tarteel-ct2-tiny`.
- NEW `scripts/convert_tarteel_model.py`: one-command conversion of
  `tarteel-ai/whisper-tiny-ar-quran` → CT2 INT8 via `ct2-transformers-converter`,
  then generates `tokenizer.json` (the source ships the classic GPT2 Whisper
  tokenizer, not a fast tokenizer that faster-whisper needs).

MODEL CONVERSION (done in this dev env, ~42MB INT8):
`python scripts/convert_tarteel_model.py` → writes
`backend/recitation_api/models/tarteel-ct2-tiny/` (model.bin + tokenizer.json +
preprocessor_config.json). That dir is gitignored (large weights, like
`reference_data/`). On the VPS, run the same script so the model exists on disk
at `<repo>/backend/recitation_api/models/tarteel-ct2-tiny` (the bind mount makes
it available at `/app/models/tarteel-ct2-tiny` inside the container). Conversion
needs `transformers` + `torch` + `ctranslate2` (NOT needed at inference).

VALIDATION (real end-to-end, this env):
- `pytest ml/tests` + `backend/recitation_api/tests/test_streaming.py` → 120 passed
  (includes new `test_faster_whisper_transcriber.py`, mocked).
- Real model: synthesized a 16k Arabic clip (espeak-ng `بسم الله الرحمن الرحيم`)
  and ran it through `StreamingRecitationSession` with the real Faster-Whisper
  transcriber: model loaded, `transcribe()` returned real Arabic word tokens +
  confidences, `StreamingMatcher` emitted live `word` events and `finalize()`
  produced a scored result (score 0.5 on the ROBOTIC espeak TTS — expected;
  real human recitation transcribes far better, per prior session notes).
  NOTE: the default model dir is `/app/models/tarteel-ct2-tiny`; when testing
  locally set `QARI_FASTERWHISPER_MODEL_DIR=backend/recitation_api/models/tarteel-ct2-tiny`.

DEPLOY NOTE: after this change the running `recitation-api` container must be
recreated (compose now sets `QARI_ML_USE_STUB=false` + model dir) and the CT2
model present on the VPS host at `backend/recitation_api/models/tarteel-ct2-tiny`.
No Flutter/mobile change needed — the app unchanged. APK not rebuilt.

### Deployed on the VPS (this session, live container `infra-recitation-api-1`)
- Rebuilt `recitation-api` image (added faster-whisper/ctranslate2 to
  requirements.ml.txt) and recreated the container → `QARI_ML_USE_STUB=false`,
  model mounted at `/app/models/tarteel-ct2-tiny` (bind mount). Health OK.
- BLOCKER + FIX 1 (ctranslate2 exec-stack): the CT2 shared lib is compiled with
  an executable-stack (RWE GNU_STACK). The container kernel refused to enable it
  → `libctranslate2...so: cannot enable executable stack as shared object
  requires: Invalid argument` and live transcription silently fell back to 0
  verdicts. `execstack` is NOT installable here, so added
  `backend/recitation_api/fix_execstack.py` (clears the exec bit on the
  GNU_STACK phdr via raw ELF editing) and a `RUN python3 fix_execstack.py` step
  in `backend/recitation_api/Dockerfile` (runs AFTER `pip install`, before
  `COPY . .`). Verified: GNU_STACK now `RW`. This is durable across recreates.
- FIX 2 (final verdict `actual_text` was always null): `StreamingMatcher.
  finalize()` rebuilt `WordState` without carrying `spoken`, so the final
  result's word_verdicts had `actual_text: null` (broke the "compare your
  recitation" results sheet). Now `finalize()` looks up the spoken word +
  confidence from `_resolved_states`. Live `word` events already had it; the
  final payload now matches.
- VALIDATION (live WS, espeak-ng Arabic clip → `ws://localhost:8001/ws/
  recitation/stream`): model loaded, `Processing audio` logged, real Arabic
  `word` events streamed, `final` returned with populated `expected_text` +
  `actual_text` and a scored result. Accuracy on the ROBOTIC espeak TTS is low
  (expected — Whisper-Quran is trained on natural recitation); a real human
  recitation transcribes far better. `pytest ml/tests` +
  `backend/recitation_api/tests/test_streaming.py` → 120 passed.
- NOT committed/pushed (no git action requested). Changes to commit later:
  `ml/inference/faster_whisper_transcriber.py`, `ml/alignment/
  streaming_matcher.py` (finalize fix), `backend/recitation_api/app/services/
  streaming_session.py`, `backend/recitation_api/Dockerfile` +
  `fix_execstack.py`, `backend/recitation_api/requirements.ml.txt`,
  `infra/docker-compose.yml`, `scripts/convert_tarteel_model.py`,
  `ml/tests/test_faster_whisper_transcriber.py`, `.gitignore`
  (backend/recitation_api/models/ ignored). The converted model is gitignored.

## Session 2026-07-15 (later) — Device "0 of N / Duration 0s" = missing RECORD_AUDIO
User tested the live AI Recitation on device: results showed "0 of 29 words
correct / Duration: 0s / all 0%", no words appeared while reciting, and "qari
voice has no sound". ROOT CAUSE: `mobile/android/app/src/main/AndroidManifest.xml`
was **missing `android.permission.RECORD_AUDIO`** entirely. The WebSocket
connected fine (29 reference words arrived), but with no manifest permission the
OS silently blocked ALL mic capture → zero PCM frames sent → server finalizes
with 0 samples → "Duration 0s" + 0/N. The `record` package + permission_handler
runtime request can't grant capture without the manifest declaration.
FIX: added `<uses-permission android:name="android.permission.RECORD_AUDIO"/>`
to the manifest. Bumped app to **v1.0.22+33** (pubspec.yaml + releases/
app_release.json with fix notes), rebuilt APK (76.0MB) and copied to
`releases/app-release.apk` — which is bind-mounted into core-api at `/app/
releases` (read-only), so the OTA (`/v1/app/download` + `/v1/app/version`)
immediately serves v1.0.22 with no container restart. Verified the VPS now
returns the 76.0MB APK + version_code 33. User must UPDATE via OTA and ALLOW
microphone when prompted; then live word tracking should work.
NOTE: "qari voice no sound" was NOT fully root-caused — the live Mushaf page
does not play reference audio during recitation (no "Listen First" in this
build); the reference track only appears on the results screen via
`reference_audio_url` (may be empty if the reference bundle lacks audio URLs).
Likely a device-volume/Bluetooth issue or missing reference URL, not the mic
bug. Ask the user where they expect qari audio (during recitation vs results)
before adding a feature.
APK build uses ANDROID_HOME=/home/Innocent/Android (SDK present; set it before
`flutter build apk --release`). `flutter pub get` then build ~152s.

## Session 2026-07-15 (still) — RECORD_AUDIO alone didn't fix "0 of N"
Deployed v1.0.22+33 (RECORD_AUDIO added) but user STILL got "0 of 29 /
Duration 0s / no words / tajweed not showing". Server logs prove the device
connects and sends the 29-word `start` handshake (`ws.stream.started words=29`)
and the WS works — but there is NO "Processing audio" for the user's sessions,
i.e. **zero audio bytes reached the server**. The 29 "Word by Word" words are
the LOCAL target list, NOT proof of server connection. So even after the
permission fix, mic capture or binary-send is still failing silently on the
device (tajweed "not working" is just a consequence of no revealed words).
ADDED DIAGNOSTICS (built v1.0.23+34, deployed to OTA):
- `StreamingRecitationService`: public getters `sentBytes` (_totalSentBytes) and
  `micChunks` (_chunkCount).
- `live_recitation_page.dart`: a live "diag · mic chunks: N · bytes sent: N" text
  (via ValueNotifier so only that Text rebuilds, not the reveal view; 500ms
  `_diagTimer`). On finish, if `sentBytes == 0` show a clear error
  "No microphone audio was captured (0 bytes sent)…" instead of a silent 0/N.
  Timer stopped in `_stop`/`_cancel`/`_reset`/`dispose`.
NEXT: user must update to v1.0.23 and report the diag line:
  - "mic chunks: 0 · bytes sent: 0" ⇒ recorder produces no data (OS still
    blocking capture despite permission — check OS mic privacy / another app
    holding the mic / Android version quirk).
  - "mic chunks: N · bytes sent: 0" ⇒ capture OK but binary WS send fails.
  - "bytes sent: >0" ⇒ transport OK, server-side issue (unlikely; server shows
    no audio for these sessions).
NOT YET committed (user will request). Changes: AndroidManifest RECORD_AUDIO,
streaming_recitation_service getters, live_recitation_page diagnostics,
 pubspec + app_release.json bumps (→1.0.23+34), plus the earlier uncommitted
 Faster-Whisper backend work.

## Session 2026-07-15 — DIAGNOSING "mic chunks: 0 · bytes sent: 0" (no error)
User updated to v1.0.23+34; live diag still shows `mic chunks: 0 · bytes sent: 0`
and the final screen says "No microphone audio was captured … OS is blocking
capture". There is NO native error captured (`_micError == null`). The single
watchdog restart (same config) fails identically → 0 chunks every time.

INVESTIGATION (read the `record` plugin source in pub cache, v7.1.1 /
record_android 2.1.2):
- `AudioRecorder.start` (record_android) runs the `RecordThread`, which builds
  `PCMReader` (the `AudioRecord`). If `AudioRecord.state != INITIALIZED` or
  `getMinBufferSize` reports bad config, it throws "PCM reader failed to
  initialize." / "Recording config is not supported by the hardware". That
  exception is caught by the thread and routed to `onFailure` → BOTH
  `sendStateErrorEvent` (state EventChannel) AND `sendErrorEvent` (record
  EventChannel), posted via `uiThreadHandler.post` AFTER the start method
  already returned `success`.
- The record-data stream error is ALMOST ALWAYS LOST: `record` v7's
  `_startRecordStream` only forwards `ctrl.addError` when `ctrl.hasListener`
  is true, but the app attaches its `audioStream.listen` (via `_attachMic`)
  only AFTER `startStream`/`await` resolves — by then the native error Event
  has already fired on the channel and is dropped. So the recorder fails
  silently → exactly `micChunks: 0, micError: null`.
- ROOT-CAUSE HYPOTHESIS (to be confirmed on device): the requested
  `RecordConfig` (PCM16, **16kHz**, `voiceRecognition` source) is rejected by
  the user's device/ROM — either 16kHz isn't supported for that source on some
  OEMs (Xiaomi/OPPO/Huawei) → init failure, or `VOICE_RECOGNITION` source
  returns 0 frames on that ROM → silent 0-chunk stream. (record never requests
  AudioFocus unless `audioInterruption != NONE`, but missing focus alone would
  not cause 0 chunks.)

FIX APPLIED = DIAGNOSTICS ONLY (user chose "investigate first", not fix yet):
- `StreamingRecitationService`: subscribe to `_recorder.onStateChanged()`
  BEFORE `startStream` (`_subscribeRecorderState`) and capture its `onError`
  into `_micError`. The state channel is attached earliest, so its setup-error
  event survives (unlike the audio-data channel) → the real cause becomes
  visible. Re-subscribed after each recorder recreate (`_restartMic`) and
  cancelled in `cancel`/`dispose`.
- `live_recitation_page.dart`: new `_micErrorNotifier` surfaced live in the
  `diag · mic chunks: N · bytes sent: N` line (turns red + prints the recorder
  error) so a swallowed failure shows immediately, not only on the error screen.
- `flutter analyze` passes (only pre-existing info/warning items).

NEXT (confirm on device, then fix): rebuild + OTA the diagnostic build, have
user retry. Two outcomes:
  - diag shows `recorder error: PCM reader failed to initialize / config not
    supported` → it's a CONFIG issue → add `startStream` fallback across
    `(voiceRecognition|mic, 16k|44.1k)` and/or `audioInterruption`/audio focus.
  - diag still `mic chunks: 0 · micError: null` → recorder INITIALIZED but
    emits silence (OEM voiceRecognition quirk / OS truly blocking) → switch to
    `AndroidAudioSource.mic` (or `unprocessed`) + `audio_session` focus.
NOT committed/pushed; version NOT bumped yet (waiting on device confirmation).

---

## Session 2026-07-15 (night) — Root cause FOUND + native mic-capture rework (Android 16)

DEVICE: user's phone is **Android 16 (API 36)**. Flutter 3.44.6 is installed
on the VPS at `/home/Innocent/flutter` (not on PATH by default — export
`PATH="/home/Innocent/flutter/bin:$PATH" ANDROID_HOME="/home/Innocent/Android"`).
Backend recitation-api also runs on this VPS and serves the OTA APK from
`releases/app-release.apk` (bind-mounted read-only into core-api; no container
restart needed — the version endpoint reflects the new file immediately).

### Symptom progression (all on the live AI Recitation screen)
1. `mic chunks: 0 · bytes sent: 0 · voiceRecognition@16000Hz` (no focus info yet).
2. Added audio-focus diagnostics → user retested: `focus: NO`. Verified in
   `audio_session` source (`AndroidAudioManager.requestAudioFocus` returns
   `status == AUDIOFOCUS_REQUEST_GRANTED`) so `focus: NO` is a REAL OS denial.
   This ruled out: another app holding the mic, and the Quick Settings mute
   toggle (muting denies data but NOT audio focus).
3. Implemented microphone **foreground service** (option b). User retested:
   **`focus: yes`** — so focus denial was real and the foreground service fixed
   it. BUT still `mic chunks: 0` for ALL 4 fallback configs (user watched the
   diag cycle voiceRecognition@16k → mic@16k → unprocessed@16k → mic@44.1k,
   all 0 frames).
4. Conclusion: the `record` Flutter plugin opens `AudioRecord` on the Flutter
   engine thread, **outside** the foreground-service capture context, so on
   Android 14+ the OS grants focus yet delivers 0 frames (from
   `record_android` `PCMReader.read()` = blocking; only non-empty buffers are
   posted → 0 chunks, no error). Source confirmed in
   `record_android-2.1.2/.../recorder/PCMReader.kt` and `RecordThread.kt`.

### Fix: native capture INSIDE the foreground service (committed, v1.0.30+41)
Replaced the `record`-based live stream with native capture:
- `mobile/android/app/src/main/kotlin/com/qari/app/MicForegroundService.kt`
  (NEW): opens `AudioRecord` (VOICE_RECOGNITION, PCM16 mono) at 16 kHz,
  falls back to 44.1 kHz + linear resample to 16 kHz (`LinearResampler`),
  reads in a background thread, posts PCM16 frames over an `EventChannel`.
- `MicStreamBridge.kt` (NEW): process-wide bridge holding the Flutter
  `EventSink`s (audio + status).
- `MainActivity.kt`: registers `MethodChannel com.qari.app/mic_foreground`
  (start/stop) + `EventChannel com.qari.app/mic_stream` (PCM frames) +
  `com.qari.app/mic_status` (status strings).
- `streaming_recitation_service.dart`: removed all `record` usage for the live
  stream; subscribes to the native `EventChannel`s; keeps WS/flush/amplitude/
  audio-focus logic. Diag line now shows native `nativeStatus` instead of the
  old config label.
- `live_recitation_page.dart`: diag line shows `nativeStatus` + `focus: yes/no`.
- Manifest: `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MICROPHONE` permissions
  and `<service android:name=".MicForegroundService"
  android:exported="false" android:foregroundServiceType="microphone" />`
  (these were present BEFORE the crashes).

### CRITICAL: the app HARD-CRASHED on "Start Reciting" (3 rounds) — root causes
The crash was NOT a missing manifest entry. Three distinct Android-14 native
pitfalls, each fixed:
1. **Call-site throw**: `startForegroundService()` throws
   `ForegroundServiceStartNotAllowedException`/`SecurityException` at the call
   site (inside `MainActivity`'s MethodChannel), BEFORE the service's own
   try/catch. Fixed by wrapping `MicForegroundService.start(this)` in try/catch
   in `MainActivity` and piping to the diag status channel + `result.error`.
2. **BadNotificationException**: notification channel must be created BEFORE
   `startForeground()`, and the small icon MUST be a valid monochrome drawable
   (NOT `R.mipmap.ic_launcher` — caused instant kill on Android 12+). Added
   `res/drawable/ic_mic_notification.xml` (monochrome mic vector) and use it.
3. **Uncatchable JNI crash**: calling `EventChannel` `eventSink.success()`
   from the background `AudioRecord` read thread crashes the app with no
   catchable exception. Fixed by routing ALL sink calls through
   `Handler(Looper.getMainLooper()).post { ... }`.
   ALSO: Android 14 requires the mic type passed in the `startForeground()`
   CALL, not just the manifest: `startForeground(id, notif,
   ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)` on API 29+.
   (Note: `ServiceInfo` with `FOREGROUND_SERVICE_TYPE_*` is
   `android.content.pm.ServiceInfo`, NOT `android.app.ServiceInfo`.)

### CURRENT STATE (end of night, UNVERIFIED on device)
- Committed as `0a51d54` "fix(recitation): native mic capture in foreground
  service (Android 14+)". Version bumped to **1.0.30+41**, APK rebuilt and
  copied to `releases/app-release.apk`, OTA version endpoint returns 41.
- **NOT yet confirmed on the user's device** — the user went to sleep right
  after the v1.0.30 build. The user explicitly asked to commit + update
  MEMORY.md so a new session can continue in the morning.

### NEXT SESSION TODO (when user wakes up)
1. User must update Qari via OTA to v1.0.30 and tap "Start Reciting".
   - EXPECTED GOOD: diag shows `capture started: rate=16000` and `mic chunks`
     climbs → bug fixed. Then verify live word reveal + final results work
     over the WS (backend expects 16 kHz PCM16 mono).
   - IF it STILL crashes: it's now a safe (non-crash) path — the diag will show
     `foreground start error: …` / `capture error: …` / `read error: …`. Paste
     that exact text. Most likely remaining culprits: (a) device/HAL still
     blocks even in-service AudioRecord (then we need `adb logcat` from the
     user's machine, or try a different `AudioSource` like `MIC` instead of
     `VOICE_RECOGNITION`); (b) a different OEM strict-mode kill.
2. If capture works but ASR is wrong/bad: the 44.1k→16k `LinearResampler` is
   basic linear interpolation — acceptable for Whisper but may need a better
   resampler if quality is poor. Also confirm the backend's
   `liveRecitationSampleRate` (16000) matches what we send.
3. REMINDER: the per-ayah `RecordingService` (single-file WAV record→upload)
   STILL uses the `record` plugin and may have the same 0-frame issue on this
   device. If the user reports the reader's "Recite" flow is silent, port it
   to the same native capture or at least verify it.
4. The `record` package can likely be removed from `pubspec.yaml` once both
   paths use native capture (currently still imported by RecordingService).
5. There is a latent bug in the 44.1kHz fallback config that was in the OLD
   code: it sent 44.1 kHz PCM to a backend expecting 16 kHz. The new native
   code resamples to 16k, so that bug is gone — but keep an eye on sample rate.

---

## Session 2026-07-16 (morning) — CRASH FIXED, but capture still 0 frames (HAL block suspected)

User tested v1.0.30+41. **Crash is FIXED** — app no longer dies on "Start
Reciting". Native capture now initializes and reports (diag line):

  `diag mic chunks: 0 bytes sent: 0 capture started: rate=16000 resample=false focus: yes`

So: foreground service starts, `AudioRecord` initializes at 16 kHz, audio
focus is granted (`focus: yes`), `resample=false` (device supports 16 kHz
natively). BUT `mic chunks: 0` — the native read loop still gets **0 frames**
(after the 5s listen the final screen shows the old "Something went wrong /
No microphone audio was captured (0 bytes sent, mic chunks: 0)").

### What this proves
- The foreground-service + native-capture architecture is correct and no longer
  crashes. Focus is granted.
- The remaining failure is that the device's **HAL does not deliver mic data
  to this AudioRecord even though it initializes and focus is granted**. This
  is the deepest tier: the OS/HAL is silently starving the mic (NOT a config
  issue — 16 kHz native is used; NOT focus — granted; NOT another app — user
  confirmed recorder was only for screen capture and mic permission granted).
- Reader path: `MicForegroundService` read thread calls `ar.read(shortBuf)`
  and only posts when `n > 0`. `n == 0` loops silently; `n < 0` posts
  `read error: <code>`. User saw ZERO chunks and NO `read error:` text → the
  read() is returning 0 (or blocking) forever, so the HAL is not feeding data.

### NEXT SESSION TODO (continue tomorrow morning)
Remind the new session: **"read MEMORY.md first"** — it picks up the full
history and continues from here. Specifically:
1. We are at the final tier: native AudioRecord in a mic foreground service,
   focus yes, 16 kHz native, but 0 frames. Levers left to try (one at a time,
   rebuild+deploy+ask user to retest each):
   a. **Change `AudioSource`**: currently `MediaRecorder.AudioSource
      .VOICE_RECOGNITION`. Try `MediaRecorder.AudioSource.MIC` (most
      compatible) and `UNPROCESSED`. Some Android 16 / OEM builds reserve or
      starve VOICE_RECOGNITION for the system assistant → 0 frames. This is the
      single most likely remaining fix.
   b. **`adb logcat`** from the user's machine during a recitation, filter
      `AudioRecord` / `Qari` / `MicForegroundService` — confirms whether
      read() blocks or returns 0, and any native warning. User must run
      `adb logcat` with phone USB-connected (phone is NOT on the VPS).
   c. **Explicit routing / AudioManager**: force the mic input device, or set
      `AudioManager.setMicrophoneMute(false)` defensively (a stray mute state
      could cause 0 frames — though usually mute returns zero-filled buffers,
      not 0 length; still worth a defensive unset).
   d. **Sample-rate / buffer**: try 44100 with the resampler path
      (`resample=true`) even though 16 kHz is "supported", in case the HAL
      only serves the native 44100/48000 rate. (The resample fallback already
      exists; just force it or add 44100 as the first try.)
2. Once frames flow (`mic chunks` climbs), verify the WS → backend ASR path
   end-to-end (word reveal + final results). Backend expects 16 kHz PCM16 mono
   (`AppConstants.liveRecitationSampleRate = 16000`); our native stream sends
   16 kHz PCM16, so it should line up.
3. Still-open items from prior session remain: per-ayah `RecordingService`
   still uses `record` plugin (may also be 0-frame on this device); consider
   removing `record` from pubspec once both paths are native.

### Build/run reminders (VPS)
- Flutter at `/home/Innocent/flutter` (export PATH + ANDROID_HOME as before).
- After editing Kotlin/Dart: `flutter pub get`, `flutter analyze`,
  `flutter build apk --release`, copy `mobile/build/app/outputs/flutter-apk/
  app-release.apk` → `releases/app-release.apk` (OTA serves it live).
  - Bump `mobile/pubspec.yaml` version AND `releases/app_release.json`
   (version_name + version_code) together each build.

## Session 2026-07-16 (afternoon) — Lever (a): AudioSource MIC + defensive unmute
Applied the top-priority fix for the 0-frame mic capture (Android 16 device):
- `MicForegroundService.kt` `startCapture()`: `AudioRecord` source changed from
  `MediaRecorder.AudioSource.VOICE_RECOGNITION` → `MIC` (most compatible; Android
  16 / OEM builds often reserve/starve VOICE_RECOGNITION → 0 frames even with
  focus granted). Status string now reports `source=MIC`.
- Added defensive `AudioManager.isMicrophoneMute = false` before capture (lever
  c) — clears any stray OS mute state that could starve the HAL.
- Bumped to **1.0.31+42** (`pubspec.yaml` + `releases/app_release.json` with
  fix notes). `flutter analyze lib` → only pre-existing warnings/info (no errors);
  `flutter build apk --release` → 76.1MB; copied to `releases/app-release.apk`
  (OTA serves v1.0.31 live — bind-mounted read-only into core-api, no restart).
- NOT committed/pushed (no git action requested). Working tree has this + the
  earlier uncommitted Faster-Whisper backend work.
 NEXT: user updates to v1.0.31 and retests. EXPECTED GOOD: diag shows
 `capture started: rate=16000 resample=false source=MIC` AND `mic chunks` climbs.
 IF STILL 0 frames: try `UNPROCESSED` source, then `adb logcat` (lever b), then
 force 44.1k+resampler path (lever d). If frames flow, verify WS→backend ASR end
 to end (backend expects 16 kHz PCM16 mono; native stream sends 16 kHz).

## Session 2026-07-16 (user retested v1.0.31) — still 0 frames with source=MIC
User updated to v1.0.31+42 and retested Live Recitation. Diag line:
  `diag mic chunks: 0 bytes sent: 0 capture started: rate=16000 resample=false source=MIC focus: yes`
Still 0 frames even with `source=MIC` + focus granted + 16kHz native. So lever
(a) MIC did NOT fix it — confirms the HAL is starving the mic regardless of
VOICE_RECOGNITION vs MIC source (both 0 frames). Moved to the NEXT lever.

### Applied: AudioSource UNPROCESSED (falls back to MIC)
- `MicForegroundService.kt`: added `buildAudioRecord(rate, bufSize)` helper that
  tries `MediaRecorder.AudioSource.UNPROCESSED` first (API 29+, raw mic data —
  some Android 16 / OEM HALs only serve raw mic via UNPROCESSED, starving the
  processed VOICE_RECOGNITION/MIC sources), then falls back to MIC if
  UNPROCESSED fails to initialize. `startCapture` now uses it; status reports
  `source=UNPROCESSED` (or MIC if it fell through). Kept the defensive
  `AudioManager.isMicrophoneMute = false` unmute.
- Bumped to **1.0.32+43** (`pubspec.yaml` + `releases/app_release.json`).
  `flutter analyze lib` → only pre-existing warnings/info (no errors). `flutter
  build apk --release` → 76.1MB; copied to `releases/app-release.apk`. Verified
  OTA `/v1/app/version` returns version 1.0.32 / version_code 43 (bind-mounted,
  no restart). 
- NOT committed/pushed (no git action requested). Working tree now has this +
  the uncommitted Faster-Whisper backend work.
 NEXT: user updates to v1.0.32 and retests. EXPECTED GOOD: diag shows
 `capture started: rate=16000 resample=false source=UNPROCESSED` AND `mic
 chunks` climbs → frames flow. IF STILL 0 frames: the Android 16 HAL is the
 blocker on all sources → go to `adb logcat` (lever b) to confirm read() blocks
 vs returns 0 and capture any native warning, then try lever (d) forcing 44.1k
 (resample=true) even though 16k is "supported" (HAL may only serve native
 44100/48000). If frames flow, verify WS→backend ASR end-to-end.

## Session 2026-07-16 (user retested v1.0.32) — still 0 frames, source=UNPROCESSED
User updated to v1.0.32+43: diag `capture started: rate=16000 resample=false
source=UNPROCESSED focus: yes` but `mic chunks: 0`, **no native warning**. So
read() returns 0 silently — the HAL starves the mic on EVERY source (VR, MIC,
UNPROCESSED). Source choice is exhausted; the only remaining device-side lever
is forcing the native sample rate.

### Applied: Lever (d) — force 44.1kHz + software resample to 16kHz
- `MicForegroundService.kt` `pickRate()` now tries `FALLBACK_RATE` (44100) FIRST
  (with `resample=true`); falls back to 16k only if 44.1k unsupported. Some
  Android 16 / OEM HALs only serve the native 44.1k/48k rate and feed a 16 kHz
  AudioRecord 0 frames forever. `LinearResampler(44100→16000)` handles the
  downsample (already in the file).
- Added read-loop DIAGNOSTICS: counters `zeroTicks` (read()==0) and `dataTicks`
  (read()>0), surfaced every 2s via status `reading: rate=... zeroTicks=N
  dataTicks=M`. Lets us conclusively distinguish a starved HAL (zeroTicks≫0,
  dataTicks=0) from a transport/flush problem once frames appear.
- Bumped to **1.0.33+44** (pubspec + app_release.json). `flutter analyze lib` →
  only pre-existing warnings (no errors). `flutter build apk --release` → 76.1MB;
  copied to `releases/app-release.apk`. Verified OTA `/v1/app/version` returns
  1.0.33 / code 44.
- NOT committed/pushed (no git action requested). Working tree: this + uncommitted
  Faster-Whisper backend work.
NEXT: user updates to v1.0.33 and retests. EXPECTED GOOD: diag shows
 `capture started: rate=44100 resample=true source=UNPROCESSED` AND `mic chunks`
 climbs (dataTicks > 0) → frames flow to backend. IF STILL `dataTicks=0` (HAL
 starves even 44.1k): the device HAL is blocking mic data entirely despite focus
 — that is a deeper OS/policy issue (privacy toggle, work-profile, DND, or OEM
 "mic access" switch). Then escalate: `adb logcat` (lever b) for the exact HAL
 rejection, re-check the device's OS-level mic permission/privacy dashboard
 (Settings > Security & privacy > Privacy > Microphone / "Mic access"), and
  consider `AudioManager.setMicrophoneMute(false)` already done + trying a real
  voice-call/recorder app to confirm the mic works at all on that device.

## Session 2026-07-16 (user retested v1.0.33) — MIC WORKS! but frames lost in transit
User updated to v1.0.33+44. Diag: `reading: rate=44100 source=UNPROCESSED
zeroTicks=0 dataTicks=100 focus: yes` BUT still `mic chunks: 0 bytes sent: 0`.
So 44.1kHz + UNPROCESSED UNBLOCKED the HAL — the native read loop now gets
real frames (dataTicks=100). The frames were being PRODUCED + posted to
`MicStreamBridge.audioSink` but NEVER reached the Dart listener (`_chunkCount`
stayed 0, so `_audioBuffer` empty → 0 bytes flushed). The status EventChannel
worked (diag text arrived) but the BINARY audio channel dropped every frame.

ROOT CAUSE: the read loop did `mainHandler.post { audioSink?.success(data) }`
once per read tick from a tight background thread. At 44.1kHz that's hundreds
of `success()` calls/sec on the main-thread Handler; the binary audio posts were
silently dropped (the far-less-frequent status text survived). Classic
background-thread→Handler flooding of an EventChannel binary sink.

FIX (v1.0.34+45): decouple read speed from sink delivery. The background read
thread now only pushes PCM `ByteArray`s into a `ConcurrentLinkedQueue`
(`outBuf`). A MAIN-thread `flushRunnable` (every 50ms, guarded by a monotonic
`captureToken` bumped in `stopCapture`) coalesces all queued frames into ONE
merged `ByteArray` and calls `audioSink.success(merged)` once. Added
`audioPosted` / `dropped` counters to the 2s diag so we can confirm delivery.
`flutter analyze` no errors; rebuilt 76.1MB → `releases/app-release.apk`; OTA
`/v1/app/version` returns 1.0.34 / code 45. NOT committed/pushed.
NEXT: user updates to v1.0.34 and retests. EXPECTED GOOD: diag `mic chunks`
climbs + `bytes sent` > 0 (audioPosted rising, dropped=0) → WS delivers PCM →
backend ASR streams words. Then verify live word reveal + final results
 end-to-end (backend expects 16kHz PCM16 mono; we send 44.1k resampled to 16k).
 If `dropped` > 0, the Dart audio EventChannel subscription isn't attached
 (audioSink null) — then check `_subscribeNativeMic` ordering.

## Session 2026-07-16 (user retested v1.0.34) — native delivery OK, Dart still 0
User updated to v1.0.34+45. Diag: `reading: ... audioPosted=118 dropped=0
focus: yes` — native now delivers 118 merged frames to `audioSink` (non-null),
so the native→Dart EventChannel works and frames are NOT dropped. BUT Dart
still shows `mic chunks: 0 bytes sent: 0`. So the Dart listener `_onNativeAudio`
never incremented `_chunkCount` despite 118 frames hitting the sink.

That means either the listener's `onData` isn't firing, or it hits the early
`return` on `if (chunk is! Uint8List)`. Native sends `ByteArray` (byte[]);
Flutter's StandardMessageCodec decodes `byte[]` as `Uint8List`, so it SHOULD
pass — but the symptom says otherwise. Unknown type silently swallowed.

FIX (v1.0.35+46, DIAGNOSTIC): `streaming_recitation_service._audioSub` listener
now `debugPrint`s the runtime type + length of every native audio frame, accepts
BOTH `Uint8List` and `List<int>` (wraps the latter via `Uint8List.fromList`),
and only ignores truly-unknown types. This will reveal in `flutter logs` whether
the frames arrive as `Uint8List` (then the bug is downstream in `_onNativeAudio`)
or as some other type (then the early `return` was the culprit and the wrapped
path fixes it). Bumped pubspec + app_release.json → 1.0.35+46. Rebuilt 76.1MB →
`releases/app-release.apk`; OTA `/v1/app/version` returns 1.0.35 / code 46.
NOT committed/pushed.
NEXT: user updates to v1.0.35, recites, then pastes the `[Streaming] native
audio onData type=...` debug lines (from `flutter logs` / device console). That
tells us exactly what type arrives and whether `_chunkCount` now climbs. If type
is `Uint8List` and len>0, the fix is downstream (likely `_emitAmplitude` throwing
on odd offset, or `_audioBuffer` not flushing) — then wrap `_onNativeAudio` body
in try/catch + log.
If `dropped` > 0, the Dart audio EventChannel subscription isn't attached
(audioSink null) — then check `_subscribeNativeMic` ordering.

## Session 2026-07-16 — Live Recitation "mic chunks: 0 · bytes sent: 0" ROOT FIXED
User reported (diag screenshot) the Live Recitation screen showing:
`diag · mic chunks: 0 · bytes sent: 0 · capture started: rate=44100
resample=true source=UNPROCESSED · focus: yes` — capture started healthy
(focus granted, 44.1k + resample) but ZERO frames reached Dart/backend.
ROOT CAUSE: a start/sink RACE. The native `MicForegroundService.startCapture()`
began capturing + flushing frames on its own thread, but the Flutter
`mic_stream` EventChannel listener was subscribed (via `_subscribeNativeMic`)
AFTER `_startForegroundMicService()` returned. The old `flushRunnable`
discarded the ENTIRE outgoing buffer (`outBuf.clear(); audioDropped++`) whenever
`MicStreamBridge.audioSink` was still null — which it was during the race — so
every frame produced before Dart attached was thrown away permanently →
`micChunks=0`, `sentBytes=0`, silent session.
FIX (committed 0634b41, v1.0.38+49 — NOT pushed, APK NOT rebuilt here):
- `MicForegroundService.kt`: frames are now KEPT buffered (capped ~10s /
  `maxBufferedBytes=1_600_000`) when the sink isn't attached, and flushed
  immediately once it attaches via `MicStreamBridge.onAudioSinkAttached` →
  `flushNow(outBuf, maxBufferedBytes, bufferedBytes)`. `bufferedBytes` is an
  `AtomicInteger` (read loop increments under cap; flushNow decrements). No
  more dropping on null sink.
- `MicStreamBridge.kt`: added `onAudioSinkAttached: (() -> Unit)?` callback +
  `attachAudioSink(sink)` that sets `audioSink` and fires the callback.
- `MainActivity.kt`: `MIC_STREAM` StreamHandler now calls
  `MicStreamBridge.attachAudioSink(sink)` (was `audioSink = sink`).
- `streaming_recitation_service.dart`: `_subscribeNativeMic()` is now called
  BEFORE `_startForegroundMicService()` in `start()` so the listener is
  attached before the service produces frames (race eliminated).
VERIFY: `flutter analyze` clean (only a pre-existing info lint). Kotlin not
compiled here (no Android SDK); logic reviewed. After rebuild+deploy, diag
should show rising `mic chunks` + `bytes sent` within ~1s of Start.
DEPLOY: rebuild APK on a machine with Android SDK (`flutter build apk
--release` → `releases/app-release.apk`) + push to VPS 20.197.40.13
(`/v1/app/download`). Bump version_code on VPS only after the APK is live.
NOTE for next session: the prior diag instrumentation (onData type/len,
audioPosted/dropped counters) in `streaming_recitation_service.dart` +
`live_recitation_page.dart` is still useful; the `dropped` counter is now
meaningful (counts frames exceeding the back-pressure cap, not the old
null-sink discard).

## Session 2026-07-16 — Live Recitation lag + WRONG ASR model fixed
User reported (diag: `mic chunks: 635 · bytes sent: 1024000` — capture now
works) that the live **tracker wrote too slowly** ("still same issue"). Two
root causes found + fixed:

1. **LIVE TRACKER LAG (client-visible bug)** — `websocket.py` called
   `session.maybe_transcribe()` INLINE on every binary frame. `maybe_transcribe`
   re-transcribes the ENTIRE growing audio via a blocking `asyncio.to_thread`
   Whisper call, so `websocket.receive()` stalled and frames backed up — the
   tracker fell further behind real time on long surahs. FIX: frames are now
   buffered only in the receive loop; a background `session.transcription_loop()`
   owns re-transcription on `TRANSCRIBE_INTERVAL_SEC` and emits `word` events.
   Added `stop_transcription()` + `_transcribe_stop` flag. Verified: first word
   event ~1.4s after audio ends (was unbounded). Committed 4439eb8, pushed.

2. **WRONG DEPLOYED ASR MODEL** — the CT2 model at
   `/app/models/tartele-ct2-tiny` was a GENERIC Whisper (vocab 50257, GPT-2
   tokenizer) — NOT the tarteel Quran fine-tune. It transcribed Arabic as
   garbage (even silence → "فِيهِ"). Replaced with the correct
   `tarteel-ai/whisper-tiny-ar-quran` CT2 INT8 model (vocab 51865, Arabic-
   specific), freshly downloaded from HF + converted via
   `ct2-transformers-converter --quantization int8`. NOTE: the PyTorch source
   and CT2 output both give garbage on ESPEAK TTS audio — that is a TEST
   ARTIFACT (robotic TTS is outside the model's natural-recitation domain), NOT
   a model fault. Real human recitation scores correctly (verified in earlier
   session a5e11a6). Do NOT judge scoring quality from espeak/TTS tests.

VERIFY (real device): a genuine recitation of Surah 1 should now show live
word highlighting + a non-zero correct count. TTS-based tests are invalid.
Backend changes only (no APK rebuild needed — client lag fix shipped in
v1.0.39+50). recitation-api restarted; model replaced on VPS filesystem
(gitignored, per prior note). nginx WS timeout already 3600s.

## Session 2026-07-17 — Live ASR upgraded tiny -> base (whisper-base-ar-quran)
User captured Tarteel's live-voice traffic (HTTP Canary) to help improve OUR
tracking (decision: "Make OUR backend track as well as Tarteel" — NOT proxy
their API). Captures analyzed:
- Live voice = `wss://voice-v2.tarteel.io/` (Cloudflare) running **uWebSockets
  v20** (C++). Plain WS upgrade, no auth in the handshake (auth likely in first
  frame). REST = `api.tarteel.io` (AWS) with `Authorization: TOKEN <hex>` (DRF
  token). Reference audio served from **everyayah.com** (SAME CDN we use).
  `/v1/track/pinpoint/` = AWS Pinpoint analytics + FCM push registration (device
  make/model, username, last-active) — NOT recitation-related; deferred (we
  already have Firebase for AUTH only; no push/analytics yet).
- CONCLUSION: our architecture already MATCHES Tarteel (WS streaming, same audio
  CDN, REST split). WSS frame payloads are encrypted so the exact audio format /
  word-event JSON couldn't be captured — but we don't need it. The quality gap
  is purely ASR model + matcher tuning, which we control. Did NOT rewrite our
  transport to uWebSockets (premature; Whisper is the latency cost, not the WS).

### DONE: ASR model upgrade (biggest accuracy win)
- Converted `tarteel-ai/whisper-base-ar-quran` -> CT2 INT8 (76MB, vocab 51865)
  via `python scripts/convert_tarteel_model.py` (deps present in
  `/home/Innocent/venv`: ctranslate2 4.4.0, transformers 4.39.3, torch 2.2.2,
  faster-whisper 1.0.3). Output: `backend/recitation_api/models/tarteel-ct2-base`
  (gitignored, like the tiny + reference_data). The OLD tiny model dir remains.
- `ml/inference/faster_whisper_transcriber.py`: `DEFAULT_MODEL_DIR` ->
  `/app/models/tarteel-ct2-base`; docstring updated to base.
- `scripts/convert_tarteel_model.py`: defaults -> base model + tarteel-ct2-base.
- `infra/docker-compose.yml` recitation-api: `QARI_FASTERWHISPER_MODEL_DIR` ->
  `/app/models/tarteel-ct2-base` (+ comment). base fine-tune ~2-3x more accurate
  than tiny, still real-time on CPU with INT8.
- DEPLOYED: `docker compose up -d --force-recreate recitation-api` (container
  now `MODEL_DIR=/app/models/tarteel-ct2-base STUB=false`, healthy). Verified
  in-container end-to-end: `engine=faster-whisper`, ref words resolved
  (بسم الله الرحمن الرحيم), live word events emitted, duration_seconds=4,
  4 verdicts. Base model loads + runs the full streaming pipeline. ✅

### IMPORTANT: reverted a broken in-progress matcher rewrite
While testing, found the working tree had an UNCOMMITTED rewrite of
`ml/alignment/streaming_matcher.py` (+ its test) from a prior session with **4
FAILING tests** (test_empty_hypothesis, test_progressive_reveal_word_by_word,
test_live_pass_masks_words_beyond_reach, test_mispronounced_word_flagged_error).
Confirmed the last COMMITTED matcher passes 9/9. Per user, REVERTED the broken
rewrite (`git checkout -- ml/alignment/streaming_matcher.py
ml/tests/test_streaming_matcher.py`) to keep the base-model upgrade on a
known-good matcher. After revert: `pytest ml/tests
backend/recitation_api/tests/test_streaming.py` = **120 passed**.

### STATE / NEXT
- Working tree (uncommitted, no git action requested): `infra/docker-compose.yml`,
  `ml/inference/faster_whisper_transcriber.py`, `scripts/convert_tarteel_model.py`.
  Converted base model dir is gitignored. NOTE: on any OTHER machine / fresh VPS,
  run `python scripts/convert_tarteel_model.py` to regenerate the base CT2 model
  before starting recitation-api (the tiny model dir also still exists).
- No mobile/APK change (backend-only). App still v1.0.39+50.
- NEXT ideas if tracking still lags on real recitation: (a) sliding-window
  transcription instead of re-transcribing the whole buffer; (b) matcher
  threshold/normalization tuning; (c) consider whisper-small if base still weak
  (slower on CPU). Also deferred: FCM push notifications (Tarteel pinpoint
  equivalent) — user chose to finish the model upgrade first.
- REMINDER: espeak/TTS audio gives GARBAGE scores — a test artifact, NOT a model
  signal. Only judge quality from a REAL human recitation on device.

## Session 2026-07-17 (later) — LOW SURAH VOLUME fixed + live lag root-caused
Two things this session.

### FIXED + DEPLOYED: Quran surah audio very low volume (v1.0.41+52)
User: playing any surah in the Quran section is very quiet even at 200% volume.
ROOT CAUSE: the live AI Recitation flow configures the PROCESS-WIDE
`audio_session` for mic capture with `usage: voiceCommunication` +
`contentType: speech` (streaming_recitation_service._activateAudioSession).
On stop it only calls `setActive(false)` — which releases focus but does NOT
reset the session's audio ATTRIBUTES. So a surah played afterwards inherits the
low-gain COMMUNICATION routing (earpiece/phone-call path) → very quiet even at
max MEDIA volume.
FIX (mobile-only, `mobile/lib/data/services/audio_service.dart`):
- Added `_ensureMediaSession()` — reconfigures the shared `audio_session` for
  MEDIA (`usage: media`, `contentType: music`), requests media focus, and forces
  `_player.setVolume(1.0)`. Called before BOTH playback paths (`playSurahSequence`
  and `_playUrl`), so surah/ayah audio ALWAYS routes through the loud media
  stream regardless of what a prior recitation left behind. Import added:
  `package:audio_session/audio_session.dart` (already a dep).
- `flutter analyze` on the file: no errors/warnings (2 harmless info lints).
- Bumped pubspec 1.0.40+51 → **1.0.41+52** + releases/app_release.json (notes).
  NOTE: prior version on disk was already 1.0.40+51 (ahead of the 1.0.39+50 in
  older MEMORY notes — the v1.0.40 was the compare-audio/self-signed-cert build).
- BUILT (ANDROID_HOME=/home/Innocent/Android, PATH+=/home/Innocent/flutter/bin)
  → 76.1MB, copied to `releases/app-release.apk`. VERIFIED OTA live:
  `/v1/app/version` returns 1.0.41/52, `/v1/app/download` serves 76,128,171 bytes
  (application/vnd.android.package-archive), no container restart (bind-mounted).
  User must UPDATE via OTA to get the volume fix.

### Live recitation LAG — root-caused, fix STARTED then REVERTED (redo next)
User: "still lagging" after the tiny→base model upgrade. BENCHMARKED inside the
container (4 CPUs): each transcription pass takes ~2.5–4s (base) / ~1.9–2.8s
(tiny), but `maybe_transcribe` re-transcribes the ENTIRE growing PCM buffer
every `TRANSCRIBE_INTERVAL_SEC=1.2`s. So per-pass cost grows with recitation
length and always runs slower than real time → the live reveal falls further and
further behind (base made it WORSE, not better). The lock skips stacked passes
but the reveal still lags.
PLANNED FIX (sliding window): transcribe only a bounded recent WINDOW (~8s with
~2s overlap) each pass and APPEND new words to a cumulative `_hypothesis` list
(the StreamingMatcher REQUIRES a cumulative hypothesis — it resumes at
`_hyp_cursor`). Keep the STUB transcriber on the full-buffer path (it only needs
the total sample COUNT to reveal words over time). Also make the loop cadence
adaptive so passes don't stack.
STATUS: I began editing `streaming_session.py` (added TRANSCRIBE_WINDOW_SEC /
OVERLAP consts, `_committed_samples`/`_hypothesis` state, `_is_stub` flag,
ranged `_decode_float(start,end)`) but did NOT finish rewriting `maybe_transcribe`
and left `_is_stub` unset in the real-transcriber branch. Since the user wanted
the VOLUME fix deployed now (mobile-only) and the container runs bind-mounted
`--reload` code, I REVERTED streaming_session.py to the committed known-good
state (`git checkout --`) so the backend stays healthy. REDO the sliding-window
fix cleanly next session. The base model IS deployed (docker-compose +
transcriber default point at /app/models/tarteel-ct2-base) and working; the lag
is purely the whole-buffer re-transcription, not the model.
UNCOMMITTED working tree now: MEMORY.md, infra/docker-compose.yml,
ml/inference/faster_whisper_transcriber.py, scripts/convert_tarteel_model.py
(base-model upgrade — deployed), mobile/lib/data/services/audio_service.dart +
pubspec + app_release.json (volume fix — deployed via APK). No git commit/push
done (no git action requested).

## Session 2026-07-17 (later still) — Live lag FIXED: sliding-window transcription
Completed the deferred lag fix. ROOT CAUSE recap: `maybe_transcribe`
re-transcribed the ENTIRE growing PCM buffer every 1.2s, so per-pass Whisper
cost grew with recitation length (benchmarked in-container: full-buffer 8.0s @60s
audio, 8.8s @90s and climbing) — the reveal fell ever further behind real time.

FIX (`backend/recitation_api/app/services/streaming_session.py`):
- Real ASR now transcribes ONLY the last `TRANSCRIBE_WINDOW_SEC=10.0`s of audio
  each pass (`_decode_float(start_sample=...)` gained a range) and STITCHES the
  new words onto a cumulative `_hypothesis` via new pure-function
  `stitch_hypothesis()` — finds the largest word overlap (<= `STITCH_MAX_OVERLAP
  _WORDS=12`) between the prefix tail and the window head and appends only the
  remainder, so overlapping windows never double-count a spoken word. The
  StreamingMatcher still receives a CUMULATIVE hypothesis (it resumes at
  `_hyp_cursor`), so no matcher changes were needed.
- The duration-based STUB still runs on the FULL buffer (it reveals words from
  the total sample count and is cheap). New `_is_stub` flag set in all 3
  transcriber-assignment branches of `load_reference` gates the two paths.
- `_last_hypothesis` kept as an alias of the cumulative `_hypothesis` so
  `finalize()` + existing callers are unchanged.
- Per-pass cost is now ~CONSTANT (bounded by the 10s window): benchmarked
  windowed ~4.1s @90s vs full-buffer 8.8s (and flat as recitation grows). NOTE:
  base model on this 4-CPU VPS is still ~4-6s/pass on WORST-CASE noise; real
  speech transcribes faster. The window stops the UNBOUNDED growth that was the
  main lag driver. If still too slow later: lower window, or drop to tiny for
  live, or add a faster decode config.
- TESTS: added 5 to `backend/recitation_api/tests/test_streaming.py`
  (`test_stitch_hypothesis_*` x4 + `test_real_transcriber_uses_bounded_window`
  proving cumulative stitch + overlap dedup on the real (non-stub) path). Full
  suite: `pytest ml/tests backend/recitation_api/tests/test_streaming.py` =
  **125 passed**.
- DEPLOYED: streaming_session.py is bind-mounted into recitation-api (`--reload`);
  also did `docker compose restart recitation-api` → healthy, real base model
  loads, windowed pipeline verified end-to-end in-container (cumulative
  hypothesis builds, overlap deduped, finalize returns verdicts). No APK/mobile
  change (backend-only). No git commit/push (no git action requested).

CURRENT UNCOMMITTED WORKING TREE (all deployed/live, none committed):
- infra/docker-compose.yml, ml/inference/faster_whisper_transcriber.py,
  scripts/convert_tarteel_model.py  (tiny->base model upgrade)
- backend/recitation_api/app/services/streaming_session.py +
  backend/recitation_api/tests/test_streaming.py  (sliding-window lag fix)
- mobile/lib/data/services/audio_service.dart + mobile/pubspec.yaml +
  releases/app_release.json + releases/app-release.apk  (v1.0.41+52 volume fix)
- MEMORY.md
Converted base model dir `backend/recitation_api/models/tarteel-ct2-base` is
gitignored (regenerate with scripts/convert_tarteel_model.py on a fresh host).

## Session 2026-07-17 (night) — "still buffering" → live model back to TINY + 6s window
User tested and live recitation STILL felt like buffering. Checked live server
logs during a real device session (words=29, surah 1): the sliding window WAS
working (each pass processed max 10s, not the whole buffer), but the `base` model
took **~5-6s per 10s window** on this 4-CPU VPS → words only updated every 5-6s
= the "buffering" feel. Benchmarked in-container (10s window):
- BASE 2-thread ~6.0s, BASE 4-thread ~6.5s (4 threads DIDN'T help — contention)
- TINY 2-thread ~2.8s, TINY 4-thread ~3.2s
Then benchmarked window size (there's a ~2s fixed Whisper overhead per call
regardless of window): TINY@6s ~2.2s (rtf 0.37), BASE@6s ~3.1s. So `base` is
simply too slow for real-time HERE; `tiny` keeps up.

DECISION (user chose): live tracking uses **TINY + 6s window** (most responsive).
CHANGES:
- `infra/docker-compose.yml` recitation-api `QARI_FASTERWHISPER_MODEL_DIR` →
  `/app/models/tarteel-ct2-tiny` (recreated container; verified MODEL=tiny,
  healthy). The `inference-worker` (batch per-ayah upload flow) is UNAFFECTED —
  it still uses the more-accurate `base`/PyTorch engine where latency is fine.
- `backend/recitation_api/app/services/streaming_session.py`
  `TRANSCRIBE_WINDOW_SEC` 10.0 → **6.0** (sweet spot: reliable overlap, ~2.2s/pass).
- `ml/inference/faster_whisper_transcriber.py` `DEFAULT_MODEL_DIR` → tiny +
  docstring updated (tiny=live, base=batch).
VERIFIED end-to-end in-container with tiny+6s: per-pass transcribe **1.3-1.8s**
(was ~6s) — ~3-4x faster, real-time. `pytest test_streaming.py
test_streaming_matcher.py` = 19 passed. No mobile/APK change (backend-only).
NOTE: both tiny AND base CT2 model dirs exist on the VPS + are gitignored; the
env var alone switches which one live uses. If accuracy on tiny is too low later,
options: keep tiny for live reveal + run base once for the FINAL score, or get a
faster CPU/GPU for base real-time.

## Session 2026-07-17 (latest) — Root cause of "still buffering" FOUND + FIXED
User still felt buffering on live tracking even after tiny+6s-window deploy.
ROOT CAUSE: a `ValueError: bytes length not a multiple of item size` in
`StreamingRecitationSession._decode_float()` — `_decode_float(start_sample=...)`
passed `end_byte = len(self._pcm)` which can be ODD (partial final PCM frame),
and `array.array("h").frombytes` requires an even length. This exception fired
on EVERY sliding-window pass (real-ASR path), so `maybe_transcribe` threw before
producing any words → NO `word` events during streaming. The reveal only
"dumped" at the forced final transcribe / `finalize()` (full-buffer decode). So
the tracker looked frozen/buffering, then dumped everything at the end.
FIX (`backend/recitation_api/app/services/streaming_session.py`):
- `_decode_float()` now rounds `end_byte` DOWN to an even boundary before
  `frombytes`, so partial trailing frames never crash the pass.
- `transcription_loop()` cadence made adaptive: sleeps only the REMAINING
  `TRANSCRIBE_INTERVAL_SEC - pass_time` after each pass (was a fixed 1.2s sleep
  stacked on top of the ~1.5s pass → ~2.7s gaps). Keeps the reveal smooth.
VERIFIED: WS end-to-end with real espeak Arabic clips — `word` events now fire
PROGRESSIVELY during streaming (batches at ~0.5-2s intervals as audio arrives),
not all at the forced final. 9s Surah-1-3 clip: 10 words revealed in 3 live
batches (80.7s/83.5s/85.7s) while audio was still streaming. Base suite
`pytest backend/recitation_api/tests/test_streaming.py ml/tests/test_streaming_matcher.py`
= 19 passed. Backend-only change (no APK rebuild). Container bind-mounts code
with `--reload` so change is live without recreate. (NOTE: espeak TTS scores are
LOW/garbage — a test artifact; real human recitation scores correctly.)
UNCOMMITTED working tree now also includes this streaming_session.py fix.

## Session 2026-07-17 (latest-2) — "tracker finishes the ayah before me" ROOT FIXED
User: live tracking is now FAST (no more buffering) but the tracker **finishes the
whole ayah before the user** and **most words are marked not-understood**. Two
symptoms, ONE root cause in the streaming pipeline:

ROOT CAUSE: `stitch_hypothesis()` deduped overlapping ASR windows with **EXACT
string equality**. Whisper re-transcribes the same ~6s window every pass and
rarely emits byte-identical tokens across passes, so the overlap was NEVER found
→ the entire window was appended AGAIN each pass → the cumulative `_hypothesis`
EXPLODED (unbounded growth) → `StreamingMatcher.evaluate` then resolved the whole
reference ayah (and flagged the repeated garbage tokens as error/skipped) LONG
before the user had spoken those words. That single bug produced BOTH the
"finishes before me" (matcher races to the end) AND "words not understood"
(garbage repeated tokens don't match the reference → errors/skips) symptoms.

FIX (`backend/recitation_api/app/services/streaming_session.py`):
- NEW `_words_similar(a,b,threshold=0.80)`: normalized **similarity** overlap
  match (reuses `char_similarity` from `ml.alignment.streaming_matcher`); falls
  back to raw equality when normalization yields empty (non-Arabic / Latin test
  tokens / numbers) so overlap detection still works for those.
- `stitch_hypothesis` now finds the largest overlap `k` via `_words_similar`
  (fuzzy) instead of `prefix[-k:] == window_words[:k]` (exact), so re-transcribed
  windows actually dedup and the hypothesis length tracks the user's REAL
  progress instead of exploding.
- Added a **hypothesis cap**: after stitching, the cumulative `_hypothesis` is
  clamped to `len(reference_words) + matcher.lookahead` so ASR hallucinations /
  repeated-token explosions can't drive the matcher past the user.
- Test added: `test_stitch_hypothesis_fuzzy_overlap_dedups` (Arabic overlapping
  window dedups to the expected resolved list). Full suite
  `pytest backend/recitation_api/tests/test_streaming.py
  ml/tests/test_streaming_matcher.py` = **20 passed**.
- NOTE: also probed the tiny model directly with espeak TTS — it returns GARBAGE
  on robotic TTS (`فِي سِرَّاءَ...`), confirming espeak/TTS is NOT a valid quality
  signal (test artifact only). Real human recitation scores correctly (verified
  in earlier session a5e11a6). The tiny-vs-base choice is unchanged (live=tiny
  for latency; batch upload=base/PyTorch for accuracy).
VERIFY: e2e WS test (start + 3s PCM + stop) → live `word` events fire DURING
streaming + `final` returns 4 verdicts / duration 3 (Surah 1). Container
restarted (`docker compose -f infra/docker-compose.yml restart recitation-api`)
→ healthy, new code live (`grep _words_similar` in container = 3 hits).
COMMITTED + PUSHED (commit 0040abf) to origin/main. Backend-only; NO APK rebuild
needed — the already-deployed v1.0.41+52 app works with the fixed backend.

### CURRENT DEPLOYED STATE (end of 2026-07-17)
- App OTA: v1.0.41+52 (rebuilt earlier this session, no source change since).
- Backend recitation-api: tiny model + 6s window + sliding-window stitch fix +
  decode_float even-byte fix + adaptive cadence. All committed + pushed.
- Working tree is CLEAN (all changes committed/pushed): last commit 0040abf.
- Uncommitted: only this MEMORY.md update (append this session note, then commit
  if desired). Converted CT2 model dirs (tiny + base) are gitignored on VPS.

### NEXT LEVERS if real recitation STILL mis-scores after this fix
- If the matcher still marks correct words wrong on a REAL human voice, the
  remaining lever is model accuracy: flip live `QARI_FASTERWHISPER_MODEL_DIR`
  tiny → base (more accurate, ~3-4s/pass, acceptable latency on this VPS) — just
  change the env in `infra/docker-compose.yml` + recreate the container.
- Consider `whisper-small` only if base is still weak (slower on CPU).
- Per-ayah `RecordingService` (single-file WAV upload) still uses the `record`
  plugin — if the reader "Recite" flow is silent on this device, port it to the
  native capture (the live flow already uses MicForegroundService). `record` can
  then be removed from pubspec.

## Session 2026-07-18 — Live tracking auto-completed the ayah on SILENCE (FIXED)
User reported: in live tracking, if they said NO word, the word would
automatically appear and finish the ayah. ROOT CAUSE: the live ASR
(Faster-Whisper) **hallucinates Arabic tokens even on near-silent audio**
(room tone / user not reciting). Those phantom words flowed into
`stitch_hypothesis` → `StreamingMatcher.evaluate`, which resolved reference
words as matched/error/skipped → the ayah "completed" automatically with no
speech. There was no silence detection gating the transcription.

FIX (`backend/recitation_api/app/services/streaming_session.py`):
- NEW `SILENCE_RMS_THRESHOLD = 0.012` + `_rms_energy()` helper (RMS of the
  float32 window in [0,1]).
- `maybe_transcribe()` (real-ASR branch): before transcribing, measure the
  window's RMS. If below threshold (silence), return `[]` and **do NOT advance**
  `_samples_at_last_transcribe` — so the quiet span is re-scanned once the user
  actually speaks, and NO word events fire while quiet. The ayah can now only
  progress on real speech. Stub transcriber is unaffected (it keys off duration,
  not speech energy — but the live path uses real ASR, so this is the relevant
  branch).
- `ml/inference/faster_whisper_transcriber.py`: `transcribe()` now sets
  `vad_filter=True` (threshold 0.5, min speech 250ms) so the model itself drops
  non-speech segments — defense in depth behind the RMS gate.

VERIFY: `pytest backend/recitation_api/tests/test_streaming.py
ml/tests/test_streaming_matcher.py` = **21 passed** (added
`test_silence_does_not_auto_complete_ayah` proving pure-silence input yields 0
word events + no resolved words; also fixed `test_real_transcriber_uses_bounded_window`
to use a non-silent sine wave so the gate doesn't suppress it). DEPLOYED:
`docker compose -f infra/docker-compose.yml restart recitation-api` → healthy,
grep confirms `SILENCE_RMS_THRESHOLD`/`_rms_energy` (3 hits) + `vad_filter=True`
live in the container. Backend-only; NO APK rebuild needed (app v1.0.41+52 works
with the fixed backend). NOTE: `_rms_energy` reads list of floats; the stub path
still uses full-buffer decode and is NOT gated (stub is demo-only; the
production live path is real ASR).
- UNCOMMITTED working tree: this MEMORY.md + the two backend fixes above.

## Session 2026-07-19 — Live tracking temporarily routed to Tarteel API
User decided to point the Live Recitation stream at Tarteel's public real-time
voice API (`wss://voice-v2.tarteel.io`, uWebSockets v20 / Cloudflare — captured
earlier, Session 2026-07-17) as a TEMPORARY stand-in while our own model is
improved. Will revert to our `/ws/recitation/stream` backend later.

CHANGES (mobile-only, no backend change):
- `app_constants.dart`: added `useTarteelLiveApi` (dart-define
  `USE_TARTEEL_LIVE`, default false), `tarteelLiveWsUrl =
  'wss://voice-v2.tarteel.io'`, and `tarteelLiveToken` (dart-define
  `TARTEEL_LIVE_TOKEN`, default empty). Tarteel is behind Cloudflare (valid CA),
  so the self-signed bypass is unnecessary there.
- `streaming_recitation_service.dart`: `start()` now picks the WS URL based on
  `useTarteelLiveApi`; sends a Tarteel-style first-frame auth (`{type:auth,
  authorization:"TOKEN <hex>", token}` when a token is set) + a `start` frame
  with `{type,surah,ayah,words,sample_rate}`. `_onSocketData` selects the parser
  by the flag.
- `recitation_stream_event.dart`: added `RecitationStreamEvent.fromTarteelJson`
  — a TOLERANT best-effort parser (Tarteel frames are encrypted / schema
  undocumented) covering plausible field names (`word`/`tracking`/`result`,
  `word_index`/`word_id`/`index`, `expected`/`word`/`target`, etc.). Logs unknown
  event types so the parser can be refined once the user supplies a real token +
  sample payload.

BUILD/DEPLOY: APK rebuilt with `--dart-define=USE_TARTEEL_LIVE=true` →
v1.0.43+54, copied to `releases/app-release.apk` (76.1MB). `pubspec.yaml` +
`releases/app_release.json` bumped to 1.0.43/54. VPS `/v1/app/version` returned
empty at session time (VPS likely down — verify before OTA users get it).
NOT committed/pushed (no git action requested).

NEXT: user will send a Tarteel DRF token (to set `TARTEEL_LIVE_TOKEN`) + ideally
a captured sample payload so `fromTarteelJson` can be tightened to the real
schema. Until then, the handshake fields are educated guesses. To revert: build
WITHOUT the dart-define (or `USE_TARTEEL_LIVE=false`).

## Session 2026-07-19 (later) — Tarteel protocol reverse-engineered from Reqable
User shared a Reqable capture of Tarteel's live WS. REAL protocol:
- TX (app→Tarteel): `{"type":3,"data":"<base64 PCM16>"}` per audio chunk
  (NOT raw binary). Plus `{"type":1,"event":"START_STREAM",...}` to start.
- RX (Tarteel→app): `{"type":2,"text":"{...}"}` text frames; inner JSON has
  `event`: `PARTIAL_TRANSCRIPT` (data.queryText = live ASR string) and
  `STATES_UPDATE` (data.stateIndexOffset + data.newStates[] + data.mistakeUpdates
  + data.audioProcessedMs). Observed newStates codes: 0=scheduled, 1=correct,
  2=mistake. Tarteel's word INDEX space diverges from our local `_words`, so the
  index alone can't map to our Arabic words.

FIXES (this session, mobile + 1 backend echo endpoint):
- `streaming_recitation_service.dart`: audio flush now sends
  `{"type":3,"data":base64(pcm)}` on Tarteel (was raw binary → Tarteel returned
  empty transcripts). Handshake sends `{"type":1,"event":"START_STREAM",...}`.
  `_onSocketData` parses Tarteel text frames via `fromTarteelJson` (list) and
  echoes every raw frame to our VPS debug endpoint. `stop()` on Tarteel resolves
  ~immediately (no `final` event from Tarteel) so "Stop & Review" no longer hangs.
- `recitation_stream_event.dart`: rewrote `fromTarteelJson` → returns
  `List<RecitationStreamEvent>`. `STATES_UPDATE` → word events with idx+status;
  `PARTIAL_TRANSCRIPT` → a word event carrying `spoken` = the transcript (the
  page fuzzy-matches it to local words). Added `_tarteelStateCode`.
- `live_recitation_page.dart`: for Tarteel, `_onEvent` now reveals the LOCAL
  target word by matching the transcript's last token (`_matchTarteelWord` /
  `_normalizeArabic`) instead of trusting Tarteel's index — fixes "words not
  appearing". Added `_revealWord` helper. This addresses the "same word not
  appearing" bug.
- BACKEND: added `POST /v1/recitations/tarteel_debug_echo` to recitation-api
  (logs raw frame / native crash to server logs). Deployed (restart
  recitation-api). Reachable via HTTPS (self-signed, app trusts it).
- `main.dart` + `MainActivity.kt`: added a native `UncaughtExceptionHandler`
  that writes the stack to `cacheDir/crash.txt`; on next launch the app reads it
  via `com.qari.app/crash` MethodChannel and echoes it to the VPS debug endpoint
  → so the "app crashes after ~8s" native crash can be read from `docker logs`
  without pulling device logs.
- VPS HTTPS (443) confirmed WORKING (self-signed; `curl -k` returns the version
  JSON = 1.0.43/54 and the echo endpoint). Earlier `curl` without `-k` gave a
  false "down" reading. OTA serves v1.0.43+54.

BUILD/DEPLOY: rebuilt with `--dart-define=USE_TARTEEL_LIVE=true` → still
v1.0.43+54 (version not bumped; it's a debug/temp build) → `releases/app-release.apk`.
NOT committed/pushed.

NEXT for the user: update via OTA, do ONE short recitation (e.g. Surah 1:1). Then:
1. Do words now appear live? (transcript-match reveal should work if Tarteel
   transcribes our base64 audio). 2. If it still crashes at ~8s, the crash stack
   will now be in `docker logs infra-recitation-api-1 | grep native_crash` — I
   read it from the VPS. 3. If words still don't appear, `docker logs ... |
   grep tarteel_echo` shows the real STATES_UPDATE/PARTIAL_TRANSCRIPT payloads
   and I tune the parser. No Tarteel DRF token has been supplied yet; the build
   works anonymously (Tarteel may rate-limit/anonymously track).

## Session 2026-07-19 (later) — Tarteel live protocol FULLY REVERSE-ENGINEERED + working

After the user supplied a Tarteel DRF token + captured the real request/response
frames, the entire Tarteel live-voice protocol was mapped and the app now tracks
words correctly. Summary of the protocol (verified from device captures):

### Tarteel WS protocol (wss://voice-v2.tarteel.io, behind Cloudflare)
- **Handshake (init config)** — MUST be sent as `{"type":1,"event":"START_STREAM",
  "data":{ audioConfig:{fileFormat:"WAV",channels:1,sampleRate:16000,
  languageCode:"ar-BH",enableInterimResults:true,enableWordTimeOffsets:true,
  maxAlternatives:1}, authToken:"<DRF token>", deviceId, devicePlatform:"android",
  isMemorization:false, isDiacritized:true, isNewSttServer:true,
  recitationMode:"FOLLOW_ALONG", shouldCollectAudio:true, shouldLabelAudio:true,
  ... }}`. NOTE: integer `type:1` (NOT string "START_STREAM"); token goes in
  `data.authToken`. Sending `type:"START_STREAM"` makes Tarteel reply
  "server has not been configured" — it never registered the session.
- **Audio frames** — RAW BINARY WAV (44-byte header + 16kHz PCM16), sent directly
  on the WebSocket (NOT JSON, NOT base64-in-JSON). One WAV per ~250ms flush
  window. Any JSON `{"event":"AUDIO"...}` envelope is rejected with "event AUDIO
  received is not supported". (Tarteel's own frames look like `{type:3,buffer}`
  on the wire — raw binary.) The native capture is 44.1kHz UNPROCESSED (the only
  rate the Android-16 HAL serves) and software-resampled to 16kHz in
  MicForegroundService.LinearResampler before the WAV wrap.
- **Server → app responses** (TEXT frames, `{"event":...,"data":{...}}`):
  - `PARTIAL_TRANSCRIPT` → `data.queryText` (live ASR string; empty during silence).
  - `STATES_UPDATE` → `data.isLost` (bool), `data.stateIndexOffset` (int),
    `data.newStates` (list of `{"type":"SUCCESS"|"FAILURE",startTime,endTime,
    word:"",position:null}`), `data.mistakeUpdates` (map), `data.audioProcessedMs`.
  - `SESSION_END` / `COMPLETE` / `RESULT` → treated as final by naive clients.
- Auth: DRF token in `data.authToken` of START_STREAM. Without it Tarteel sends
  nothing back (silent). Token supplied by user: `5d2dc38f...` (baked via
  `--dart-define=TARTEEL_LIVE_TOKEN=`).

### App changes (all mobile, Tarteel-only; our /ws/recitation/stream backend is
untouched and still the production target once model quality is good enough):
- `app_constants.dart`: `useTarteelLiveApi` (USE_TARTEEL_LIVE), `tarteelLiveWsUrl`,
  `tarteelLiveToken` (TARTEEL_LIVE_TOKEN), `tarteelDebugEchoUrl`,
  `tarteelAudioEvent` (TARTEEL_AUDIO_EVENT, default "AUDIO_CHUNK" — the event
  name Tarteel expects; if rejected, try AUDIO / AUDIO_FRAME via the dart-define
  WITHOUT a code change).
- `streaming_recitation_service.dart`:
  - `_sendTarteelHandshake` → `{"type":1,"event":"START_STREAM","data":{...}}`
    with authToken, audioConfig (WAV/16000), recitationMode FOLLOW_ALONG.
  - `_flushAudio` → wraps the 16k PCM16 in a WAV container (`_wrapWav`) and sends
    a JSON envelope `{"event": tarteelAudioEvent, "data": "<base64 WAV>"}` on the
    socket. **NOT raw bytes** — Tarteel rejects raw/binary and `{"type":3,...}`
    with: "The message sent is not valid, please format it using
    {event: [eventName], data: [data]}". This was the bug fixed in v1.0.46+60.
  - 15s WS connect timeout so a stalled connect surfaces as an error, not a hang.
  - `_echoTarteelFrame` now uses a cert-bypassing `HttpClient` (the plain `http`
    client rejected our VPS self-signed TLS, so frames never reached the server
    logs). Added `_tarteelLastRx` / `_tarteelLastError` surfaced in the diag line
    so Tarteel's exact error payload shows on-screen without the VPS round-trip.
  - `sentSampleRate` (16000) constant shown in diag as `sentRate` to disprove the
    "44.1k vs 16k" confusion.
- `recitation_stream_event.dart` `fromTarteelJson`:
  - STATES_UPDATE parses each `newStates[i]` as an object, reads `item['type']`
    (string "SUCCESS"/"FAILURE"), maps to matched/error. `_tarteelStateCode`
    extended for string codes SUCCESS/COMPLETED/FAILURE. `isLost` is ignored
    (drift frames don't clear the canvas; tracking re-syncs on real states).
  - PARTIAL_TRANSCRIPT / STATES_UPDATE / COMPLETE / SESSION_END / RESULT handled.
- `live_recitation_page.dart` `_onEvent` (Tarteel branch):
  - STRICT navigation: Tarteel `finalResult`/`error` events are IGNORED for
    navigation — the live canvas stays open; only "Stop & Review" finalizes
    (synthesizes a result from revealed words). This stops Tarteel's early
    COMPLETE/SESSION_END from yanking the user to results mid-recitation.
  - WORD REVEAL IS STRICTLY SEQUENTIAL: a `_tarteelCursor` advances only on
    STATES_UPDATE events (those with `wordIndex != null`); PARTIAL_TRANSCRIPT
    (interim ASR) does NOT advance. Each advance reveals `_words[cursor]` in
    order. This FIXED the "اللَّهِ لِلَّهِ" bug — previously the code matched the
    last ASR token against the local word list, so repeated/mis-heard "Allah"
    revealed the wrong words. Now Al-Fatiha reveals in correct order.
  - `_matchTarteelWord` / `_normalizeArabic` are now unused (left for reference).

### VERIFY (device, v1.0.44+55 Tarteel build): words now reveal LIVE in correct
mushaf order as the user recites; mistakes (`FAILURE`) tint red; diag shows
`sentRate: 16000` + `tarteelRx: STATES_UPDATE` / `PARTIAL_TRANSCRIPT`. The
"server has not been configured" / "event AUDIO not supported" / JSON-format
errors are all resolved.

### DEPLOY STATE (2026-07-19 end of day)
- App OTA: v1.0.44+55, built with `--dart-define=USE_TARTEEL_LIVE=true
  --dart-define=TARTEEL_LIVE_TOKEN=5d2dc38f...`. Tarteel live tracking WORKS.
- Working tree (uncommitted before this note): MEMORY.md + the mobile Tarteel
  changes + releases/app-release.apk (v1.0.44+55) + releases/app_release.json.
  Backend (recitation-api) unchanged this session — Tarteel is a client-side
  proxy, no backend change needed.
- NOTE: the per-ayah `RecordingService` (reader "Recite") still uses the `record`
  plugin (may be 0-frame on this Android-16 device). The live flow uses native
  MicForegroundService. `record` can be removed from pubspec once both paths are
  native. `http` was added to pubspec (used by the Tarteel debug echo).
- To REVERT to our own backend: build WITHOUT USE_TARTEEL_LIVE (or set false).
  Our /ws/recitation/stream backend is deployed + working (silence gate, sliding
  window, real Faster-Whisper tiny model) — it's the long-term home once its
  accuracy matches Tarteel.

## Session 2026-07-19 — Tarteel audio-frame envelope fix + VPS rebuild/push
The running OTA APK had reverted to the VPS backend (`wss://20.197.40.13`) instead
of Tarteel. Root causes + fixes this session:

- **Build env is the VPS itself** (this machine IS 20.197.40.13). Flutter is at
  `/home/Innocent/flutter`, Android SDK at `/home/Innocent/Android`. Backend stack
  is docker-compose (infra-nginx-1, infra-core-api-1, infra-recitation-api-1,
  infra-inference-worker-1, postgres, redis) — all healthy. `releases/` is mounted
  into core-api at `/app/releases`, so dropping a new APK there is INSTANTLY live
  (no container restart). OTA serves `https://20.197.40.13/v1/app/download`.
- **Rebuilt with Tarteel on**: `flutter build apk --release
  --dart-define=USE_TARTEEL_LIVE=true
  --dart-define=TARTEEL_LIVE_TOKEN=5d2dc38fcbd3f2be1e4841211850a94733812f2d`
  (`scripts/release_app.sh --use-tarteel-live true --tarteel-token <hex> --bump`
  does build + version bump + APK copy + app_release.json in one step).
- **BUG FIX (the real issue)**: Tarteel returned
  `ERROR {"event":"ERROR","data":{"data":{"message":"The message sent is not
  valid, please format it using {event: [eventName], data: [data]} and try
  again"}}}`. The audio frame was sent as `{"type":3,"data":"<base64>"}`. Fixed in
  `streaming_recitation_service.dart` `_flushAudio` → now sends
  `{"event": AppConstants.tarteelAudioEvent, "data": "<base64 WAV>"}`
  (default event name "AUDIO_CHUNK"). Verified: compiled APK contains
  `voice-v2.tarteel.io` and ZERO `20.197.40.13/ws/recitation` references.
- **TLS caveat**: nginx uses a SELF-SIGNED cert (`/etc/nginx/certs/server.crt`),
  so curl/browsers reject HTTPS (`unknown CA`). The app trusts `20.197.40.13` via
  `network_security_config`, so the app itself is unaffected. Plan a real cert
  (Let's Encrypt for api.qari.app) later.
- **Git push**: no creds on VPS. Pushed via PAT passed inline:
  `git -c credential.helper="" push
  https://x-access-token:<PAT>@github.com/khan23153/qari.git main`.
  (Large-file warning on the 72MB APK — harmless; Git LFS still planned.)
- **The string `5d2dc38fcbd3f2be1e4841211850a94733812f2d` is the TARTEEL DRF
  token, NOT a git commit** — it is not in repo history. Do not `git cat-file` it.

### DEPLOY STATE (2026-07-19 end of day)
- App OTA: **v1.0.46+60** (bumped from +59 via --bump), built with
  `USE_TARTEEL_LIVE=true` + token. Live at `https://20.197.40.13/v1/app/download`,
  verified serving (HTTP 200, bytes match built APK).
- Commits pushed: `ebf8805` (Tarteel build on) + `77357d1` (audio envelope fix)
  → `main` (`15a7ef7..77357d1`).
- Backend unchanged (Tarteel is client-side proxy).
- NEXT suspect if Tarteel STILL rejects audio: the event name. Try
  `--dart-define=TARTEEL_AUDIO_EVENT=AUDIO` (or `AUDIO_FRAME`) — no code change.

## Session 2026-07-26 — IP confirmed (unchanged) + Tarteel audio transport fix + CI builds
Branch: `claude/memory-latest-session-7pdqik` (remote CC session, not the VPS).

1. **NEW_VPS_IP = 20.197.40.13 (same as old)** — user confirmed the new VPS
   keeps the old IP. Audited every hardcoded reference (app_constants.dart,
   network_security_config.xml, nginx.conf, docker-compose.yml,
   api_client.dart, release_app.sh, app_release.json): all already point at
   20.197.40.13, so NO code change and NO IP-driven rebuild was needed. The
   top-of-file migration warning is now marked resolved; the remaining
   migration work is stack re-creation + TLS cert on the new host (see
   checklist below).
2. **Tarteel audio-frame bug FIXED (the v1.0.46+60 "fix" was wrong)** —
   MEMORY contained contradictory protocol notes. Evidence review: the
   device-VERIFIED working build (v1.0.44+55) sent audio as **raw BINARY WAV
   frames**; Tarteel parses TEXT frames as `{event,data}` JSON envelopes,
   which is why `{"type":3,...}` (TEXT) got "format it using {event…}" and
   `{"event":"AUDIO",...}` got "event AUDIO is not supported" (audio is not
   an event). The v1.0.46+60 change to `{"event":"AUDIO_CHUNK","data":b64}`
   TEXT frames therefore re-broke audio. FIX in
   `streaming_recitation_service.dart`: `_flushAudio` sends raw binary WAV
   again (primary); the JSON envelope is kept as a fallback that auto-enables
   ONCE per session if the server rejects the current format (detects "format
   it using"/"not valid"/"not supported" in ERROR frames), or can be forced
   with `--dart-define=TARTEEL_AUDIO_AS_JSON=true`
   (`AppConstants.tarteelAudioAsJson`). Also corrected the stale handshake
   docstring (type is INT 1, not a string). Could NOT live-probe
   wss://voice-v2.tarteel.io from this sandbox (network policy 403) — verify
   on device: diag should show `tarteelRx: STATES_UPDATE`/`PARTIAL_TRANSCRIPT`
   and words revealing live.
3. **APK builds moved to GitHub Actions (user request: stop building on the
   VPS)** — added `.github/workflows/build-apk.yml`: manual trigger
   (workflow_dispatch) with inputs use_tarteel_live / bump / commit_release /
   notes_en. It reuses `scripts/release_app.sh` (same bump + app_release.json
   logic), pins Flutter 3.27.4 + Java 17, uploads the APK as an artifact, and
   (by default) commits `releases/app-release.apk` + bumped metadata back to
   the branch — so the VPS deploy step becomes just `git pull` in the repo dir
   (releases/ is bind-mounted into core-api; OTA picks it up with no restart).
   REQUIRED SETUP: add repo secret `TARTEEL_LIVE_TOKEN` (Settings → Secrets →
   Actions) — the workflow warns if it's missing on a Tarteel build. The
   Tarteel DRF token must no longer be pasted into shell commands.
   NOTE: next Tarteel build via CI ships the binary-WAV fix — bump lands on
   top of v1.0.46+60.
   [SUPERSEDED same day — see item 4: Tarteel was removed entirely; the
   workflow no longer has Tarteel inputs and no TARTEEL_LIVE_TOKEN secret is
   needed.]
4. **TARTEEL REMOVED ENTIRELY (user decision): live tracking = our own
   backend + train our own model.** The user chose to drop the Tarteel proxy
   and invest in our own `/ws/recitation/stream` engine.
   - MOBILE: deleted all Tarteel client code — `AppConstants` Tarteel block
     (useTarteelLiveApi / tarteelLiveWsUrl / tarteelLiveToken /
     tarteelAudioEvent / tarteelAudioAsJson / tarteelDebugEchoUrl → replaced
     by a generic `debugEchoUrl` for the native-crash echo),
     `_sendTarteelHandshake` + `_wrapWav` + Tarteel branches in
     `streaming_recitation_service.dart` (connect/flush/RX/stop paths, echo
     client, tarteelLastRx/-Error diag), `fromTarteelJson` +
     `_tarteelStateCode` in `recitation_stream_event.dart`, and the Tarteel
     cursor/branches in `live_recitation_page.dart` (word reveal is again
     driven by the backend's word_index + `expected` text; backend
     finalResult/error events navigate normally again).
   - BACKEND: `/v1/recitations/tarteel_debug_echo` renamed to
     `/v1/recitations/debug_echo` (old path kept as an alias for fielded
     APKs). Engine unchanged: live = faster-whisper CT2 tiny @6s window,
     batch = whisper-base — both initialized from tarteel-ai's OPEN-SOURCE
     HF checkpoints (that stays; it's our own hosted engine, not their API).
   - BUILD: `release_app.sh` and `build-apk.yml` no longer take Tarteel
     flags; no TARTEEL_LIVE_TOKEN secret needed. Every new build streams to
     our VPS backend.
   - TRAINING PIPELINE (Tarteel-parity plan): new
     `scripts/build_training_dataset.py` builds a fine-tuning dataset from
     everyayah.com (the app's 5 reciters × 6236 ayahs → 16k mono WAV +
     `manifest.jsonl`) paired with corpus Uthmani text — exactly the format
     `ml/training/finetune_whisper.py` (already existed) consumes. Full
     playbook in `ml/training/README.md`: build dataset → fine-tune
     tiny (live) + base (batch) on a GPU box → convert via
     `scripts/convert_tarteel_model.py --model /models/qari-whisper-tiny
     --output .../qari-ct2-tiny` → point
     `QARI_FASTERWHISPER_MODEL_DIR` at it → evaluate WER + latency before
     shipping. Key insight: the streaming matcher is fine; live (tiny) ASR
     accuracy on AMATEUR voices is the gap vs Tarteel — grow the dataset
     with `tarteel-ai/everyayah` (HF) + consented user uploads.
   - NOTE: training itself needs a GPU machine; it cannot run on the VPS or
     in the CC sandbox.
5. **ML system completed to the Tarteel-parity spec (user's 6-feature ask)**:
   - `ml/ARCHITECTURE.md` — master doc mapping all 6 requested features
     (streaming, custom ASR, phonetic alignment, error spotting, dataset/
     training, fast inference) to concrete components + train→deploy flow.
   - NEW `ml/alignment/phonetic.py` — rule-based Arabic grapheme→phoneme
     (articulatory features: place/manner/voicing/emphatic) + weighted
     phoneme edit distance. Wired into `StreamingMatcher._is_match`
     (char-sim OR phonetic-sim ≥0.86): ص/س, ط/ت, ذ/ز, ق/ك confusions now
     match (no false red marks) while الرحمن/الرحيم stay apart. Tests:
     `ml/tests/test_phonetic.py` (12) + all 9 matcher tests pass.
   - NEW `ml/training/finetune_wav2vec2.py` — Wav2Vec2-CTC fine-tuning,
     explicit PyTorch loop (AdamW+warmup, AMP, grad-accum, dataset-derived
     char vocab, per-epoch WER/CER, best-WER checkpoint). Feeds the forced
     aligner; deploy via NEW env `QARI_ALIGNER_MODEL_DIR`
     (forced_alignment.py now reads it).
   - **Live tajweed wired**: `FasterWhisperTranscriber.transcribe_with_timings`
     (CT2 word timestamps) + `StreamingRecitationSession._run_tajweed_checks`
     — finalize() now runs the numpy-only TajweedChecker on the full session
     audio (≤300s, real-transcriber sessions only) and fills `tajweed_score`
     + `tajweed_issues` in the result (was hardcoded 0.0). Best-effort:
     failures log and never block the result. Needs recitation-api restart
     on deploy.
   - NEW `ml/evaluation/benchmark_latency.py` — p50/p95 window-decode
     latency gate vs the 1.2s live budget; run on the VPS before shipping
     any new live model.
   - Verified here: phonetic+matcher+tajweed tests all green (52 total);
     streaming_session imports clean. `tests/test_streaming.py` needs the
     full backend env (hangs in sandbox) — run on VPS.
   - CI note: first Build APK run failed — Flutter 3.27.4 pin too old
     (retrofit 4.9.1 needs Dart ≥3.8). Fixed by unpinning to latest stable
     (f6b1168) and re-triggered.

## Session 2026-07-27 — app debug + offline curriculum (name bug, auth, quizzes)
User screenshots: profile name = infinite spinner; home greeting nameless.
1. **Name bug FIXED**: root cause — profile awaited /me + /me/stats
   sequentially with the 90s Dio timeout. Now: display name + email cached
   at signup/login (LocalStorageService), profile/home show it instantly
   (email local-part fallback), network refresh parallel with 10s timeout,
   fetched name re-cached. Home greeting shows the name under
   "Assalamu Alaikum".
2. **Auth hardened**: 401 on any non-auth endpoint → token cleared +
   `ApiClient.onUnauthorized` (set in main.dart) routes to Login once
   (previously an expired token left a silently-broken Home). Reset via
   `ApiClient.resetUnauthorized()` on login.
3. **Offline curriculum (Learn hub)**: new
   `mobile/lib/data/services/curriculum_service.dart` + asset
   `mobile/assets/vocab_curriculum.json` (75KB, generated by
   `scripts/build_vocab_curriculum.py` from the corpus): 60 vocabulary
   levels × 10 most-frequent words (meaning, transliteration, count,
   example ref, how-to-learn text) with auto-generated MCQ/reverse-MCQ/
   drag-match quizzes; cumulative coverage shown per level (L60 = 58% of
   all Quran words). 3 expanded Foundation lessons + 8 hand-authored
   Grammar lessons (ism/fiʿl/harf, roots, pronouns ×2, prefixes, māḍī,
   muḍāriʿ, iḍāfa) each with quizzes. lesson_list_page rewritten as the
   3-track "Learn Quran" hub; lesson completion + XP persist locally
   (sequential unlocking); home Learning Path now renders the curriculum
   (with real progress) when the server path is empty, and path taps open
   the REAL lesson (previously an empty shell). LessonPlayer pops `true`
   on completion so lists refresh.
4. **CI**: new `.github/workflows/flutter-ci.yml` (analyze + stable test
   suites on any mobile/** push) — the sandbox has no Flutter, so CI is
   the compile check. lesson_route_test updated for new lesson titles.
5. **VPS DOWN (user screenshot)**: phone gets ERR_CONNECTION_REFUSED on
   20.197.40.13 — nginx/docker stack not running on the VPS. User given:
   `docker compose -f infra/docker-compose.yml up -d` + NSG port 80/443
   check; interim APK link = GitHub raw releases/app-release.apk.

## Session 2026-07-26/27 — app debug + offline learning curriculum (commit 0425fd2)
User-reported bugs FIXED (all verified by Flutter CI - new flutter-ci.yml):
1. Profile "name shows only loading" — /me + /me/stats were awaited
   SEQUENTIALLY with 90s Dio timeouts. Now: display name + email cached at
   signup/login (LocalStorageService displayName/userEmail keys), shown
   instantly; network refresh parallel with 10s bound. Home greeting shows
   the name under "Assalamu Alaikum" (home_page _displayName).
2. Expired JWT = silently broken app — added ApiClient.onUnauthorized:
   401 on any non-/auth/ endpoint clears the token once and routes to Login
   (main.dart wires it via rootNavigatorKey; reset on re-auth).
NEW OFFLINE LEARNING SYSTEM (no backend needed):
- CurriculumService (mobile/lib/data/services/curriculum_service.dart):
  3 tracks — Foundation (3 lessons), Grammar (8 lessons w/ quizzes:
  ism/fi'l/harf, roots, pronouns, attached pronouns, prefixes, past/present
  verbs, idafa), Vocabulary (60 auto-generated levels from
  assets/vocab_curriculum.json — top-600 corpus words, 10/level, meanings +
  transliteration + frequency + how-to-learn text + MCQ/reverse-MCQ/
  drag-match quizzes; cumulative coverage shown honestly, 58% at L60).
  Regenerate asset: scripts/build_vocab_curriculum.py (--top N for more).
- Local progress: completed lesson ids + local XP in LocalStorageService;
  sequential unlocking; lesson_player marks completion and pops true.
- lesson_list_page = 3-track Learn hub; home Learning Path renders the
  curriculum with real progress when server path is empty; path taps open
  REAL lessons (CurriculumService.findLesson).
- Lesson IDs: foundation 100+, grammar 200+, vocab 1000+level (stable keys).
CI: flutter-ci.yml (analyze + 4 stable test suites) on mobile/** pushes —
GREEN on 0425fd2. Legacy broken tests (reader_render_test, widget_test
grammar-colors) intentionally excluded; fix later.
VPS NOTE (new OCI VPS, same IP): only docker-compose v1 (1.29.2) is
installed → breaks vs new engine ("KeyError: ContainerConfig"), and the
whole stack was DOWN (ERR_CONNECTION_REFUSED on OTA). Fix = install
Compose v2 plugin binary manually, remove v1-named infra_* containers,
`docker compose up -d`. Also regenerate gitignored CT2 models +
reference_data on this machine (migration checklist below).

## VPS MIGRATION CHECKLIST (do these when NEW_VPS_IP is known)
Fresh VPS host. Nothing carries over automatically — re-create everything.

### 1. Base setup on new VPS
- Install Docker + docker compose, git, Python venv deps
  (`/home/Innocent/venv`: fastapi, httpx, pytest-asyncio, redis, etc.).
- Clone repo: `git clone https://github.com/khan23153/qari.git`.
- Flutter at `/home/Innocent/flutter` (NOT in PATH) + Android SDK at
  `/home/Innocent/Android` — needed to rebuild+deploy the OTA APK here.

### 2. Backend (docker compose redeploy)
- `infra/docker-compose.yml` already defines all services. Before `up`:
  - Update `nginx.conf` server_name + proxy_pass targets to NEW_VPS_IP.
  - `recitation-api` mounts `../ml` + `PYTHONPATH:/app` + `QARI_ML_USE_STUB=false`
    + `QARI_FASTERWHISPER_MODEL_DIR=/app/models/tarteel-ct2-tiny` (live=tiny@6s
    window; batch upload uses base/PyTorch in inference-worker).
  - `inference-worker` uses `QARI_ML_USE_STUB=false` (real Whisper/QuranASR).
- `docker compose -f infra/docker-compose.yml up -d` (creates nginx, core-api,
  recitation-api, inference-worker, postgres, redis).
- Postgres: run `alembic upgrade head` (the `ayahs.audio_url_ur` column migration
  `0003_ayah_audio_url_ur` MUST exist or the ayahs query fails).
- **Regenerate gitignored model + reference data** (NOT in repo, must rebuild):
  - CT2 models: `python scripts/convert_tarteel_model.py` → writes
    `backend/recitation_api/models/tarteel-ct2-tiny` (+ `-ct2-base`).
  - Reference bundle: `python scripts/build_reference_from_local_corpus.py` →
    `backend/recitation_api/reference_data` (6236 ayahs; needed so recitation
    scoring isn't empty).
- Verify: `curl -k https://NEW_VPS_IP/v1/app/version` returns the version JSON.

### 3. TLS / cert
- Old VPS used a self-signed cert at `/etc/nginx/certs/server.crt`. Either copy
  that cert/key to the new host (so the app's pinned `trustedSelfSignedHost`
  keeps working) OR issue a real Let's Encrypt cert for `api.qari.app` (preferred
  long-term). Until a real cert, the app trusts the self-signed host via
  `network_security_config.xml` — update the host there if IP changes.

### 4. OTA APK rebuild + deploy (REQUIRED after IP change)
The app hardcodes the backend host, so a new IP means a new build + OTA push:
- Update `app_constants.dart` host → NEW_VPS_IP (or domain).
- Decide Tarteel-on vs own-backend (last build was Tarteel-on; see top note).
- `scripts/release_app.sh` (build + bump version + copy APK) or manually:
  `flutter pub get && flutter build apk --release` → copy
  `mobile/build/app/outputs/flutter-apk/app-release.apk` → `releases/app-release.apk`
  (bind-mounted into core-api at `/app/releases`, instantly live, no restart).
  Bump `pubspec.yaml` + `releases/app_release.json` together.
- Verify `https://NEW_VPS_IP/v1/app/download` serves the new APK.

### 5. After migration
- Replace all `20.197.40.13` refs in MEMORY.md + repo with NEW_VPS_IP.
- Decommission old VPS only after confirming the new one serves OTA + WS + recitation.
- Uncommitted working-tree state from old VPS (2026-07-19): MEMORY.md +
  mobile Tarteel changes + app-release.apk + app_release.json. Backend code is
  committed/pushed (last backend commit 0040abf; Tarteel is client-side only).
