import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../data/models/recitation_model.dart';
import '../../../../data/models/recitation_session_record.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../../../../data/repositories/local_corpus_repository.dart';
import '../../../../data/repositories/mushaf_layout_repository.dart';
import '../../../../data/services/audio_service.dart';
import '../../../../data/services/local_storage_service.dart';
import '../../../../data/services/recitation_history_service.dart';
import '../../../../data/services/streaming_recitation_service.dart';
import '../mushaf/floating_recitation_bar.dart';
import '../mushaf/mushaf_jump_sheet.dart';
import '../mushaf/mushaf_page_frame.dart';
import '../mushaf/mushaf_theme.dart';
import '../mushaf/surah_titles.dart';
import '../recitation_mode.dart';
import '../recitation_review.dart';
import '../widgets/mushaf_reveal_view.dart';
import '../widgets/word_comparison_sheet.dart';
import 'recitation_history_page.dart';
import 'verse_identifier_page.dart';

/// UI phases for the live (real-time) recitation experience.
enum LiveRecitationUiState { setup, live, finalizing, results, error }

/// What block of Quran the user is reciting continuously.
enum RecitationScope { page, surah }

/// Upgraded AI Recitation section — real-time voice tracking rendered as a
/// **Mushaf (physical-book) layout**. As the backend confirms each recited word
/// over the live WebSocket, the word is revealed on a blank canvas and flows
/// continuously right-to-left like a printed Quran, with inline ayah markers
/// between verses.
///
/// This is a **separate** page from the legacy [RecitationPage] used by the
/// Quran reader's per-ayah "Recite" button, which is intentionally left
/// untouched. Only the home "AI Recitation" entry routes here.
class LiveRecitationPage extends StatefulWidget {
  final int? surahNumber;
  final int? ayahNumber;

  /// The entry point owns the mode. AI recitation defaults to Hifz; the
  /// Tilawat entry explicitly requests visible text.
  final RecitationMode? initialMode;

  /// Allows the standalone UI preview to explain why voice feedback is offline.
  final VoidCallback? onStartRecitation;

  const LiveRecitationPage({
    super.key,
    this.surahNumber,
    this.ayahNumber,
    this.initialMode,
    this.onStartRecitation,
  });

  @override
  State<LiveRecitationPage> createState() => _LiveRecitationPageState();
}

class _LiveRecitationPageState extends State<LiveRecitationPage> {
  final StreamingRecitationService _service = StreamingRecitationService();

  /// Selected Mushaf preset (persisted locally via SharedPreferences).
  final MushafThemeController _mushafController = MushafThemeController();

  /// When true, the app bar and floating bar are hidden for distraction-free
  /// reading. Toggled by tapping the Mushaf page itself.
  bool _chromeVisible = true;

  /// Tilawat (full page visible) or Hifz (unsaid words hidden).
  late final RecitationMode _mode;
  final AudioService _audioService = AudioService();

  LiveRecitationUiState _ui = LiveRecitationUiState.setup;

  RecitationScope _scope = RecitationScope.page;
  int _surah = 1;
  int _ayah = 1;
  int _page = 1;
  bool _loadingPage = true;
  int _loadGeneration = 0;
  int _ayahCount = 7;

  /// For the Surah scope: the exact ayah range the user wants to recite.
  /// Defaults to the whole surah (1 .. _ayahCount).
  int _ayahFrom = 1;
  int _ayahTo = 7;

  /// Whether to colour tajweed rules on the revealed (correct) words, like the
  /// Surah reader. Persisted across sessions.
  bool _tajweedOn = true;

  /// Flat target word array across all ayahs being recited (the whole
  /// page/surah). Used to drive the backend reference + the results grid.
  List<String> _words = const [];
  List<int> _wordLines = const [];
  List<int> _markerLines = const [];

  /// Tajweed spans, aligned 1:1 with [_words], so each revealed word can be
  /// coloured per-letter by its tajweed rule.
  List<List<TajweedSpan>?> _wordTajweedSpans = const [];

  /// Ordered (surah, ayah) references for the loaded block — sent to the
  /// backend so it can resolve the concatenated reference list.
  List<(int, int)> _ayahRefs = const [];

  /// 0-based index of the LAST word of each ayah in [_words] (for markers).
  List<int> _ayahBoundaries = const [];

  /// Ayah-number labels aligned 1:1 with [_ayahBoundaries].
  List<String> _ayahLabels = const [];

  /// Location of each ayah, aligned 1:1 with [_ayahBoundaries]; drives the
  /// "Surah · Page | Juz | Hizb" header as the cursor moves.
  List<_AyahMeta> _ayahMeta = const [];

  /// Word index → surah number, for every surah that OPENS inside the target
  /// (its ayah 1 is present). The surah plate + Bismillah are drawn inline
  /// right before that word.
  Map<int, int> _surahStarts = const {};

  // ── Live reveal state (the "magic typing" canvas) ───────────────────────
  /// Words revealed so far from the live WebSocket. Starts COMPLETELY EMPTY
  /// (blank canvas) — no dots, no placeholders. Each confirmed word is appended
  /// here in recitation order.
  List<String> _revealedWords = const [];

  /// Per-revealed-word live status (matched / error / skipped) for tinting.
  List<LiveWordStatus> _revealedStatuses = const [];

  /// Index of the word the reciter is expected to say NEXT.
  ///
  /// Feeds the red-wall guard in [MushafRevealView]: any revealed word whose
  /// index is ahead of this cursor is rendered neutral, whatever the server
  /// said. Advanced on every accepted word event.
  int _liveCursor = 0;

  /// Per-revealed-word tajweed spans (aligned 1:1 with [_revealedWords]) so the
  /// live canvas can colour each letter by its rule as it appears.
  List<List<TajweedSpan>?> _revealedTajweedSpans = const [];

  /// Dedup guard: reference word indices already revealed (the backend may
  /// re-emit a status change for a word we already showed).
  final Set<int> _revealedIndices = {};

  /// Anchor key for the word at the recitation cursor, so we can auto-scroll
  /// the ACTIVE word into view.
  ///
  /// NOTE: this must follow the cursor word, not the end of the page. The Mushaf
  /// is pre-rendered in full, so an anchor parked after the final word would sit
  /// at the bottom of the surah and scroll the reader away on the first event.
  final GlobalKey _cursorKey = GlobalKey();

  /// Fallback anchor at the end of the flow, used only before recitation starts
  /// (cursor == -1), when no word is active to scroll to.
  final GlobalKey _caretKeyFallback = GlobalKey();

  /// Drives the auto-scroll so the active word stays in the upper half of the
  /// viewport as words wrap.
  final ScrollController _scrollController = ScrollController();

  /// The post-recitation review (reach-limited statuses + score). Rendered on
  /// the same Mushaf page, never as a separate tile screen.
  RecitationReview? _review;
  String? _errorMessage;

  /// Live diagnostics notifiers (updated by [_diagTimer] so only the small
  /// diagnostic Text rebuilds, not the whole reveal view).
  final ValueNotifier<int> _micChunksNotifier = ValueNotifier(0);
  final ValueNotifier<int> _sentBytesNotifier = ValueNotifier(0);

  /// Native recorder error captured from the recorder's state channel (e.g.
  /// "PCM reader failed to initialize"). Surfaced live so a swallowed setup
  /// failure is visible immediately, not just on the error screen.
  final ValueNotifier<String?> _micErrorNotifier = ValueNotifier(null);

  /// Android audio-focus grant result (from `audio_session`). `false` ⇒ the OS
  /// denied focus ⇒ the recorder is silently dead ⇒ "mic chunks: 0".
  final ValueNotifier<bool?> _focusNotifier = ValueNotifier(null);

  /// How many native audio frames actually reached the Dart `onData` callback.
  /// Surfaced live so we can tell "native posted frames but Dart never got them"
  /// (EventChannel delivery break) from "Dart got them but processing failed".
  final ValueNotifier<int> _audioOnDataNotifier = ValueNotifier(0);

  /// True once we've been "listening" for a couple seconds but the recorder has
  /// produced zero chunks — i.e. the OS is blocking mic capture. Surfaces a
  /// live warning so the user doesn't have to wait until "Stop" to find out.
  final ValueNotifier<bool> _noAudioNotifier = ValueNotifier(false);
  DateTime? _listenStartedAt;
  Timer? _diagTimer;

  /// Guards `_stop()` so repeated taps on "Stop & Review" (the old 10-click
  /// workaround) only trigger one finalize.
  bool _stopping = false;

  StreamSubscription<RecitationStreamEvent>? _eventSub;
  StreamSubscription<LiveConnectionState>? _connSub;

  @override
  void initState() {
    super.initState();
    _loadAppearancePreferences();
    _mode = widget.initialMode ?? RecitationMode.hifz;
    _loadInitialPage();
    _mushafController.load();

    _eventSub = _service.events.listen(_onEvent);
    _connSub = _service.connectionState.listen(_onConnectionState);
  }

  @override
  void dispose() {
    _stopDiagTimer();
    _eventSub?.cancel();
    _connSub?.cancel();
    _scrollController.dispose();
    _mushafController.dispose();
    _micChunksNotifier.dispose();
    _sentBytesNotifier.dispose();
    _micErrorNotifier.dispose();
    _focusNotifier.dispose();
    _audioOnDataNotifier.dispose();
    _noAudioNotifier.dispose();
    _service.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _loadAppearancePreferences() async {
    final enabled =
        await LocalStorageService().getTajweedColorsEnabled(defaultValue: true);
    if (mounted) setState(() => _tajweedOn = enabled);
  }

  /// Resets every verdict on the page WITHOUT removing the text: all words go
  /// back to ghost-ink `unspoken` and nothing is active. Must be called inside
  /// a `setState`.
  ///
  /// The page text is never wiped. Wiping it on the mic tap and re-flooding it
  /// on `ready` is what made the whole surah "appear" at once in solid ink.
  void _clearReveal() {
    _revealedWords = List<String>.from(_words);
    _revealedStatuses = List<LiveWordStatus>.filled(
      _words.length,
      LiveWordStatus.pending,
    );
    _revealedTajweedSpans = List<List<TajweedSpan>?>.from(_wordTajweedSpans);
    _revealedIndices.clear();
    _liveCursor = -1;
    _review = null;
  }

  /// True when [text] contains at least one Arabic letter.
  ///
  /// Used to drop the corpus' trailing numeric verse markers ("١", "٢", …).
  /// This mirrors the backend reference builder exactly, so the client index
  /// space matches the wire index space. Kept in one place so the two cannot
  /// drift apart silently.
  static bool _hasArabicLetter(String text) {
    for (final code in text.codeUnits) {
      // U+0621..U+064A covers the Arabic letters; digits and Arabic-Indic
      // digits (U+0660..U+0669) fall outside it.
      if (code >= 0x0621 && code <= 0x064A) return true;
    }
    return false;
  }

  /// Pre-renders the entire target so the page is NEVER blank.
  ///
  /// The whole recitation target is laid out up front with every word in
  /// [LiveWordStatus.pending] (renders as neutral `unspoken` book ink). Live
  /// events then mutate `_wordVerdicts` **in place** — a word's text and its
  /// position on the page never change, only its colour does. This is what
  /// removes the "words popping onto a blank canvas" effect.
  void _primeFullPage() {
    // Cursor starts at -1: nothing is active until the session is live, so
    // every word renders as ghost-ink `unspoken` (index > cursor) on open.
    setState(_clearReveal);
  }

  /// Applies a live word verdict IN PLACE on the pre-rendered page.
  ///
  /// Replaces the old append behaviour. [idx] is the reference index from the
  /// wire; the word's text is taken from the already-rendered [_revealedWords]
  /// (which carries full tashkeel) rather than from the event, so the glyphs on
  /// screen never change once drawn.
  void _applyVerdict(String? text, int? idx, LiveWordStatus status,
      [List<TajweedSpan>? spans]) {
    if (idx == null || idx < 0 || idx >= _revealedWords.length) return;
    setState(() {
      // Last verdict wins: a word can be re-emitted with a better status, and
      // a later `match` must be able to clear an earlier provisional `error`.
      if (status != LiveWordStatus.pending) {
        _revealedStatuses[idx] = status;
      }
      if (spans != null && idx < _revealedTajweedSpans.length) {
        _revealedTajweedSpans[idx] = spans;
      }
      _revealedIndices.add(idx);
      // The cursor only ever moves FORWARD, and only to just past the word we
      // just resolved, so a reordered or duplicated event can never yank it
      // backwards. This is what keeps words ahead of the cursor neutral and
      // therefore prevents the red wall.
      if (idx + 1 > _liveCursor) _liveCursor = idx + 1;
    });
    _scrollToLatest();
  }

  // ─── Data loading ─────────────────────────────────────────────────────────

  final LocalCorpusRepository _corpus = LocalCorpusRepository();

  Future<void> _loadInitialPage() async {
    if (widget.surahNumber != null) {
      final ayahs = await _corpus.getAyahs(widget.surahNumber!);
      final chosen =
          ayahs.where((a) => a.ayahNumber == (widget.ayahNumber ?? 1));
      if (chosen.isNotEmpty) _page = chosen.first.pageNumber ?? 1;
    }
    if (mounted) await _loadScope();
  }

  /// Loads the target block from the bundled corpus and records where each ayah
  /// ends (for inline markers). For the Surah scope this honours the selected
  /// [_ayahFrom] .. [_ayahTo] range. The live canvas stays blank until reciting.
  Future<void> _loadScope() async {
    final generation = ++_loadGeneration;
    try {
      final printedLayout = await MushafLayoutRepository().load();
      List<AyahModel> allAyahs;
      if (_scope == RecitationScope.page) {
        allAyahs = await _corpus.getAyahsByPage(_page);
      } else {
        allAyahs = await LocalCorpusRepository().getAyahs(_surah);
      }
      if (allAyahs.isEmpty) return;

      // For the surah scope, restrict to the chosen ayah range.
      final ayahs = _scope == RecitationScope.surah
          ? allAyahs
              .where(
                  (a) => a.ayahNumber >= _ayahFrom && a.ayahNumber <= _ayahTo)
              .toList()
          : allAyahs;

      final words = <String>[];
      final tajweed = <List<TajweedSpan>?>[];
      final refs = <(int, int)>[];
      final boundaries = <int>[];
      final labels = <String>[];
      final wordLines = <int>[];
      final markerLines = <int>[];
      final meta = <_AyahMeta>[];
      final starts = <int, int>{};

      for (final a in ayahs) {
        final layout = printedLayout[a.reference];
        if (layout == null) {
          throw StateError('Missing Mushaf layout: ${a.reference}');
        }
        var wordPosition = 0;
        if (a.ayahNumber == 1) starts[words.length] = a.surahNumber;
        for (final w in a.words) {
          // Skip the corpus' trailing numeric verse marker (e.g. "١").
          //
          // CRITICAL for index alignment: the backend reference builder drops
          // any token with no Arabic letters (scripts/build_reference_from_local_corpus.py),
          // so the wire indices do NOT include these markers. Keeping them here
          // would shift every word index after the first ayah and paint the
          // highlight onto the wrong word. We render the marker ourselves via
          // ayahBoundaries, so dropping it here is also what keeps the ayah
          // ornament from appearing twice.
          if (!_hasArabicLetter(w.text)) continue;
          final location = layout.words[wordPosition++];
          wordLines.add(
              _scope == RecitationScope.page ? location.line : location.row);
          words.add(w.text);
          tajweed.add(
            (w.tajweedSpans != null && w.tajweedSpans!.isNotEmpty)
                ? w.tajweedSpans
                : null,
          );
        }
        refs.add((a.surahNumber, a.ayahNumber));
        if (a.words.isNotEmpty) {
          boundaries.add(words.length - 1);
          labels.add(a.ayahNumber.toString());
          markerLines.add(_scope == RecitationScope.page
              ? layout.marker.line
              : layout.marker.row);
          meta.add(_AyahMeta(
            surah: a.surahNumber,
            ayah: a.ayahNumber,
            page: a.pageNumber,
            juz: a.juzNumber,
          ));
        }
      }

      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadingPage = false;
          _surah = ayahs.first.surahNumber;
          _ayah = ayahs.first.ayahNumber;
          _ayahFrom = _ayah;
          _ayahTo = ayahs.last.ayahNumber;
          _words = words;
          _wordLines = wordLines;
          _markerLines = markerLines;
          _wordTajweedSpans = tajweed;
          _ayahRefs = refs;
          _ayahBoundaries = boundaries;
          _ayahLabels = labels;
          _ayahMeta = meta;
          _surahStarts = starts;
          _ayahCount = ayahs.last.ayahNumber;
        });
        // Pre-render the whole target immediately so the screen shows the full
        // Mushaf text from word one — never a blank canvas awaiting the mic.
        _primeFullPage();
      }
    } catch (e) {
      debugPrint('LiveRecitation: could not load scope: $e');
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadingPage = false;
          _ui = LiveRecitationUiState.error;
          _errorMessage = 'Could not load this Quran page. Please try again.';
        });
      }
    }
  }

  // ─── Streaming event handlers ───────────────────────────────────────────

  void _onEvent(RecitationStreamEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case RecitationStreamEventType.ready:
        // The backend's reference words are authoritative (they carry the
        // Uthmani `text_with_tashkeel` and the exact index space the live
        // events will address). Adopt them as the pre-rendered page text when
        // the count agrees with the locally loaded target.
        //
        // NEVER render `event.expected` for display: that field is the ASR-facing
        // key, and using it would strip the diacritics off the page.
        final serverWords = event.words.isNotEmpty &&
                event.words.length == _revealedWords.length
            ? event.words.map((w) => w.text).toList()
            : null;
        // Re-prime (rather than only resetting verdicts) so a reconnect starts
        // from a clean, fully neutral page instead of inheriting the previous
        // session's colours. Prime FIRST, then adopt the server text, so the
        // text is not overwritten by the reset.
        _primeFullPage();
        if (mounted) {
          setState(() {
            if (serverWords != null) _revealedWords = serverWords;
            // The engine is listening: light up the first expected word.
            // Everything after it stays ghosted until confirmed.
            _liveCursor = 0;
          });
        }
        break;
      case RecitationStreamEventType.word:
        final idx = event.wordIndex;
        // Update that exact word IN PLACE. The text is never taken from the
        // event — the word is already on screen with its full tashkeel, so the
        // page layout never shifts and glyphs never re-render differently.
        final text = (event.expected ?? event.spoken ?? '').trim();
        // Capture the word's tajweed spans (aligned by reference index) so the
        // live canvas can colour each letter by its rule.
        final spans =
            (idx != null && idx >= 0 && idx < _wordTajweedSpans.length)
                ? _wordTajweedSpans[idx]
                : null;
        _applyVerdict(text, idx, event.status, spans);
        break;
      case RecitationStreamEventType.finalResult:
        _finishWith(event.result);
        break;
      case RecitationStreamEventType.error:
        setState(() {
          _ui = LiveRecitationUiState.error;
          _errorMessage = event.detail ?? 'Streaming error';
        });
        break;
      case RecitationStreamEventType.pong:
      case RecitationStreamEventType.unknown:
        break;
    }
  }

  void _onConnectionState(LiveConnectionState state) {
    if (!mounted) return;
    if (state == LiveConnectionState.error &&
        _ui == LiveRecitationUiState.live) {
      setState(() {
        _ui = LiveRecitationUiState.error;
        _errorMessage ??=
            'Lost connection to the live engine. Check your network and retry.';
      });
    }
  }

  /// Smoothly scrolls the ACTIVE (cursor) word to the upper third of the
  /// viewport, but ONLY when it enters the bottom 30% — so we don't fight the
  /// user's own scrolling on every word.
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Follow the cursor word. Falls back to the trailing caret only before
      // recitation starts (cursor == -1), when no word is active yet.
      final BuildContext? ctx =
          _cursorKey.currentContext ?? _caretKeyFallback.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;

      final position = Scrollable.of(ctx).position;
      final viewportHeight = position.viewportDimension;
      if (viewportHeight <= 0) return;

      final wordTop = box.localToGlobal(Offset.zero).dy;
      final containerBox =
          position.context.storageContext.findRenderObject() as RenderBox?;
      final containerTop = containerBox?.localToGlobal(Offset.zero).dy ?? 0.0;
      final rel = wordTop - containerTop; // word offset within the viewport

      // Blueprint: if the latest word enters the bottom 30% of the viewport,
      // animate it to ~33% from the top (upper third).
      // The floating mic bar covers the bottom of the viewport, so follow
      // the cursor before it gets near that band.
      if (rel > viewportHeight * 0.60) {
        final delta = rel - viewportHeight * 0.33;
        position.animateTo(
          position.pixels + delta,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // ─── Session control ──────────────────────────────────────────────────────

  Future<void> _start() async {
    if (!_canChangePage) return;
    await Haptics.vibrate(HapticsType.medium);
    _listenStartedAt = DateTime.now();
    _noAudioNotifier.value = false;
    _stopping = false;
    setState(() {
      _ui = LiveRecitationUiState.live;
      _clearReveal();
      _errorMessage = null;
    });
    _scrollToTop();

    try {
      await _service.start(
        surahNumber: _surah,
        ayahNumber: _ayah,
        ayahFrom: _scope == RecitationScope.surah ? _ayahFrom : _ayah,
        ayahTo: _scope == RecitationScope.surah ? _ayahTo : _ayah,
        ayahRefs: _ayahRefs,
        // Full target word list sent so the backend can score even if its own
        // reference store is empty (prevents "0 of 0 words correct").
        words: _words,
        // Reveal-as-you-speak is the ONLY behaviour on this screen.
        memorizationMode: _mode == RecitationMode.hifz,
      );
    } on MicPermissionDeniedException {
      setState(() {
        _ui = LiveRecitationUiState.error;
        _errorMessage =
            'Microphone access denied. Enable it in Settings to use live recitation.';
      });
    } catch (e) {
      setState(() {
        _ui = LiveRecitationUiState.error;
        _errorMessage = 'Could not start the live session: $e';
      });
    }
    _startDiagTimer();
  }

  void _startDiagTimer() {
    _stopDiagTimer();
    _diagTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final chunks = _service.micChunks;
      _micChunksNotifier.value = chunks;
      _sentBytesNotifier.value = _service.sentBytes;
      // Capture any native recorder error (state channel) so it shows live.
      _micErrorNotifier.value = _service.micError;
      // Capture whether Android granted audio focus — a `false` here is the
      // smoking gun for a silently-dead recorder (OS/contending app blocking).
      _focusNotifier.value = _service.audioFocusGranted;
      _audioOnDataNotifier.value = _service.audioOnDataCount;
      // After ~2s of listening with zero recorder output, the OS is almost
      // certainly blocking mic capture — flag it live instead of waiting for
      // "Stop" (by which point the live UI is replaced by the error screen).
      if (_listenStartedAt != null &&
          DateTime.now().difference(_listenStartedAt!).inMilliseconds > 2000 &&
          chunks == 0 &&
          !_noAudioNotifier.value) {
        _noAudioNotifier.value = true;
      }
    });
  }

  void _stopDiagTimer() {
    _diagTimer?.cancel();
    _diagTimer = null;
    _noAudioNotifier.value = false;
    _listenStartedAt = null;
  }

  Future<void> _stop() async {
    if (_stopping) return; // idempotent: ignore repeated taps while finishing
    _stopping = true;
    _stopDiagTimer();
    await Haptics.vibrate(HapticsType.selection);
    // Show "Finalizing…" immediately so the long server-side final
    // transcription (re-processing the whole recitation, can take many seconds
    // on a slow CPU) doesn't make the button feel dead. The `final` WS event
    // will drive navigation to results; the timer is only a safety net.
    setState(() => _ui = LiveRecitationUiState.finalizing);
    unawaited(_service.stop());
    Timer(const Duration(seconds: 45), () {
      if (mounted && _ui == LiveRecitationUiState.finalizing) {
        _finishWith(_synthesizeResult());
      }
    });
  }

  void _finishWith(RecitationResult? result) {
    if (!mounted) return;
    // Idempotent: the `final` event and `_stop()`'s safety timer can both call
    // this; only the first one should navigate + persist.
    if (_ui == LiveRecitationUiState.results) return;

    // Tear down the mic + socket immediately so the native foreground service
    // stops pushing PCM into the (now irrelevant) EventChannel sink while the
    // results screen is shown. Keeping capture alive here was the most likely
    // trigger for the hard native crash reported after a recitation finished.
    unawaited(_service.cancel());

    // If the app never sent any microphone audio to the server, there is
    // nothing to score — surfacing a silent "0 of N / Duration: 0s" is
    // confusing. Show a clear, actionable error instead so the user knows to
    // grant mic access / free the microphone.
    if (_service.sentBytes == 0) {
      final chunks = _service.micChunks;
      // The native recorder often reports the *real* cause asynchronously
      // (unsupported sample rate, "PCM reader failed to initialize", another
      // app holding the mic). Surface it verbatim so the user isn't left
      // guessing between "permission" and "network".
      final nativeErr = _service.micError;
      final nativeDetail =
          nativeErr != null ? ' Recorder error: $nativeErr' : '';
      // Distinguish "the recorder produced no audio" (capture blocked by the
      // OS despite the app permission being granted) from "audio was captured
      // but never reached the server" (a transport / dropped-connection issue)
      // — the fix is very different for each.
      final captureHint = chunks == 0
          ? 'The microphone produced no audio at all.$nativeDetail '
              '${_service.audioFocusGranted == false ? 'Android denied audio '
                  'focus — another app (voice assistant, recorder, call) is '
                  'likely holding the mic. ' : ''}'
              'Open your device Settings › Apps › Qari › Permissions › '
              'Microphone and set it to "Allow", close any other app using the '
              'mic (voice assistant, recorder, phone call), then restart Qari '
              'and retry.'
          : 'Audio was captured ($chunks mic chunks) but none reached the '
              'server. The connection dropped mid-stream — check your network '
              'and retry.';
      setState(() {
        _ui = LiveRecitationUiState.error;
        _errorMessage = 'No microphone audio was captured (0 bytes sent, '
            'mic chunks: $chunks). $captureHint';
      });
      debugPrint('[LiveRecitation] 0 bytes sent → micChunks=$chunks '
          '(capture blocked: ${chunks == 0})');
      return;
    }

    // Score ONLY the words the reciter reached. The server's `final` re-scores
    // the whole target, so an early stop comes back with every remaining word
    // `is_correct: false` — trusted as-is that was a red page and a 0% score.
    final review = _buildReview(
      result != null && result.wordVerdicts.isNotEmpty ? result : null,
    );
    debugPrint('[LiveRecitation] finish: backendVerdicts='
        '${result?.wordVerdicts.length ?? -1}, '
        'liveCursor=$_liveCursor, reach=${review.reach}, '
        'targetWords=${_revealedWords.length}');

    // Persist the session locally for history / mistake-review / streak.
    _persistSession(review.result);

    setState(() {
      _review = review;
      _ui = LiveRecitationUiState.results;
    });
  }

  RecitationReview _buildReview(RecitationResult? serverResult) {
    return buildRecitationReview(
      words: _revealedWords,
      liveCursor: _liveCursor,
      liveStatuses: _revealedStatuses,
      serverResult: serverResult,
      surahNumber: _surah,
      ayahNumber: _ayah,
    );
  }

  /// Saves the completed session to the local history store (Tarteel-style
  /// "Mistake Review" + streak tracking). Captures every mispronounced /
  /// skipped word as a [RecitationMistake] for later review.
  void _persistSession(RecitationResult result) {
    try {
      final mistakes = <RecitationMistake>[];
      for (final v in result.wordVerdicts) {
        if (v.isCorrect) continue;
        final expected = v.expectedText ?? v.displayWord(_words);
        mistakes.add(RecitationMistake(
          word: v.displayWord(_words),
          expectedText: expected,
          errorType: v.errorType ?? 'error',
          surahNumber: _surah,
          ayahNumber: _ayah,
        ));
      }
      final from = _scope == RecitationScope.surah ? _ayahFrom : _ayah;
      final to = _scope == RecitationScope.surah ? _ayahTo : _ayah;
      // Fire-and-forget: the session is already shown; persistence must never
      // block the results UI.
      LocalStorageService.getInstance().then((ls) {
        RecitationHistoryService(ls.prefs).saveSession(
          scope: _scope == RecitationScope.page ? 'page' : 'surah',
          surahNumber: _surah,
          ayahFrom: from,
          ayahTo: to,
          overallScore: result.overallScore,
          correctCount: result.correctCount,
          totalCount: result.wordVerdicts.length,
          durationSeconds: result.durationSeconds,
          mistakes: mistakes,
        );
      });
    } catch (e) {
      debugPrint('LiveRecitation: could not persist session: $e');
    }
  }

  /// Builds a result from the live verdicts when the backend final payload
  /// didn't arrive (e.g. connection dropped) so the user still sees feedback.
  /// Like the server path, only words up to the reach are scored.
  RecitationResult _synthesizeResult() => _buildReview(null).result;

  Future<void> _cancel() async {
    _stopDiagTimer();
    await _service.cancel();
    if (mounted) {
      setState(() {
        _ui = LiveRecitationUiState.setup;
        _clearReveal();
      });
    }
  }

  void _reset() {
    _stopDiagTimer();
    setState(() {
      _ui = LiveRecitationUiState.setup;
      _errorMessage = null;
      _clearReveal();
    });
  }

  void _onMistakeTapped(int index) {
    final verdict = _review?.verdictAt(index);
    if (verdict != null) _onWordTapped(verdict);
  }

  void _onWordTapped(WordVerdict verdict) {
    if (verdict.isCorrect) return;
    Haptics.vibrate(HapticsType.medium);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => WordComparisonSheet(
        verdict: verdict,
        ayahWords: _words,
        audioService: _audioService,
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MushafThemeScope(
      controller: _mushafController,
      // Listen to the controller so a preset change repaints the page. We wrap
      // in a local `Theme` (NOT a nested MaterialApp — this page is a pushed
      // route inside the app's existing navigator) so Material chrome picks up
      // the preset while the Mushaf text reads colours off the preset directly.
      child: AnimatedBuilder(
        animation: _mushafController,
        builder: (context, _) {
          final mushaf = _mushafController.theme;
          return Theme(
            data: mushaf.toThemeData(),
            child: _buildPage(mushaf),
          );
        },
      ),
    );
  }

  Widget _buildPage(MushafTheme mushaf) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: mushaf.background,
      body: SafeArea(
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _chromeVisible
                  ? _buildHeader(theme, mushaf)
                  : const SizedBox(width: double.infinity, height: 0),
            ),
            Expanded(child: _buildBody(theme, mushaf)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, MushafTheme mushaf) {
    // Tarteel-style chrome: [Surah ▾ / Page | Juz | Hizb] box, then search and
    // the theme switcher. The box opens the surah / ayah jump sheet.
    final meta = _currentMeta;
    final surah = meta?.surah ?? _surah;
    final title = surahNameEnglish(surah) ?? 'Surah $surah';
    final location = meta == null
        ? 'Loading…'
        : [
            if (meta.page != null) 'Page ${meta.page}',
            if (meta.juz != null) 'Juz ${meta.juz}',
            'Hizb ${hizbFor(meta.surah, meta.ayah)}',
          ].join(' | ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Material(
              color: mushaf.text.withValues(alpha: mushaf.isDark ? 0.08 : 0.05),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: mushaf.border.withValues(alpha: 0.8)),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _canChangePage ? () => _openQuickJump(mushaf) : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                                color: mushaf.text,
                                height: 1.2,
                              ),
                            ),
                          ),
                          Icon(Icons.arrow_drop_down_rounded,
                              color: mushaf.text.withValues(alpha: 0.7)),
                        ],
                      ),
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: mushaf.text.withValues(alpha: 0.65),
                          fontSize: 10,
                        ),
                      ),
                      Text(_mode.label,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: mushaf.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Find a verse by reciting',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const VerseIdentifierPage(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Mushaf appearance',
            onPressed: () => _showAppearance(mushaf),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Recitation history',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RecitationHistoryPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, MushafTheme mushaf) {
    switch (_ui) {
      case LiveRecitationUiState.setup:
        return _buildSetup(theme, mushaf);
      case LiveRecitationUiState.live:
        return _buildLive(theme, mushaf);
      case LiveRecitationUiState.finalizing:
        return _buildFinalizing(theme, mushaf);
      case LiveRecitationUiState.results:
        return _buildReviewPage(theme, mushaf);
      case LiveRecitationUiState.error:
        return _buildError(theme);
    }
  }

  // ─── Mushaf page (shared by setup, live and review) ─────────────────────

  /// A surah's opening, drawn inline where its ayah 1 begins: the title plate,
  /// then the Bismillah. Al-Fatiha's Bismillah IS ayah 1 (drawing it again
  /// would duplicate it) and At-Tawbah (9) has none.
  static const _surahBannerHeight = 40.0;
  static const _bismillahFontSize = 18.0;
  static const _bismillahLineHeight = 1.5;

  double _surahOpeningHeight(int surah) =>
      10 +
      _surahBannerHeight +
      (surah == 1 || surah == 9
          ? 8
          : 6 + _bismillahFontSize * _bismillahLineHeight);

  Widget _surahOpening(MushafTheme mushaf, int surah) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MushafSurahBanner(
            theme: mushaf,
            name: surahNameEnglish(surah) ?? 'Surah $surah',
            nameArabic: surahNameArabic(surah),
            height: _surahBannerHeight,
            showEnglishName: false,
          ),
          if (surah != 1 && surah != 9) ...[
            const SizedBox(height: 6),
            MushafBismillah(
              theme: mushaf,
              fontSize: _bismillahFontSize,
              lineHeight: _bismillahLineHeight,
            ),
          ] else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// The Mushaf page: framed paper with inline surah openings and the word
  /// flow, all inside ONE bounded scroll view. The frame grows with its
  /// text and scrolls as a whole at large accessibility text sizes. The mic
  /// bar has its own space below the page and cannot cover the last line.
  ///
  /// The SAME page is used before, during and after recitation — only the word
  /// states change — so tapping the mic never swaps or re-floods the text.
  Widget _buildMushafPage(
    ThemeData theme,
    MushafTheme mushaf, {
    required List<LiveWordStatus> statuses,
    required int cursor,
    bool reviewMode = false,
    ValueChanged<int>? onMistakeTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paperHeight = math.max(0.0, constraints.maxHeight - 8);
        final textHeight =
            math.max(0.0, paperHeight - (mushaf.isDark ? 8 : 34.8));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Tap anywhere on the page: hide / show the top and bottom chrome.
          onTap: () => setState(() => _chromeVisible = !_chromeVisible),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: EdgeInsets.symmetric(
                horizontal: mushaf.isDark ? 0 : 6, vertical: 4),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: paperHeight,
                  maxWidth: 620,
                ),
                child: MushafPageFrame(
                  theme: mushaf,
                  showBorder: !mushaf.isDark,
                  padding: EdgeInsets.fromLTRB(
                      8, mushaf.isDark ? 4 : 10, 8, mushaf.isDark ? 4 : 10),
                  child:
                      _loadingPage || _words.isEmpty || _revealedWords.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Text(
                                'Loading…',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: mushaf.text.withValues(alpha: 0.5),
                                ),
                              ),
                            )
                          : MushafRevealView(
                              words: _revealedWords,
                              statuses: statuses,
                              mushaf: mushaf,
                              cursor: cursor,
                              tajweedSpans: _revealedTajweedSpans,
                              tajweedEnabled: _tajweedOn,
                              ayahBoundaries: _ayahBoundaries,
                              ayahLabels: _ayahLabels,
                              lineNumbers: _wordLines,
                              ayahLineNumbers: _markerLines,
                              lineCount:
                                  _scope == RecitationScope.page && _page <= 2
                                      ? 8
                                      : 15,
                              centeredLines:
                                  _scope == RecitationScope.page && _page <= 2,
                              minimumHeight: textHeight,
                              blockHeights: {
                                for (final e in _surahStarts.entries)
                                  e.key: _surahOpeningHeight(e.value),
                              },
                              caretKey: _caretKeyFallback,
                              cursorKey: reviewMode ? null : _cursorKey,
                              reviewMode: reviewMode,
                              onMistakeTap: onMistakeTap,
                              hideUnspoken: _mode == RecitationMode.hifz,
                              blocksBefore: {
                                for (final e in _surahStarts.entries)
                                  e.key: _surahOpening(mushaf, e.value),
                              },
                            ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Setup ──────────────────────────────────────────────────────────────
  Widget _buildSetup(ThemeData theme, MushafTheme mushaf) {
    return Column(
      children: [
        Expanded(
          child: _buildMushafPage(
            theme,
            mushaf,
            statuses: _revealedStatuses,
            cursor: -1,
          ),
        ),
        _floating(FloatingRecitationBar(
          theme: mushaf,
          listening: false,
          micLabel: 'Start reciting',
          onMicTap: _loadingPage ? () {} : widget.onStartRecitation ?? _start,
          onJumpTap: () => _openQuickJump(mushaf),
          onPreviousPage:
              _canChangePage && _page > 1 ? () => _changePage(_page - 1) : null,
          onNextPage: _canChangePage && _page < 604
              ? () => _changePage(_page + 1)
              : null,
          pageLabel: '$_page / 604',
        )),
      ],
    );
  }

  bool get _canChangePage =>
      !_loadingPage && _ui == LiveRecitationUiState.setup;

  Future<void> _changePage(int page) async {
    if (!_canChangePage || page < 1 || page > 604) return;
    setState(() {
      _scope = RecitationScope.page;
      _page = page;
      _loadingPage = true;
      _clearReveal();
    });
    _scrollToTop();
    await _loadScope();
  }

  /// Jump to the complete Quran page containing the selected verse.
  Future<void> _openQuickJump(MushafTheme mushaf) async {
    if (!_canChangePage) return;
    final ayahs = await _corpus.getAyahs(_surah);
    if (!mounted || !_canChangePage) return;
    final target = await MushafJumpSheet.show(
      context,
      theme: mushaf,
      initialSurah: _surah,
      initialAyahFrom: _ayah,
      initialAyahTo: _ayah,
      initialAyahCount: ayahs.length,
      pageMode: true,
    );
    if (target == null || !mounted || !_canChangePage) return;
    final chosenSurah = await _corpus.getAyahs(target.surah);
    if (!mounted || !_canChangePage) return;
    final chosen = chosenSurah.where((a) => a.ayahNumber == target.ayahFrom);
    if (chosen.isNotEmpty) await _changePage(chosen.first.pageNumber ?? 1);
  }

  Future<void> _showAppearance(MushafTheme mushaf) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: mushaf.background,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TajweedToggle(
                value: _tajweedOn,
                theme: Theme.of(sheetContext),
                onChanged: (value) {
                  setState(() => _tajweedOn = value);
                  updateSheet(() {});
                  LocalStorageService.getInstance().then(
                    (storage) => storage.setTajweedColorsEnabled(value),
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Page theme'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  MushafThemeController.showSheet(context,
                      controller: _mushafController);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  /// Location of the ayah under the cursor (the first ayah before recitation).
  _AyahMeta? get _currentMeta {
    if (_ayahMeta.isEmpty) return null;
    final c = _liveCursor < 0 ? 0 : _liveCursor;
    for (var i = 0; i < _ayahBoundaries.length && i < _ayahMeta.length; i++) {
      if (c <= _ayahBoundaries[i]) return _ayahMeta[i];
    }
    return _ayahMeta.last;
  }

  /// Controls occupy their own space below the paper and never cover a line.
  Widget _floating(Widget bar) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      alignment: Alignment.bottomCenter,
      child: _chromeVisible ? bar : const SizedBox(width: double.infinity),
    );
  }

  // ─── Live ───────────────────────────────────────────────────────────────
  Widget _buildLive(ThemeData theme, MushafTheme mushaf) {
    return Column(
      children: [
        Expanded(
            child: Column(
          children: [
            // Status bar (self-managed LIVE timer) so the page never setStates
            // on a 1s tick (which would rebuild the reveal view).
            _LiveStatusBadge(connectionState: _service.connectionState),

            // Live "no audio" warning: if the recorder produced nothing after
            // a couple seconds, tell the user immediately (the error screen
            // would otherwise hide this until they tap Stop).
            ValueListenableBuilder<bool>(
              valueListenable: _noAudioNotifier,
              builder: (context, stalled, _) => stalled
                  ? Container(
                      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mic_off_rounded,
                              size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _service.micError != null
                                  ? 'No microphone audio. Recorder error: '
                                      '${_service.micError}'
                                  : 'No microphone audio is reaching the app. '
                                      'If microphone permission is already '
                                      'Allowed, fully close Qari and reopen '
                                      'it, then try again. Also close any '
                                      'other app using the mic (voice '
                                      'assistant, recorder, call).',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            if (kDebugMode) _buildDiagnostics(theme),

            // The continuous Mushaf page. Unspoken words are ghost ink; each
            // confirmed word turns solid in place. A tap toggles the app bar +
            // floating bar for distraction-free reading.
            Expanded(
              child: _buildMushafPage(
                theme,
                mushaf,
                statuses: _revealedStatuses,
                cursor: _liveCursor,
              ),
            ),
          ],
        )),

        // Controls sit below the page's bottom clearance, so it never
        // hides text. It slides away with the app bar on a page tap.
        _floating(FloatingRecitationBar(
          theme: mushaf,
          listening: true,
          micLabel: 'Reciting — tap to stop',
          onMicTap: _stop,
          onJumpTap: () => _openQuickJump(mushaf),
          onStop: _cancel,
          stopLabel: 'Cancel',
        )),
      ],
    );
  }

  /// Live diagnostics (so "0 of N / Duration 0s" is never a black box): mic
  /// chunks captured vs bytes actually sent to the server. Only this small
  /// Text rebuilds (via ValueNotifier), not the reveal view.
  Widget _buildDiagnostics(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: ValueListenableBuilder<int>(
        valueListenable: _micChunksNotifier,
        builder: (context, chunks, _) => ValueListenableBuilder<int>(
          valueListenable: _sentBytesNotifier,
          builder: (context, sent, _) => ValueListenableBuilder<String?>(
            valueListenable: _micErrorNotifier,
            builder: (context, err, _) => ValueListenableBuilder<bool?>(
              valueListenable: _focusNotifier,
              builder: (context, focus, _) => ValueListenableBuilder<int>(
                valueListenable: _audioOnDataNotifier,
                builder: (context, _, __) {
                  final onData = _audioOnDataNotifier.value;
                  final focusStr = focus == null
                      ? ''
                      : focus
                          ? ' · focus: yes'
                          : ' · focus: NO';
                  final statusStr = _service.nativeStatus ?? 'init';
                  final onDataErr = _service.audioOnDataError;
                  final frameType = _service.lastFrameType;
                  final sentRate = AppConstants.liveRecitationSampleRate;
                  final onDataStr = ' · onData: $onData'
                      '${frameType != null ? ' ($frameType)' : ''}'
                      ' · sentRate: $sentRate'
                      '${onDataErr != null ? ' · onDataErr: $onDataErr' : ''}';
                  return Text(
                    err != null
                        ? 'diag · mic chunks: $chunks · bytes sent: $sent · '
                            '$statusStr$focusStr$onDataStr\n'
                            'recorder error: $err'
                        : 'diag · mic chunks: $chunks · bytes sent: $sent · '
                            '$statusStr$focusStr$onDataStr',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: (err != null || focus == false)
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Review ─────────────────────────────────────────────────────────────
  /// Post-recitation review on the SAME Mushaf page (Tarteel style): verified
  /// mistakes carry a red underline inline, words never reached stay ghosted
  /// and unpenalised, and a tap on a red word opens the comparison sheet.
  Widget _buildReviewPage(ThemeData theme, MushafTheme mushaf) {
    final review = _review!;
    return Column(
      children: [
        Expanded(
            child: Column(
          children: [
            _ReviewSummary(review: review, mushaf: mushaf, theme: theme),
            Expanded(
              child: _buildMushafPage(
                theme,
                mushaf,
                statuses: review.statuses,
                cursor: review.reach,
                reviewMode: true,
                onMistakeTap: _onMistakeTapped,
              ),
            ),
          ],
        )),
        _floating(_ReviewActions(
          mushaf: mushaf,
          onRetry: _reset,
          onDone: () => Navigator.of(context).maybePop(),
        )),
      ],
    );
  }

  // ─── Error ──────────────────────────────────────────────────────────────
  Widget _buildFinalizing(ThemeData theme, MushafTheme mushaf) {
    return Column(children: [
      const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.all(10),
        child: Text('Reviewing your recitation…',
            style: theme.textTheme.bodySmall),
      ),
      Expanded(
          child: _buildMushafPage(theme, mushaf,
              statuses: _revealedStatuses, cursor: _liveCursor)),
    ]);
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64,
                color: theme.colorScheme.error.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            Text(
              'Something went wrong',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Please try again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _reset,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Target picker ───────────────────────────────────────────────────────
  Future<void> _openTargetPicker() async {
    int tempSurah = _surah;
    int tempCount = _ayahCount;

    Future<void> refreshCount(StateSetter setSheet, int surah) async {
      try {
        final ayahs = await LocalCorpusRepository().getAyahs(surah);
        if (ayahs.isNotEmpty) {
          setSheet(() {
            tempCount = ayahs.length;
          });
        }
      } catch (_) {}
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Choose a surah',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  _NumberDropdown(
                    label: 'Surah',
                    value: tempSurah,
                    count: AppConstants.totalSurahs,
                    onChanged: (v) {
                      setSheet(() => tempSurah = v);
                      refreshCount(setSheet, v);
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _surah = tempSurah;
                        _ayahCount = tempCount;
                        _ayahFrom = 1;
                        _ayahTo = tempCount;
                      });
                      _loadScope();
                    },
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: const Text('Set'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showInfoDialog(ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Live Recitation'),
        content: const Text(
          '• Recite continuously — the mic keeps listening hands-free until you '
          'tap Stop.\n\n'
          '• The page starts blank. As the engine confirms each word you say, it '
          'appears on the page — right-to-left, like a real Mushaf.\n\n'
          '• Mispronounced words show in red, skipped words in amber.\n\n'
          '• Circular markers between words show where each ayah ends.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

/// Compact score line above the review page. The score covers only the words
/// the reciter reached; words not reached are counted, never penalised.
class _ReviewSummary extends StatelessWidget {
  final RecitationReview review;
  final MushafTheme mushaf;
  final ThemeData theme;

  const _ReviewSummary({
    required this.review,
    required this.mushaf,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final evaluated = review.result.wordVerdicts.length;
    final muted = mushaf.text.withValues(alpha: 0.6);
    final String detail;
    if (evaluated == 0) {
      detail =
          'No words were recognised. Move closer to the mic and try again.';
    } else {
      final parts = <String>[
        '${review.correctCount} correct',
        '${review.mistakeCount} ${review.mistakeCount == 1 ? 'mistake' : 'mistakes'}',
        if (review.unreachedCount > 0) '${review.unreachedCount} not reached',
      ];
      detail = parts.join(' · ');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Row(
        children: [
          Text(
            evaluated == 0 ? '—' : review.result.scorePercentage,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: review.mistakeCount == 0 ? mushaf.text : mushaf.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: mushaf.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (review.mistakeCount > 0)
                  Text(
                    'Tap an underlined word to compare',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating action bar for the review page, styled like the recitation bar.
class _ReviewActions extends StatelessWidget {
  final MushafTheme mushaf;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  const _ReviewActions({
    required this.mushaf,
    required this.onRetry,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final t = mushaf;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          t.text.withValues(alpha: t.isDark ? 0.30 : 0.10),
          t.background,
        ).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: t.border.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Recite again'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live status bar: shows the LIVE timer (count-up, never auto-stops) and a
/// connecting indicator. Owns its own 1s timer + connection subscription so the
/// parent page doesn't need to [setState] every second (which would otherwise
/// rebuild the reveal view).
class _LiveStatusBadge extends StatefulWidget {
  final Stream<LiveConnectionState> connectionState;

  const _LiveStatusBadge({required this.connectionState});

  @override
  State<_LiveStatusBadge> createState() => _LiveStatusBadgeState();
}

class _LiveStatusBadgeState extends State<_LiveStatusBadge> {
  int _elapsed = 0;
  Timer? _timer;
  bool _connecting = true;
  StreamSubscription<LiveConnectionState>? _connSub;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    _connSub = widget.connectionState.listen((s) {
      if (!mounted) return;
      final connecting =
          s == LiveConnectionState.connecting || s == LiveConnectionState.idle;
      if (connecting != _connecting) setState(() => _connecting = connecting);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_connecting) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('Connecting…', style: theme.textTheme.labelMedium),
          ] else ...[
            Icon(Icons.circle, size: 10, color: theme.colorScheme.error)
                .animate(onComplete: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 700.ms)
                .fadeOut(duration: 700.ms),
            const SizedBox(width: 8),
            Text(
              'LIVE · ${_formatDuration(_elapsed)}',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NumberDropdown extends StatelessWidget {
  final String label;
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  const _NumberDropdown({
    required this.label,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(1, count < 1 ? 1 : count);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: safeValue,
          items: [
            for (var i = 1; i <= (count < 1 ? 1 : count); i++)
              DropdownMenuItem(value: i, child: Text('$i')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// Inline toggle for live per-letter tajweed colouring, mirroring the Surah
/// reader's tajweed switch so the live canvas and the reader look identical.
class _TajweedToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final ThemeData theme;

  const _TajweedToggle({
    required this.value,
    required this.onChanged,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final color = theme.colorScheme.primary;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:
              value ? color.withValues(alpha: 0.08) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value
                ? color.withValues(alpha: 0.4)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.palette_rounded, size: 20, color: value ? color : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tajweed colours',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    'Colour each letter by its tajweed rule as it appears',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: color,
            ),
          ],
        ),
      ),
    );
  }
}

/// Where one ayah sits in the Madinah Mushaf.
class _AyahMeta {
  final int surah;
  final int ayah;
  final int? page;
  final int? juz;

  const _AyahMeta({
    required this.surah,
    required this.ayah,
    this.page,
    this.juz,
  });
}
