import 'package:flutter/material.dart';

/// Central configuration for the Qari app.
class AppConstants {
  AppConstants._();

  // ─── API ────────────────────────────────────────────────────────────────
  /// Base URL for the core API.
  ///
  /// Production backend is hosted on the VPS and reached over HTTPS on :443
  /// using its public IP. The app accepts the self-signed cert (see
  /// ApiClient) so this works without a public CA:
  ///   https://qari.pneumetron.com/v1  →  /v1/auth/signup
  ///
  /// Reached via Cloudflare (publicly-trusted TLS) to the VPS nginx, which
  /// proxies `/v1` to the core API. The `/v1` prefix is required (the backend
  /// mounts every route under `/v1`).
  ///
  /// For local development on an emulator, override at run time, e.g.:
  ///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
  static String get baseUrl {
    const env = String.fromEnvironment('API_BASE_URL');
    if (env.isNotEmpty) return env;
    return 'https://qari.pneumetron.com/v1';
  }

  /// WebSocket base URL for real-time recitation streaming.
  ///
  /// Derived from [baseUrl]: swaps `http(s)` → `ws(s)` and drops the `/v1`
  /// suffix (WebSocket routes are mounted at `/ws/...`, not under `/v1`).
  /// Override at run time with `--dart-define=WS_BASE_URL=ws://10.0.2.2:8001`.
  static String get wsBaseUrl {
    const env = String.fromEnvironment('WS_BASE_URL');
    if (env.isNotEmpty) return env;
    var ws = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    ws = ws.replaceFirst(RegExp(r'/v1/?$'), '');
    return ws;
  }

  /// Full endpoint for the live recitation streaming WebSocket.
  static String get recitationStreamWsUrl => '$wsBaseUrl/ws/recitation/stream';

  /// DEV-ONLY: native crashes are POSTed here so they can be inspected from
  /// the VPS logs without pulling device logs. Points at our recitation-api's
  /// `/v1/recitations/debug_echo` (VPS host). Empty disables echoing.
  static String get debugEchoUrl {
    const env = String.fromEnvironment('DEBUG_ECHO_URL');
    if (env.isNotEmpty) return env;
    return '$baseUrl/recitations/debug_echo';
  }

  /// Host whose self-signed TLS cert the app trusts (see ApiClient / the
  /// streaming service's custom HttpClient). Empty = trust no extra host.
  /// TLS is terminated by Cloudflare with a publicly-trusted certificate, so
  /// no self-signed pinning is needed anymore. Kept as an empty string for
  /// backward compatibility with the trust callback.
  static const String trustedSelfSignedHost = '';
  /// Public Quran audio CDN (everyayah.com) — hosts per-ayah MP3s for many
  /// reciters. The previous `audio.qari.app` host does not resolve (it produced
  /// the "0 source error" / "Audio not available" toast in the reader).
  static const String audioCdnUrl = 'https://everyayah.com/data';
  /// CDN base for Urdu (Shamshad Ali Khan) translation audio. Mirrors the
  /// everyayah.com per-ayah MP3 layout used for Arabic recitation; the app
  /// constructs `{base}/{surah}{ayah}.mp3` (3-digit zero-padded) just like
  /// [audioCdnUrl] so Urdu tarjuma audio can be queued after the Arabic.
  /// NOTE: the Urdu tarjuma folder lives under everyayah's `/data/translations/`
  /// path — not directly under `/data/` (that returns 404).
  static const String urduTranslationCdnUrl =
      'https://everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps';
  static const int apiTimeoutSeconds = 90;
  /// Longer timeout specifically for the (potentially large) recitation audio
  /// upload + long-running AI analysis poll.
  static const int recitationApiTimeoutSeconds = 180;

  // ─── Supported Languages ────────────────────────────────────────────────
  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      script: 'Latin',
      textDirection: TextDirection.ltr,
      locale: Locale('en'),
    ),
    AppLanguage(
      code: 'ur',
      name: 'Urdu',
      nativeName: 'اردو',
      script: 'Nastaliq',
      textDirection: TextDirection.rtl,
      locale: Locale('ur'),
    ),
    AppLanguage(
      code: 'ar',
      name: 'Arabic',
      nativeName: 'العربية',
      script: 'Arabic',
      textDirection: TextDirection.rtl,
      locale: Locale('ar'),
    ),
  ];

  static List<Locale> get supportedLocales =>
      supportedLanguages.map((l) => l.locale).toList();

  /// Resolves a stored language code to its [Locale], defaulting to English.
  static Locale localeForCode(String? code) {
    if (code == null) return const Locale('en');
    final match = supportedLanguages.where((l) => l.code == code);
    return match.isNotEmpty ? match.first.locale : const Locale('en');
  }

  // ─── Quran ──────────────────────────────────────────────────────────────
  static const int totalSurahs = 114;
  static const int totalAyahs = 6236;
  /// Standard 15-line Madani Mushaf has 604 pages. Used by the continuous
  /// full-page (Mushaf) recitation scope.
  static const int totalQuranPages = 604;
  static const int bismillahAyahNumber = 0;
  static const String bismillahText = 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ';

  // Arabic font
  static const String arabicFontFamily = 'KFGQPCUthmanicHafs';
  static const double arabicFontMinSize = 22.0;
  static const double arabicFontMaxSize = 40.0;
  static const double arabicFontDefaultSize = 28.0;

  // UI font
  static const String uiFontFamily = 'NotoSans';
  static const String urduFontFamily = 'NotoNastaliqUrdu';
  // Arabic UI font (clean sans for buttons/menus/labels). The bundled
  // Uthmanic font (arabicFontFamily) is reserved for actual Quran text.
  static const String arabicUiFontFamily = 'NotoSansArabic';

  // ─── Grammar Color Coding ───────────────────────────────────────────────
  /// pos_group -> (color, underlineStyle)
  /// Fi'l (verb) = green + solid underline
  /// Ism (noun) = blue + no underline
  /// Harf (particle) = amber + dotted underline
  static const Map<String, GrammarColorConfig> grammarColors = {
    'fil': GrammarColorConfig(
      posGroup: 'fil',
      label: "Fi'l",
      labelUrdu: 'فعل',
      color: Color(0xFF2E7D32),
      underlineStyle: UnderlineStyle.solid,
    ),
    'ism': GrammarColorConfig(
      posGroup: 'ism',
      label: 'Ism',
      labelUrdu: 'اسم',
      color: Color(0xFF1565C0),
      underlineStyle: UnderlineStyle.none,
    ),
    'harf': GrammarColorConfig(
      posGroup: 'harf',
      label: 'Harf',
      labelUrdu: 'حرف',
      color: Color(0xFFFF8F00),
      underlineStyle: UnderlineStyle.dotted,
    ),
    'ism_mudaf': GrammarColorConfig(
      posGroup: 'ism_mudaf',
      label: 'Ism (Mudaf)',
      labelUrdu: 'اسم (مضاف)',
      color: Color(0xFF1565C0),
      underlineStyle: UnderlineStyle.none,
    ),
    'fiil_madi': GrammarColorConfig(
      posGroup: 'fiil_madi',
      label: "Fi'l Madi",
      labelUrdu: 'فعل ماضی',
      color: Color(0xFF2E7D32),
      underlineStyle: UnderlineStyle.solid,
    ),
    'fiil_mudari': GrammarColorConfig(
      posGroup: 'fiil_mudari',
      label: "Fi'l Mudari'",
      labelUrdu: 'فعل مضارع',
      color: Color(0xFF2E7D32),
      underlineStyle: UnderlineStyle.solid,
    ),
    'fiil_amr': GrammarColorConfig(
      posGroup: 'fiil_amr',
      label: "Fi'l Amr",
      labelUrdu: 'فعل امر',
      color: Color(0xFF2E7D32),
      underlineStyle: UnderlineStyle.solid,
    ),
    'harf_jarr': GrammarColorConfig(
      posGroup: 'harf_jarr',
      label: 'Harf Jarr',
      labelUrdu: 'حرف جر',
      color: Color(0xFFFF8F00),
      underlineStyle: UnderlineStyle.dotted,
    ),
    'harf_nasb': GrammarColorConfig(
      posGroup: 'harf_nasb',
      label: 'Harf Nasb',
      labelUrdu: 'حرف نصب',
      color: Color(0xFFFF8F00),
      underlineStyle: UnderlineStyle.dotted,
    ),
    'default': GrammarColorConfig(
      posGroup: 'default',
      label: 'Other',
      labelUrdu: 'دیگر',
      color: Color(0xFF616161),
      underlineStyle: UnderlineStyle.none,
    ),
  };

  // ─── Tajweed Colors ─────────────────────────────────────────────────────
  // Keyed by the Quran.com v4 tajweed markup class names (the `rule` field of
  // each tajweed span produced by scripts/build_local_corpus.py), so the
  // reader can colour each letter by its exact rule.
  static const Map<String, Color> tajweedColors = {
    'ham_wasl': Color(0xFF607D8B),
    'laam_shamsiyah': Color(0xFF00897B),
    'madda_normal': Color(0xFF1B5E20),
    'madda_permissible': Color(0xFF2E7D32),
    'madda_obligatory': Color(0xFF1B5E20),
    'madda_necessary': Color(0xFF0B3D0B),
    'slnt': Color(0xFF558B2F),
    'ghunnah': Color(0xFF00838F),
    'ikhafa': Color(0xFFAD1457),
    'ikhafa_shafawi': Color(0xFFC2185B),
    'qalaqah': Color(0xFF37474F),
    'idgham_ghunnah': Color(0xFF7B1FA2),
    'idgham_wo_ghunnah': Color(0xFF8E24AA),
    'idgham_shafawi': Color(0xFF6A1B9A),
    'idgham_mutajanisayn': Color(0xFF9C27B0),
    'iqlab': Color(0xFFEF6C00),
    'normal': Color(0xFF212121),
  };

  /// Friendly English labels for the tajweed rule classes, used in the legend
  /// and the word detail sheet. Falls back to the raw class name.
  static const Map<String, String> tajweedRuleLabels = {
    'ham_wasl': 'Hamzat al-Wasl',
    'laam_shamsiyah': 'Lam Shamsiyyah',
    'madda_normal': 'Madd (Natural)',
    'madda_permissible': "Madd Ja'iz",
    'madda_obligatory': 'Madd Wajib',
    'madda_necessary': 'Madd Lazim',
    'slnt': 'Madd (Silent)',
    'ghunnah': 'Ghunnah',
    'ikhafa': 'Ikhfa',
    'ikhafa_shafawi': 'Ikhfa Shafawi',
    'qalaqah': 'Qalqalah',
    'idgham_ghunnah': 'Idgham + Ghunnah',
    'idgham_wo_ghunnah': 'Idgham',
    'idgham_shafawi': 'Idgham Shafawi',
    'idgham_mutajanisayn': 'Idgham',
    'iqlab': 'Iqlab',
    'normal': 'Normal',
  };

  // ─── Audio ──────────────────────────────────────────────────────────────
  static const List<double> supportedPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const double defaultPlaybackSpeed = 1.0;
  static const List<String> availableReciters = [
    'abdul_basit',
    'sudais',
    'minshawi',
    'husary',
    'afasy',
  ];

  // ─── SRS (Spaced Repetition) ────────────────────────────────────────────
  static const int sm2GradeBhoolGaya = 1;   // Again
  static const int sm2GradeMushkil = 3;     // Hard
  static const int sm2GradeAasaan = 5;      // Easy
  static const int flashcardSessionCap = 20;
  static const double sm2InitialEase = 2.5;
  static const int sm2InitialInterval = 1;

  // ─── Recitation ─────────────────────────────────────────────────────────
  static const int maxRecordingDurationSeconds = 120;
  static const int recitationPollIntervalMs = 2000;
  static const int recitationMaxPollAttempts = 60;
  static const double minConfidenceThreshold = 0.55;
  static const double maxNoiseThreshold = 0.35;

  // ─── Live Recitation (real-time streaming / Memorization Mode) ───────────
  /// PCM sample rate streamed to the backend (mono 16-bit).
  static const int liveRecitationSampleRate = 16000;
  /// Interval between keep-alive ping frames on the streaming socket so a long
  /// hands-free session is never dropped by the proxy during quiet pauses.
  static const int liveRecitationPingIntervalSeconds = 20;
  /// Bars shown in the always-listening bottom mic visualizer.
  static const int liveVisualizerBarCount = 40;

  // ─── Scholar ────────────────────────────────────────────────────────────
  static const int maxScholarAudioSeconds = 120;
  static const List<String> scholarTopics = [
    'Tajweed',
    'Qirat',
    'Meaning / Tafsir',
    'Arabic Grammar',
    'Pronunciation',
    'Other',
  ];

  // ─── UI ─────────────────────────────────────────────────────────────────
  static const int bottomNavTabCount = 4;
  static const double bottomNavElevation = 8.0;
  static const double cardBorderRadius = 24.0;
  static const double sheetBorderRadius = 24.0;
}

/// Represents a supported app language.
class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String script;
  final TextDirection textDirection;
  final Locale locale;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.script,
    required this.textDirection,
    required this.locale,
  });
}

/// Underline style for grammar color-coding (color-blind accessible).
enum UnderlineStyle { none, solid, dotted }

/// Configuration for a grammar part-of-speech group.
class GrammarColorConfig {
  final String posGroup;
  final String label;
  final String labelUrdu;
  final Color color;
  final UnderlineStyle underlineStyle;

  const GrammarColorConfig({
    required this.posGroup,
    required this.label,
    required this.labelUrdu,
    required this.color,
    required this.underlineStyle,
  });
}

/// Learning path types.
enum LearningPath { foundation, quranDirect }

/// App theme types.
enum AppThemeMode { light, dark, highContrast }

/// Recitation state machine states.
enum RecitationState {
  idle,
  listening,
  recording,
  analyzing,
  results,
  errorMicDenied,
  errorTooNoisy,
  errorLowConfidence,
  errorAnalysisFailed,
}
