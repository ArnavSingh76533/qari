import 'package:shared_preferences/shared_preferences.dart';

/// How the Mushaf page presents words the reciter has not said yet.
enum RecitationMode {
  /// Reading / follow-along: the whole page is visible in book ink.
  tilawat,

  /// Memorisation: unsaid words are hidden (layout preserved) and appear only
  /// once the engine confirms them.
  hifz;

  String get label => this == tilawat ? 'Tilawat' : 'Hifz';

  RecitationMode get toggled => this == tilawat ? hifz : tilawat;

  static const String _prefsKey = 'mushaf_recitation_mode';

  /// The last mode the user picked; Tilawat when nothing is stored.
  static Future<RecitationMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsKey) == hifz.name ? hifz : tilawat;
    } catch (_) {
      return tilawat;
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, name);
    } catch (_) {
      // Non-fatal: the in-memory choice still applies this session.
    }
  }
}
