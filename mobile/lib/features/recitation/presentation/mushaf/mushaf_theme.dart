import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visual identity of a Mushaf page — the four "paper" presets.
///
/// This is a deliberately small, FLAT palette (no Material ColorScheme maths)
/// because an authentic Mushaf page is typography on paper, not a Material
/// surface hierarchy. Colours are resolved once per preset and read directly by
/// [MushafRevealView] and the page chrome.
@immutable
class MushafTheme {
  final String id;
  final String label;
  final String arabicLabel;

  /// Page paper.
  final Color background;

  /// Body text (a "correct"/"unspoken" word).
  final Color text;

  /// Accent: ayah markers, the active cursor glow, primary controls.
  final Color accent;

  /// Page frame / rule lines.
  final Color border;

  /// Soft background tint behind a confirmed-correct word.
  final Color correctTint;

  /// Soft background tint behind the listening cursor.
  final Color activeTint;

  /// Foreground for a confirmed mistake (strictly behind the cursor).
  final Color mismatchInk;

  /// The colour of a decorative Bismillah / surah banner glyph.
  final Color ornament;

  const MushafTheme({
    required this.id,
    required this.label,
    required this.arabicLabel,
    required this.background,
    required this.text,
    required this.accent,
    required this.border,
    required this.correctTint,
    required this.activeTint,
    required this.mismatchInk,
    required this.ornament,
  });

  bool get isDark =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

  /// Faint "ghost ink" for a word the reciter has NOT said yet.
  ///
  /// The text stays readable as guidance, but is clearly dimmer than a
  /// confirmed word, so a pre-rendered page never looks as if it was already
  /// recognised before the reciter spoke (Tarteel's upcoming-text treatment).
  Color get ghostInk => text.withValues(alpha: isDark ? 0.30 : 0.32);

  /// Maps onto a Flutter [ThemeData] so Material widgets in the same subtree
  /// (app bar, bottom sheet, buttons) adopt the same paper.
  ThemeData toThemeData() {
    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: accent,
      onPrimary: isDark ? const Color(0xFF1A1409) : Colors.white,
      secondary: accent,
      onSecondary: isDark ? const Color(0xFF1A1409) : Colors.white,
      error: mismatchInk,
      onError: Colors.white,
      surface: background,
      onSurface: text,
      surfaceContainerHighest:
          Color.alphaBlend(accent.withValues(alpha: 0.06), background),
      outline: border,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? const Color(0xFF2A2622) : const Color(0xFF2C221E),
        contentTextStyle:
            TextStyle(color: isDark ? const Color(0xFFEDE7DE) : Colors.white),
      ),
    );
  }

  // ── The four presets ─────────────────────────────────────────────────────

  /// 1. Classic Madinah — warm cream paper, charcoal ink, soft gold accent.
  static const classic = MushafTheme(
    id: 'classic',
    label: 'Classic Madinah',
    arabicLabel: 'المدينة',
    background: Color(0xFFFFFDF5),
    text: Color(0xFF1A1A1A),
    accent: Color(0xFFB8860B),
    border: Color(0xFFD8C89A),
    correctTint: Color(0xFFE8F5E9),
    activeTint: Color(0xFFFFF3D0),
    mismatchInk: Color(0xFFB3261E),
    ornament: Color(0xFFB8860B),
  );

  /// 2. Night / OLED — deep obsidian, crisp warm white, warm amber accent.
  static const night = MushafTheme(
    id: 'night',
    label: 'Night / OLED',
    arabicLabel: 'ليلي',
    background: Color(0xFF121212),
    text: Color(0xFFE8E6E3),
    accent: Color(0xFFD4A373),
    border: Color(0xFF3A342C),
    correctTint: Color(0xFF1B3B2B),
    activeTint: Color(0xFF3A2E1C),
    mismatchInk: Color(0xFFCF6679),
    ornament: Color(0xFFD4A373),
  );

  /// 3. Parchment / Sepia — warm sepia, espresso ink, terracotta accent.
  static const parchment = MushafTheme(
    id: 'parchment',
    label: 'Parchment / Sepia',
    arabicLabel: 'ورقي',
    background: Color(0xFFF4ECD8),
    text: Color(0xFF2C221E),
    accent: Color(0xFFB05A3C),
    border: Color(0xFFC9B48C),
    correctTint: Color(0xFFE6EFDF),
    activeTint: Color(0xFFF6E3C8),
    mismatchInk: Color(0xFF9B3A22),
    ornament: Color(0xFFB05A3C),
  );

  /// 4. Minimal Pure White — pure white paper, jet black ink. No accent needed
  /// beyond a neutral, so the active cursor uses a soft grey wash.
  static const minimal = MushafTheme(
    id: 'minimal',
    label: 'Minimal White',
    arabicLabel: 'أبيض',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    accent: Color(0xFF5A5A5A),
    border: Color(0xFFE2E2E2),
    correctTint: Color(0xFFE8F5E9),
    activeTint: Color(0xFFF0F0F0),
    mismatchInk: Color(0xFFC5221F),
    ornament: Color(0xFF9A9A9A),
  );

  static const List<MushafTheme> all = <MushafTheme>[
    classic,
    night,
    parchment,
    minimal
  ];

  static MushafTheme byId(String? id) =>
      all.firstWhere((t) => t.id == id, orElse: () => classic);
}

/// Holds the user's selected Mushaf preset and persists it locally.
///
/// Read at startup with [load] (called once from `LiveRecitationPage.initState`);
/// writes happen only on explicit user selection, so there is nothing to debounce.
class MushafThemeController extends ChangeNotifier {
  static const String _prefsKey = 'mushaf_theme_id';

  MushafTheme _theme = MushafTheme.classic;
  bool _loaded = false;

  MushafTheme get theme => _theme;
  bool get isLoaded => _loaded;

  /// Reads the persisted preset. Safe to call more than once.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _theme = MushafTheme.byId(prefs.getString(_prefsKey));
    } catch (_) {
      // A storage failure must never block reading — fall back to Classic.
      _theme = MushafTheme.classic;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Selects a preset and persists it.
  Future<void> select(MushafTheme next) async {
    if (next.id == _theme.id) return;
    _theme = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, next.id);
    } catch (_) {
      // Non-fatal: the in-memory selection still applies this session.
    }
  }

  /// The bottom sheet listing the four presets.
  static Future<void> showSheet(
    BuildContext context, {
    MushafThemeController? controller,
  }) {
    final pageController = controller ?? MushafThemeScope.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: pageController.theme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SingleChildScrollView(
        child: _MushafThemeSheet(controller: pageController),
      ),
    );
  }
}

/// Provides the [MushafThemeController] to the subtree.
class MushafThemeScope extends InheritedNotifier<MushafThemeController> {
  const MushafThemeScope({
    super.key,
    required MushafThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static MushafThemeController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MushafThemeScope>();
    assert(scope != null, 'No MushafThemeScope found in context');
    return scope!.notifier!;
  }

  /// The theme itself (convenience for widgets that only need colours).
  static MushafTheme themeOf(BuildContext context) => of(context).theme;
}

class _MushafThemeSheet extends StatelessWidget {
  const _MushafThemeSheet({required this.controller});

  final MushafThemeController controller;

  @override
  Widget build(BuildContext context) {
    final t = controller.theme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: t.text.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Mushaf appearance',
              style: TextStyle(
                color: t.text,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'اختر مظهر المصحف',
              style: TextStyle(
                  color: t.text.withValues(alpha: 0.55), fontSize: 13),
            ),
            const SizedBox(height: 14),
            for (final option in MushafTheme.all)
              _ThemeOptionTile(
                option: option,
                selected: option.id == t.id,
                onTap: () async {
                  await controller.select(option);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final MushafTheme option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: option.text.withValues(alpha: selected ? 0.07 : 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? option.accent
                  : option.text.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // A live paper/ink swatch, so the choice is obvious.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: option.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: option.border, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  'ق',
                  style: TextStyle(
                    color: option.text,
                    fontSize: 20,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        color: option.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      option.arabicLabel,
                      style: TextStyle(
                        color: option.text.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: option.accent, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
