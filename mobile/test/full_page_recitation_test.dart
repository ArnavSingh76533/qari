import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'mushaf_text_helpers.dart';

void reportPageGeometry(WidgetTester tester) {
  if (!const bool.fromEnvironment('CAPTURE_QURAN_UI')) return;
  final finder = find.byType(MushafRevealView);
  final view = tester.widget<MushafRevealView>(finder);
  final paragraph = mushafParagraphElements(tester).first.widget as RichText;
  final context = mushafParagraphElements(tester).first;
  final painter = TextPainter(
    text: TextSpan(text: view.words.first, style: paragraph.text.style),
    textDirection: TextDirection.rtl,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  debugPrint(
      'Quran geometry: paper=${view.minimumHeight}, flow=${tester.getSize(finder)}, font=${mushafFontSize(tester)}, lineHeight=${paragraph.text.style?.height}, word=${rectOf(tester, view.words.first).size}, measured=${painter.size}, blocks=${view.blocksBefore.entries.map((e) => '${e.key}:${tester.getSize(find.byWidget(e.value)).height}').join(',')}');
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

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'mushaf_recitation_mode': 'tilawat',
      if (const String.fromEnvironment('MUSHAF_CAPTURE_THEME') == 'night') ...{
        'mushaf_theme_id': 'night',
        'tajweed_colors_enabled': true,
      },
    });
  });

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
        final shadows = debugDisableShadows;
        try {
          debugDisableShadows = false;
          boundary.markNeedsPaint();
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/review/quran-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        } finally {
          debugDisableShadows = shadows;
        }
      }
      final page = tester.getRect(find.byType(MushafPageFrame));
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      expect(page.height, greaterThan(size.height * .70),
          reason: 'Quran must fill the viewport instead of a short card');
      expect(page.bottom, closeTo(bar.top, 18));
      final lastMarker = rectOf(tester, ayahMarkerText('7'));
      expect(lastMarker.bottom, greaterThan(page.bottom - 80),
          reason: 'Quran lines should use the whole sheet');
      expect(lastMarker.bottom, lessThanOrEqualTo(bar.top));
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
    (1, 1, 1, '٧'),
    (2, 2, 1, '٥'),
    (3, 2, 6, '١٦'),
    (4, 2, 17, '٢٤'),
    (5, 2, 25, '٢٩'),
    (6, 2, 30, '٣٧'),
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
        final shadows = debugDisableShadows;
        try {
          debugDisableShadows = false;
          boundary.markNeedsPaint();
          await tester.pump();
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/review/quran-page-${target.$1}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        } finally {
          debugDisableShadows = shadows;
        }
      }
      expect(find.textContaining('Page ${target.$1} |'), findsOneWidget);
      final page = tester.getRect(find.byType(MushafPageFrame));
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      final marker = rectOf(tester, target.$4, last: true);
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

  testWidgets('Tajweed colours restore and preserve the full-page layout',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tajweed_colors_enabled', true);
    await tester.pumpWidget(const MaterialApp(
      home: LiveRecitationPage(
          surahNumber: 80, initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MushafRevealView>(find.byType(MushafRevealView))
            .tajweedEnabled,
        isTrue);
    final before = rectOf(tester, ayahMarkerText('40'), last: true);
    await tester.tap(find.byTooltip('Mushaf appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Tajweed colours'))).pop();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<MushafRevealView>(find.byType(MushafRevealView))
            .tajweedEnabled,
        isFalse);
    expect(rectOf(tester, ayahMarkerText('40'), last: true), before,
        reason: 'colour changes must preserve the Quran word layout');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('appearance menu changes the Quran page theme', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mushaf appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page theme'));
    await tester.pumpAndSettle();
    expect(find.text(MushafTheme.night.label), findsOneWidget);
    await tester.tap(find.text(MushafTheme.night.label));
    await tester.pumpAndSettle();
    expect(tester.widget<MushafPageFrame>(find.byType(MushafPageFrame)).theme,
        MushafTheme.night);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('all 604 Quran pages fit above the recitation controls',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tajweed_colors_enabled', true);
    final data = await rootBundle.load('assets/quran_corpus.json.gz');
    final corpus = jsonDecode(utf8.decode(gzip.decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))))
        as Map<String, dynamic>;
    final starts = <int, (int, int)>{};
    for (final surah in corpus['surahs'] as List<dynamic>) {
      for (final ayah in surah['ayahs'] as List<dynamic>) {
        starts.putIfAbsent(ayah['page_number'] as int,
            () => (ayah['surah_number'] as int, ayah['ayah_number'] as int));
      }
    }
    expect(starts.keys.toSet(), {for (var page = 1; page <= 604; page++) page});
    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LiveRecitationPage(initialMode: RecitationMode.tilawat),
    ));
    await tester.pumpAndSettle();
    final failures = <String>[];
    for (var page = 1; page <= 604; page++) {
      if (page > 1) {
        await tester.tap(find.byTooltip('Next Quran page'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Page $page |'), findsOneWidget);
      final reveal =
          tester.widget<MushafRevealView>(find.byType(MushafRevealView));
      expect(reveal.tajweedEnabled, isTrue,
          reason: 'page $page restores Tajweed');
      final controls = tester.getRect(find.byType(FloatingRecitationBar));
      final position =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final lastBottom =
          rectOf(tester, ayahMarkerText(reveal.ayahLabels.last), last: true)
              .bottom;
      if (lastBottom > controls.top || position.maxScrollExtent > 2) {
        final font = mushafFontSize(tester);
        failures.add('page $page: font=$font, words=${reveal.words.length}, '
            'scroll=${position.maxScrollExtent}, last=$lastBottom, bar=${controls.top}');
      }
      expect(tester.takeException(), isNull, reason: 'page $page');
    }
    expect(failures, isEmpty, reason: failures.join('\n'));
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 6)));
}
