import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void reportPageGeometry(WidgetTester tester) {
  if (!const bool.fromEnvironment('CAPTURE_QURAN_UI')) return;
  final finder = find.byType(MushafRevealView);
  final view = tester.widget<MushafRevealView>(finder);
  final wordFinder =
      find.descendant(of: finder, matching: find.text(view.words.first)).first;
  final word = tester.widget<Text>(wordFinder);
  final context = tester.element(wordFinder);
  final painter = TextPainter(
    text: TextSpan(text: view.words.first, style: word.style),
    textDirection: TextDirection.rtl,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  debugPrint(
      'Quran geometry: paper=${view.minimumHeight}, flow=${tester.getSize(finder)}, font=${word.style?.fontSize}, word=${tester.getSize(wordFinder)}, measured=${painter.size}, blocks=${view.blocksBefore.entries.map((e) => '${e.key}:${tester.getSize(find.byWidget(e.value)).height}').join(',')}');
  painter.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final font = FontLoader('KFGQPCUthmanicHafs')
      ..addFont(rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Flutter CI exposes the SDK's platform fonts. Load the real Android UI
    // face alongside the bundled Quran face instead of test-only Ahem boxes.
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final roboto = FontLoader('Roboto')
        ..addFont(File(
                '$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf')
            .readAsBytes()
            .then((bytes) => ByteData.sublistView(bytes)));
      await roboto.load();
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({
        'mushaf_recitation_mode': 'tilawat',
      }));

  testWidgets('AI recitation always opens in Hifz despite the saved mode',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LiveRecitationPage()));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MushafRevealView>(find.byType(MushafRevealView))
            .hideUnspoken,
        isTrue);
    expect(find.byTooltip('Tilawat: full page visible. Tap for Hifz'),
        findsNothing);
    expect(find.byTooltip('Hifz: unsaid words hidden. Tap for Tilawat'),
        findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tilawat stays visible and has no cross-mode switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({'mushaf_recitation_mode': 'hifz'});
    await tester.pumpWidget(const MaterialApp(
      home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MushafRevealView>(find.byType(MushafRevealView))
            .hideUnspoken,
        isFalse);
    expect(find.byTooltip('Tilawat: full page visible. Tap for Hifz'),
        findsNothing);
    expect(find.text('Tajweed colours'), findsNothing,
        reason: 'appearance settings must not consume page height');
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(360, 740),
    const Size(430, 932),
    const Size(800, 1100)
  ]) {
    testWidgets('Quran sheet fills available height at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preview = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: preview,
          child: const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
          )));
      await tester.pumpAndSettle();
      reportPageGeometry(tester);
      if (const bool.fromEnvironment('CAPTURE_QURAN_UI')) {
        final boundary =
            preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/review/quran-${size.width.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final page = tester.getRect(find.byType(MushafPageFrame));
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      expect(page.height, greaterThan(size.height * .70),
          reason: 'Quran must fill the viewport instead of a short card');
      expect(page.bottom, closeTo(bar.top, 18));
      expect(
          tester.getRect(find.text('٧')).bottom, greaterThan(page.bottom - 80),
          reason: 'Quran lines should use the whole sheet');
      expect(tester.getRect(find.text('٧')).bottom, lessThanOrEqualTo(bar.top));
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.maxScrollExtent, lessThanOrEqualTo(2),
          reason: 'idle scroll anchors must not add a blank line to the page');
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
    expect(
        tester
            .widget<MushafRevealView>(find.byType(MushafRevealView))
            .hideUnspoken,
        isFalse);
    expect(find.text('سُورَةُ البقرة'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final target in [
    (48, 2, 282, '٢٨٢'),
    (501, 45, 23, '٣٢'),
    (576, 74, 19, '٤٧'),
    (585, 80, 1, '٤٠'),
    (591, 86, 1, '١٠'),
    (601, 103, 1, '٥'),
    (604, 112, 1, '٦')
  ]) {
    testWidgets('complete page ${target.$1} fits with all verse markers',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preview = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: LiveRecitationPage(
                surahNumber: target.$2,
                ayahNumber: target.$3,
                initialMode: RecitationMode.tilawat),
          )));
      await tester.pumpAndSettle();
      reportPageGeometry(tester);
      if (const bool.fromEnvironment('CAPTURE_QURAN_UI')) {
        final boundary =
            preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/review/quran-page-${target.$1}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.textContaining('Page ${target.$1} |'), findsOneWidget);
      final page = tester.getRect(find.byType(MushafPageFrame));
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      final marker = tester.getRect(find.text(target.$4).last);
      expect(marker.bottom, lessThanOrEqualTo(bar.top));
      expect(page.bottom, lessThanOrEqualTo(bar.top));
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      expect(position.maxScrollExtent, lessThanOrEqualTo(2),
          reason:
              'the complete Quran page must fit above its controls at standard text size');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
