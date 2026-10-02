import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

/// Wrapper around SharedPreferences for persistent app settings.
/// Handles onboarding state, language, path, theme, font scale, qari,
/// auth token, and audio consent.
class LocalStorageService {
  static LocalStorageService? _instance;
  late SharedPreferences _prefs;

  LocalStorageService._();

  static Future<LocalStorageService> getInstance() async {
    if (_instance == null) {
      _instance = LocalStorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  // For synchronous access in the app widget
  LocalStorageService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Synchronous access to the underlying [SharedPreferences] store. Use with
  /// care before [ensureInitialized] has resolved (reads may return defaults).
  SharedPreferences get prefs => _prefs;

  // Ensure prefs are loaded
  Future<void> ensureInitialized() async {
    try {
      _prefs.getString('');
    } catch (_) {
      _prefs = await SharedPreferences.getInstance();
    }
  }

  // ─── Keys ────────────────────────────────────────────────────────────────
  static const _kOnboardingComplete = 'onboarding_complete';
  static const _kSelectedLanguage = 'selected_language';
  static const _kSelectedPath = 'selected_path';
  static const _kIsOnboarded = 'is_onboarded';
  static const _kThemeMode = 'theme_mode';
  static const _kFontScale = 'font_scale';
  static const _kSelectedQari = 'selected_qari';
  static const _kAuthToken = 'auth_token';
  static const _kAudioConsent = 'audio_consent';
  static const _kGrammarColorsEnabled = 'grammar_colors_enabled';
  static const _kTajweedColorsEnabled = 'tajweed_colors_enabled';
  static const _kDensityLevel = 'density_level';
  static const _kTranslationLanguage = 'translation_language';
  static const _kPlayTranslationAudio = 'play_translation_audio';
  static const _kUserId = 'user_id';
  static const _kDailyGoal = 'daily_goal';
  static const _kStreakCount = 'streak_count';
  static const _kDataVersion = 'backend_data_version';
  static const _kDisplayName = 'display_name';
  static const _kUserEmail = 'user_email';
  static const _kCompletedLessons = 'completed_lessons';
  static const _kLocalXp = 'local_xp';

  // ─── Onboarding ──────────────────────────────────────────────────────────
  Future<bool> isOnboardingComplete() async {
    await ensureInitialized();
    return _prefs.getBool(_kOnboardingComplete) ?? false;
  }

  Future<void> setOnboardingComplete(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kOnboardingComplete, value);
  }

  /// Whether the server-side onboarding (language + path) is finished.
  Future<bool> isOnboarded() async {
    await ensureInitialized();
    return _prefs.getBool(_kIsOnboarded) ?? false;
  }

  Future<void> setIsOnboarded(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kIsOnboarded, value);
  }

  // ─── Language ────────────────────────────────────────────────────────────
  Future<String?> getSelectedLanguage() async {
    await ensureInitialized();
    return _prefs.getString(_kSelectedLanguage);
  }

  Future<void> setSelectedLanguage(String code) async {
    await ensureInitialized();
    await _prefs.setString(_kSelectedLanguage, code);
  }

  // ─── Learning Path ───────────────────────────────────────────────────────
  Future<String?> getSelectedPath() async {
    await ensureInitialized();
    return _prefs.getString(_kSelectedPath);
  }

  Future<void> setSelectedPath(String path) async {
    await ensureInitialized();
    await _prefs.setString(_kSelectedPath, path);
  }

  // ─── Theme ───────────────────────────────────────────────────────────────
  Future<String> getThemeMode() async {
    await ensureInitialized();
    return _prefs.getString(_kThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    await ensureInitialized();
    await _prefs.setString(_kThemeMode, mode);
  }

  // ─── Font Scale ──────────────────────────────────────────────────────────
  Future<double> getFontScale() async {
    await ensureInitialized();
    return _prefs.getDouble(_kFontScale) ?? 1.0;
  }

  Future<void> setFontScale(double scale) async {
    await ensureInitialized();
    await _prefs.setDouble(_kFontScale, scale);
  }

  // ─── Qari (Reciter) ──────────────────────────────────────────────────────
  Future<String> getSelectedQari() async {
    await ensureInitialized();
    return _prefs.getString(_kSelectedQari) ?? 'abdul_basit';
  }

  Future<void> setSelectedQari(String qari) async {
    await ensureInitialized();
    await _prefs.setString(_kSelectedQari, qari);
  }

  // ─── Auth Token ──────────────────────────────────────────────────────────
  Future<String?> getAuthToken() async {
    await ensureInitialized();
    return _prefs.getString(_kAuthToken);
  }

  Future<void> setAuthToken(String? token) async {
    await ensureInitialized();
    if (token != null) {
      await _prefs.setString(_kAuthToken, token);
    } else {
      await _prefs.remove(_kAuthToken);
    }
  }

  // ─── Audio Consent ───────────────────────────────────────────────────────
  Future<bool> getAudioConsent() async {
    await ensureInitialized();
    return _prefs.getBool(_kAudioConsent) ?? false;
  }

  Future<void> setAudioConsent(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kAudioConsent, value);
  }

  // ─── Grammar Colors ──────────────────────────────────────────────────────
  Future<bool> getGrammarColorsEnabled() async {
    await ensureInitialized();
    return _prefs.getBool(_kGrammarColorsEnabled) ?? true;
  }

  Future<void> setGrammarColorsEnabled(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kGrammarColorsEnabled, value);
  }

  // ─── Tajweed Colors ──────────────────────────────────────────────────────
  Future<bool> getTajweedColorsEnabled({bool defaultValue = false}) async {
    await ensureInitialized();
    return _prefs.getBool(_kTajweedColorsEnabled) ?? defaultValue;
  }

  Future<void> setTajweedColorsEnabled(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kTajweedColorsEnabled, value);
  }

  /// Synchronous read of the tajweed toggle — safe to call from [initState]
  /// before [ensureInitialized] resolves (reads the in-memory prefs if ready,
  /// else falls back to the default).
  bool getTajweedColorsEnabledSync() {
    try {
      return _prefs.getBool(_kTajweedColorsEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ─── Density Level ───────────────────────────────────────────────────────
  /// 0 = Arabic only, 1 = +translit, 2 = +word meaning, 3 = +full translation
  Future<int> getDensityLevel() async {
    await ensureInitialized();
    return _prefs.getInt(_kDensityLevel) ?? 1;
  }

  Future<void> setDensityLevel(int level) async {
    await ensureInitialized();
    await _prefs.setInt(_kDensityLevel, level);
  }

  // ─── Translation Language (Surah view) ──────────────────────────────────
  /// 'en' or 'ur' — which tarjuma to show in the Quran reader.
  Future<String> getTranslationLanguage() async {
    await ensureInitialized();
    return _prefs.getString(_kTranslationLanguage) ?? 'en';
  }

  Future<void> setTranslationLanguage(String code) async {
    await ensureInitialized();
    await _prefs.setString(_kTranslationLanguage, code);
  }

  // ─── Play Translation Audio ─────────────────────────────────────────────
  Future<bool> getPlayTranslationAudio() async {
    await ensureInitialized();
    return _prefs.getBool(_kPlayTranslationAudio) ?? false;
  }

  Future<void> setPlayTranslationAudio(bool value) async {
    await ensureInitialized();
    await _prefs.setBool(_kPlayTranslationAudio, value);
  }

  // ─── User ID ─────────────────────────────────────────────────────────────
  Future<String?> getUserId() async {
    await ensureInitialized();
    return _prefs.getString(_kUserId);
  }

  Future<void> setUserId(String? id) async {
    await ensureInitialized();
    if (id != null) {
      await _prefs.setString(_kUserId, id);
    } else {
      await _prefs.remove(_kUserId);
    }
  }

  // ─── Display name / email (local-first identity) ─────────────────────────
  // Cached at signup/login and refreshed whenever a /me fetch succeeds, so
  // the Home greeting and Profile header can show the name INSTANTLY and
  // offline — never a spinner blocked on the backend.
  Future<String?> getDisplayName() async {
    await ensureInitialized();
    return _prefs.getString(_kDisplayName);
  }

  Future<void> setDisplayName(String? name) async {
    await ensureInitialized();
    if (name != null && name.isNotEmpty) {
      await _prefs.setString(_kDisplayName, name);
    } else {
      await _prefs.remove(_kDisplayName);
    }
  }

  Future<String?> getUserEmail() async {
    await ensureInitialized();
    return _prefs.getString(_kUserEmail);
  }

  Future<void> setUserEmail(String? email) async {
    await ensureInitialized();
    if (email != null && email.isNotEmpty) {
      await _prefs.setString(_kUserEmail, email);
    } else {
      await _prefs.remove(_kUserEmail);
    }
  }

  // ─── Local lesson progress (offline-first curriculum) ────────────────────
  // The bundled curriculum tracks completion + XP locally so learning works
  // with an unreachable backend; the backend can sync on top later.
  Future<Set<String>> getCompletedLessonIds() async {
    await ensureInitialized();
    return (_prefs.getStringList(_kCompletedLessons) ?? const []).toSet();
  }

  Future<void> addCompletedLesson(String lessonId, int xp) async {
    await ensureInitialized();
    final done = (_prefs.getStringList(_kCompletedLessons) ?? []).toSet();
    if (done.add(lessonId)) {
      await _prefs.setStringList(_kCompletedLessons, done.toList());
      await _prefs.setInt(_kLocalXp, (_prefs.getInt(_kLocalXp) ?? 0) + xp);
    }
  }

  Future<int> getLocalXp() async {
    await ensureInitialized();
    return _prefs.getInt(_kLocalXp) ?? 0;
  }

  // ─── Daily Goal ──────────────────────────────────────────────────────────
  Future<int> getDailyGoal() async {
    await ensureInitialized();
    return _prefs.getInt(_kDailyGoal) ?? 5;
  }

  Future<void> setDailyGoal(int goal) async {
    await ensureInitialized();
    await _prefs.setInt(_kDailyGoal, goal);
  }

  // ─── Streak ──────────────────────────────────────────────────────────────
  Future<int> getStreakCount() async {
    await ensureInitialized();
    return _prefs.getInt(_kStreakCount) ?? 0;
  }

  Future<void> setStreakCount(int count) async {
    await ensureInitialized();
    await _prefs.setInt(_kStreakCount, count);
  }

  // ─── Backend data version ─────────────────────────────────────────────────
  /// Bumped on the backend whenever corpus/content changes. The app compares
  /// this against the release manifest so it can refresh cached content when
  /// the backend data changes (the "auto-update content" behaviour).
  Future<int> getBackendDataVersion() async {
    await ensureInitialized();
    return _prefs.getInt(_kDataVersion) ?? 0;
  }

  Future<void> setBackendDataVersion(int version) async {
    await ensureInitialized();
    await _prefs.setInt(_kDataVersion, version);
  }

  // ─── Clear All ───────────────────────────────────────────────────────────
  Future<void> clearAll() async {
    await ensureInitialized();
    await _prefs.clear();
  }

  // ─── Clear Cached Progress ───────────────────────────────────────────────
  /// Removes only the locally cached *progress/state* values (streak, daily
  /// goal, cached backend data version) so a freshly authenticated user lands
  /// on a clean slate and the home/profile screens refetch real server data.
  /// Auth token, user id, onboarding flag, theme and other preferences are
  /// intentionally preserved.
  Future<void> clearProgressCache() async {
    await ensureInitialized();
    await _prefs.remove(_kStreakCount);
    await _prefs.remove(_kDailyGoal);
    await _prefs.remove(_kDataVersion);
  }
}
