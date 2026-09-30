import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('KFGQPCUthmanicHafs')
      ..addFont(rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf'));
    await font.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({
        'mushaf_recitation_mode': 'tilawat',
      }));

  testWidgets('AI recitation always opens in Hifz despite the saved mode',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LiveRecitationPage()));
    await tester.pumpAndSettle();
    expect(tester.widget<MushafRevealView>(find.byType(MushafRevealView))
        .hideUnspoken, isTrue);
    expect(find.byTooltip('Tilawat: full page visible. Tap for Hifz'), findsNothing);
    expect(find.byTooltip('Hifz: unsaid words hidden. Tap for Tilawat'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tilawat stays visible and has no cross-mode switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({'mushaf_recitation_mode': 'hifz'});
    await tester.pumpWidget(const MaterialApp(
      home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<MushafRevealView>(find.byType(MushafRevealView))
        .hideUnspoken, isFalse);
    expect(find.byTooltip('Tilawat: full page visible. Tap for Hifz'), findsNothing);
    expect(find.text('Tajweed colours'), findsNothing,
        reason: 'appearance settings must not consume page height');
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(360, 740), const Size(430, 932), const Size(800, 1100)]) {
    testWidgets('Quran sheet fills available height at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(
        home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
      ));
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byType(MushafPageFrame));
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      expect(page.height, greaterThan(size.height * .70),
          reason: 'Quran must fill the viewport instead of a short card');
      expect(page.bottom, closeTo(bar.top, 18));
      expect(tester.getRect(find.text('٧')).bottom,
          greaterThan(page.bottom - 80),
          reason: 'Quran lines should use the whole sheet');
      expect(tester.getRect(find.text('٧')).bottom, lessThanOrEqualTo(bar.top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('page navigation loads the next Quran page without changing mode',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Page 1 |'), findsOneWidget);
    await tester.tap(find.byTooltip('Next Quran page'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Page 2 |'), findsOneWidget);
    expect(tester.widget<MushafRevealView>(find.byType(MushafRevealView))
        .hideUnspoken, isFalse);
    expect(find.text('سُورَةُ البقرة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
