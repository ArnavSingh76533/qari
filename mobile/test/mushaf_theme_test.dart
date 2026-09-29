import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import '../lib/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import '../lib/features/recitation/presentation/mushaf/mushaf_theme.dart';
import '../lib/features/recitation/presentation/mushaf/surah_titles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MushafTheme presets', () {
    test('exposes exactly the four documented presets', () {
      expect(
        MushafTheme.all.map((t) => t.id).toList(),
        ['classic', 'night', 'parchment', 'minimal'],
      );
    });

    test('matches the specified paper / ink / accent colours', () {
      expect(MushafTheme.classic.background, const Color(0xFFFFFDF5));
      expect(MushafTheme.classic.text, const Color(0xFF1A1A1A));
      expect(MushafTheme.classic.accent, const Color(0xFFB8860B));

      expect(MushafTheme.night.background, const Color(0xFF121212));
      expect(MushafTheme.night.text, const Color(0xFFE8E6E3));
      expect(MushafTheme.night.accent, const Color(0xFFD4A373));

      expect(MushafTheme.parchment.background, const Color(0xFFF4ECD8));
      expect(MushafTheme.parchment.text, const Color(0xFF2C221E));

      expect(MushafTheme.minimal.background, const Color(0xFFFFFFFF));
      expect(MushafTheme.minimal.text, const Color(0xFF000000));
    });

    test('correct tint is green in light and dark presets', () {
      // Spec: #E8F5E9 in light, #1B3B2B in dark.
      expect(MushafTheme.classic.correctTint, const Color(0xFFE8F5E9));
      expect(MushafTheme.night.correctTint, const Color(0xFF1B3B2B));
      // A correct word must never reuse the error ink.
      for (final t in MushafTheme.all) {
        expect(t.correctTint, isNot(t.mismatchInk));
      }
    });

    test('classifies brightness correctly for every preset', () {
      expect(MushafTheme.classic.isDark, isFalse);
      expect(MushafTheme.night.isDark, isTrue);
      expect(MushafTheme.parchment.isDark, isFalse);
      expect(MushafTheme.minimal.isDark, isFalse);
    });

    test('byId falls back to Classic for unknown or null ids', () {
      expect(MushafTheme.byId('night'), MushafTheme.night);
      expect(MushafTheme.byId(null).id, 'classic');
      expect(MushafTheme.byId('does-not-exist').id, 'classic');
    });

    test('toThemeData keeps paper as scaffold background', () {
      for (final t in MushafTheme.all) {
        final data = t.toThemeData();
        expect(data.scaffoldBackgroundColor, t.background);
        expect(data.colorScheme.primary, t.accent);
        expect(data.colorScheme.surface, t.background);
      }
    });
  });

  group('MushafThemeController persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('defaults to Classic before load()', () {
      final c = MushafThemeController();
      expect(c.theme.id, 'classic');
      expect(c.isLoaded, isFalse);
    });

    test('persists a selection and restores it on the next launch', () async {
      final c = MushafThemeController();
      await c.load();
      await c.select(MushafTheme.night);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('mushaf_theme_id'), 'night');

      // Simulate a relaunch: a brand new controller reads the stored value.
      final restored = MushafThemeController();
      await restored.load();
      expect(restored.theme.id, 'night');
      expect(restored.isLoaded, isTrue);
    });

    test('selecting the already-active theme is a no-op', () async {
      final c = MushafThemeController();
      await c.load();
      var notified = 0;
      c.addListener(() => notified++);
      await c.select(MushafTheme.classic);
      expect(notified, 0);
    });
  });

  group('Surah titles', () {
    test('resolves well-known surahs and rejects out-of-range', () {
      expect(surahNameArabic(1), 'الفاتحة');
      expect(surahNameArabic(114), 'الناس');
      expect(surahNameArabic(0), isNull);
      expect(surahNameArabic(115), isNull);
      expect(surahNameArabic(null), isNull);
    });

    test('covers all 114 surahs', () {
      for (var i = 1; i <= 114; i++) {
        expect(surahNameArabic(i), isNotNull, reason: 'missing surah $i');
      }
    });
  });

  group('MushafPageFrame', () {
    Widget _frameHost(MushafTheme t, {bool border = true}) {
      return MaterialApp(
        theme: t.toThemeData(),
        home: Scaffold(
          body: MushafPageFrame(
            theme: t,
            showBorder: border,
            showBismillah: true,
            surahName: 'Al-Fatihah',
            surahNameArabic: 'الفاتحة',
            surahMeta: 'Page 1',
            child: const Text('بسم الله'),
          ),
        ),
      );
    }

    testWidgets('renders the surah banner and Bismillah', (tester) async {
      await tester.pumpWidget(_frameHost(MushafTheme.classic));
      // Calligraphic plate: "سُورَةُ <name>" set in the Hafs face.
      expect(find.text('سُورَةُ الفاتحة'), findsOneWidget);
      expect(find.text('Al-Fatihah'), findsOneWidget);
      expect(find.textContaining(MushafBismillah.bismillah), findsOneWidget);
      // The body text is present and is NOT wrapped in its own card.
      expect(find.text('بسم الله'), findsOneWidget);
    });

    testWidgets('omits the banner when no surah name is given', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MushafTheme.classic.toThemeData(),
          home: Scaffold(
            body: MushafPageFrame(
              theme: MushafTheme.classic,
              child: const Text('صفحة'),
            ),
          ),
        ),
      );
      expect(find.textContaining('سُورَةُ'), findsNothing);
      expect(find.text('صفحة'), findsOneWidget);
    });

    testWidgets('page border can be turned off', (tester) async {
      await tester.pumpWidget(_frameHost(MushafTheme.classic, border: false));
      expect(find.text('بسم الله'), findsOneWidget);
      // With the frame off there is no second (inset hairline) container.
      final bordered = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .length;
      expect(bordered, lessThan(3));
    });
  });

  group('FloatingRecitationBar', () {
    Widget _barHost({
      required MushafTheme theme,
      required bool listening,
      VoidCallback? onStop,
    }) {
      return MaterialApp(
        theme: theme.toThemeData(),
        home: Scaffold(
          body: FloatingRecitationBar(
            theme: theme,
            listening: listening,
            onMicTap: () {},
            onJumpTap: () {},
            onStop: onStop,
          ),
        ),
      );
    }

    testWidgets('shows mic + jump, and stop only when provided',
        (tester) async {
      await tester.pumpWidget(
        _barHost(theme: MushafTheme.classic, listening: false),
      );
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
    });

    testWidgets('mic becomes a waveform glyph and stop appears while live',
        (tester) async {
      await tester.pumpWidget(
        _barHost(theme: MushafTheme.classic, listening: true, onStop: () {}),
      );
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    testWidgets('tapping the mic fires the callback', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: MushafTheme.classic.toThemeData(),
          home: Scaffold(
            body: FloatingRecitationBar(
              theme: MushafTheme.classic,
              listening: true,
              onMicTap: () => taps++,
              onJumpTap: () {},
              onStop: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('the pulse halo animates ONLY while listening', (tester) async {
      const halo = ValueKey<String>('mushaf-mic-halo');
      await tester.pumpWidget(
        _barHost(theme: MushafTheme.night, listening: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(halo),
        findsOneWidget,
        reason: 'expected the pulse halo to render while listening',
      );

      await tester.pumpWidget(
        _barHost(theme: MushafTheme.night, listening: false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(halo),
        findsNothing,
        reason: 'idle bar must not animate',
      );
    });
  });
}
