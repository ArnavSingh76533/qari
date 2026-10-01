import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:qari/core/theme/app_theme.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'helpers/mushaf_paragraph_helpers.dart';

void expectRtlRows(WidgetTester tester, {required String reason}) {
  final paragraph = tester.getRect(find.byType(MushafRevealView));
  final rows = mushafTextRows(tester);
  expect(rows, isNotEmpty, reason: reason);
  final view = tester.widget<MushafRevealView>(find.byType(MushafRevealView));
  final lines =
      tester.widgetList<MushafParagraph>(find.byType(MushafParagraph)).toList();
  expect(rows.length, lines.length,
      reason: '$reason: a fitted line must never wrap');
  var end = -1;
  for (var i = 0; i < rows.length; i++) {
    end += lines[i].wordSpans.length;
    if (!view.surahEnds.contains(end)) {
      expect(rows[i].left, closeTo(paragraph.left, 1),
          reason: '$reason row ${i + 1}: fitted left margin must be flush');
    }
    expect(rows[i].left, greaterThanOrEqualTo(paragraph.left - 0.5),
        reason: '$reason row ${i + 1}: text stays within the left margin');
    expect(rows[i].right, closeTo(paragraph.right, 1),
        reason: '$reason row ${i + 1}: text starts at the RTL margin');
  }
  expectNaturalMushafSpaces(tester, reason: reason);
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [320.0, 500.0]) {
    testWidgets('short final lines retain natural spacing at width $width',
        (tester) async {
      const words = ['كَفَرُوا۟', 'سَوَآءٌ', 'عَلَيْهِمْ'];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: MushafRevealView(
              words: words,
              statuses: const [],
              mushaf: MushafTheme.classic,
              fontSize: 20,
              minimumHeight: 180,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(mushafWords(), words);
      expect(mushafTextRows(tester).length, 1);
      expectRtlRows(tester, reason: 'short line at width $width');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('an ayah marker wraps with its final word', (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ'];
    var width = -1.0;
    for (final word in words) {
      final painter = TextPainter(
        text: TextSpan(
          text: word,
          style: AppTheme.arabicTextStyle(fontSize: 20)
              .copyWith(fontSize: 20, height: 1.65),
        ),
        textDirection: TextDirection.rtl,
      )..layout();
      width += painter.width;
      painter.dispose();
    }
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: const MushafRevealView(
            words: words,
            statuses: [],
            mushaf: MushafTheme.classic,
            fontSize: 20,
            ayahBoundaries: [2],
            ayahLabels: ['1'],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final word = mushafWordRect(tester, words.length - 1);
    final marker = mushafRect(tester, find.text('١'));
    expect(word.top, greaterThan(mushafWordRect(tester, 0).top),
        reason: 'the fixture must exercise wrapping at the final word');
    expect(marker.top, lessThan(word.bottom),
        reason: 'the end marker must share its final word row');
    expect(marker.bottom, greaterThan(word.top),
        reason: 'the end marker must not become a separate line');
    expect(word.left - marker.right, inInclusiveRange(0.0, 6.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('printed lines fit narrow paper with enlarged text',
      (tester) async {
    final words = List.generate(9, (i) => 'ءَأَنذَرْتَهُمْ');
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SizedBox(
          width: 200,
          child: MushafRevealView(
            words: words,
            statuses: const [],
            mushaf: MushafTheme.classic,
            minimumHeight: 500,
            lineEnds: const [8],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(mushafWords(), words);
    final rects = mushafWordRects(tester);
    expect(rects.length, words.length);
    final paragraph = tester.getRect(find.byType(MushafRevealView));
    for (final rect in rects) {
      expect(rect.isEmpty, isFalse);
      expect(rect.left, greaterThanOrEqualTo(paragraph.left - 0.5));
      expect(rect.right, lessThanOrEqualTo(paragraph.right + 0.5));
      expect(rect.top, greaterThanOrEqualTo(paragraph.top - 0.5));
      expect(rect.bottom, lessThanOrEqualTo(paragraph.bottom + 0.5));
    }
    expect(mushafTextRows(tester).length, 1,
        reason: 'the one-line budget must retain every word');
    expectRtlRows(tester, reason: '200px paper at double text scale');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a long surah keeps readable text and scrolls', (tester) async {
    final words = List.filled(500, 'ءَأَنذَرْتَهُمْ');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: MushafRevealView(
          words: words,
          statuses: const [],
          mushaf: MushafTheme.classic,
          minimumHeight: 400),
    ))));
    await tester.pumpAndSettle();
    final paragraph =
        tester.widget<MushafParagraph>(find.byType(MushafParagraph).first);
    expect(paragraph.text.style!.fontSize, greaterThanOrEqualTo(13));
    expect(mushafWords(), words);
    expect(
        tester.getSize(find.byType(MushafRevealView)).height, greaterThan(400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('surah openings retain measured heights at large text scale',
      (tester) async {
    for (final surah in [2, 112]) {
    await tester.pumpWidget(MaterialApp(home: LiveRecitationPage(
      surahNumber: surah, ayahNumber: 1, initialMode: RecitationMode.tilawat)));
    await tester.pumpAndSettle();
    final source = tester.widget<MushafRevealView>(find.byType(MushafRevealView));
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!),
      home: Scaffold(body: SizedBox(width: 360, height: 600,
        child: SingleChildScrollView(controller: scroll,
          child: MushafRevealView(words: source.words, statuses: const [],
            mushaf: source.mushaf, fontSize: source.fontSize, minimumHeight: 500,
            lineEnds: source.lineEnds, surahEnds: source.surahEnds,
            ayahBoundaries: source.ayahBoundaries, ayahLabels: source.ayahLabels,
            blocksBefore: source.blocksBefore, blockHeights: source.blockHeights))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
      reason: 'fixed opening heights must not overflow at 2× system text scale');
    final opening = find.byWidget(source.blocksBefore[0]!);
    final openingBounds = mushafRect(tester, opening);
    for (final text in find.descendant(of: opening, matching: find.byType(Text)).evaluate()) {
      final bounds = mushafRect(tester, find.byWidget(text.widget));
      expect(bounds.top, greaterThanOrEqualTo(openingBounds.top - 0.5));
      expect(bounds.bottom, lessThanOrEqualTo(openingBounds.bottom + 0.5));
    }
    expect(mushafWords(), source.words);
    expect(mushafWordRect(tester, 0).top, greaterThanOrEqualTo(openingBounds.bottom));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final last = mushafWordRect(tester, source.words.length - 1);
    expect(last.bottom, lessThanOrEqualTo(600));
    expect(last.top, greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    }
  });

  for (final size in [const Size(360, 740), const Size(430, 932)]) {
    for (final target in [
      (page: 1, surah: 1, ayah: 1, theme: 'classic'),
      (page: 3, surah: 2, ayah: 6, theme: 'night'),
      (page: 6, surah: 2, ayah: 30, theme: 'classic'),
      (page: 84, surah: 4, ayah: 34, theme: 'classic'),
      (page: 587, surah: 82, ayah: 1, theme: 'classic'),
      (page: 604, surah: 112, ayah: 1, theme: 'classic'),
    ]) {
      testWidgets('page ${target.page} has natural RTL body spacing at $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({
          'mushaf_theme_id': target.theme,
          'tajweed_colors_enabled': target.page == 84
        });
        final preview = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: preview,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: LiveRecitationPage(
              surahNumber: target.surah,
              ayahNumber: target.ayah,
              initialMode: RecitationMode.tilawat,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('CAPTURE_QURAN_UI')) {
          final boundary = preview.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
                'build/review/quran-page${target.page}-${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(find.textContaining('Page ${target.page} |'), findsOneWidget);
        final view =
            tester.widget<MushafRevealView>(find.byType(MushafRevealView));
        expect(mushafWords(), view.words);
        final frame = tester.getRect(find.byType(MushafPageFrame));
        final rows = mushafTextRows(tester);
        if (target.page == 3) {
          expect(rows.length, 15,
              reason: 'Page 3 must retain fifteen text rows');
        }
        for (final rect in rows) {
          expect(rect.left, greaterThanOrEqualTo(frame.left));
          expect(rect.right, lessThanOrEqualTo(frame.right));
          expect(rect.top, greaterThanOrEqualTo(frame.top));
          expect(rect.bottom, lessThanOrEqualTo(frame.bottom));
        }
        expectRtlRows(tester, reason: 'page ${target.page} at $size');
        // Every verse marker remains on the same row as its final body word.
        final bodyRects = mushafWordRects(tester);
        final markerTexts = find.descendant(
          of: find.byType(MushafParagraph),
          matching: find.byType(Text),
        );
        final markerRects = <String, List<Rect>>{};
        for (final element in markerTexts.evaluate()) {
          final text = element.widget as Text;
          if (text.data == null || !RegExp(r'^[٠-٩]+$').hasMatch(text.data!))
            continue;
          markerRects
              .putIfAbsent(text.data!, () => [])
              .add(mushafRect(tester, find.byWidget(text)));
        }
        final used = <String, int>{};
        for (var i = 0; i < view.ayahBoundaries.length; i++) {
          final label = toArabicIndicDigits(view.ayahLabels[i]);
          final occurrence = used[label] ?? 0;
          used[label] = occurrence + 1;
          expect(markerRects[label], isNotNull,
              reason: 'missing marker $label');
          final marker = markerRects[label]![occurrence];
          final word = bodyRects[view.ayahBoundaries[i]];
          expect(marker.top, lessThan(word.bottom));
          expect(marker.bottom, greaterThan(word.top));
          expect(word.left - marker.right, inInclusiveRange(-0.5, 6.1),
              reason:
                  'ayah $label marker must remain tightly after its final word');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
