import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/data/models/word_model.dart';
import 'package:qari/data/repositories/local_corpus_repository.dart';
import 'package:qari/data/repositories/mushaf_layout_repository.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'mushaf_text_helpers.dart';

void main() {
  final words = <String>[];
  final rows = <int>[];
  final boundaries = <int>[];
  final markerRows = <int>[];
  final labels = <String>[];
  final expected = <String>[];

  setUpAll(() async {
    await (FontLoader('KFGQPCUthmanicHafs')
          ..addFont(
              rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf')))
        .load();
    final layout = await MushafLayoutRepository().load();
    final ayahs = await LocalCorpusRepository().getAyahsByPage(3);
    for (final ayah in ayahs) {
      final printed = layout[ayah.reference]!;
      for (var i = 0; i < printed.words.length; i++) {
        words.add(ayah.words[i].text);
        rows.add(printed.words[i].line);
        expected.add(mushafDisplayText(ayah.words[i].text));
      }
      boundaries.add(words.length - 1);
      markerRows.add(printed.marker.line);
      labels.add(ayah.ayahNumber.toString());
      expected.add(ayahMarkerText(labels.last));
    }
  });

  Widget page({int cursor = -1, bool hidden = false, GlobalKey? anchor}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 560,
            child: MushafRevealView(
              words: words,
              statuses: List.filled(words.length, LiveWordStatus.matched),
              lineNumbers: rows,
              ayahBoundaries: boundaries,
              ayahLabels: labels,
              ayahLineNumbers: markerRows,
              minimumHeight: 560,
              mushaf: MushafTheme.night,
              cursor: cursor,
              cursorKey: anchor,
              hideUnspoken: hidden,
            ),
          ),
        ),
      );

  for (final width in [320.0, 360.0, 430.0]) {
    testWidgets('printed 15 lines remain flush at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(page());
      expect(find.byType(FittedBox), findsNWidgets(15));
      expect(mushafUnitTexts(tester), expected);
      expect(find.byType(Wrap), findsNothing);
      expect(find.byType(Spacer), findsNothing);
      final body = tester.getRect(find.byType(MushafRevealView));
      final paragraphs = mushafParagraphElements(tester);
      for (var line = 1; line <= 15; line++) {
        final rowFinder = find.byKey(ValueKey('mushaf-line-$line'));
        final elements = find
            .descendant(of: rowFinder, matching: find.byType(RichText))
            .evaluate()
            .toList();
        final first = (elements.first.widget as RichText).text.toPlainText();
        final last = (elements.last.widget as RichText).text.toPlainText();
        final boxes = [rectOf(tester, first), rectOf(tester, last, last: true)];
        // Measure the row's own paragraphs to avoid repeated-word ambiguity.
        final rowRect = tester.getRect(rowFinder);
        final firstBox = elements.first.renderObject! as RenderBox;
        final lastBox = elements.last.renderObject! as RenderBox;
        expect(firstBox.localToGlobal(Offset(firstBox.size.width, 0)).dx,
            closeTo(body.right, 0.1));
        expect(lastBox.localToGlobal(Offset.zero).dx, closeTo(body.left, 0.1));
        expect(rowRect.height, closeTo(560 / 15, 0.01));
        expect(boxes.every((box) => box.bottom <= body.bottom + 1), isTrue);
      }
      expect(paragraphs.length, words.length + labels.length);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small word gaps follow the font and whole-line transform',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    final units = find
        .descendant(
            of: find.byKey(const ValueKey('mushaf-line-1')),
            matching: find.byType(RichText))
        .evaluate()
        .toList();
    final first = units[0].renderObject! as RenderBox;
    final second = units[1].renderObject! as RenderBox;
    final gap = first.localToGlobal(Offset.zero).dx -
        second.localToGlobal(Offset(second.size.width, 0)).dx;
    final painter = TextPainter(
      text: TextSpan(
          text: String.fromCharCode(0x20),
          style: (units.first.widget as RichText).text.style),
      textDirection: TextDirection.rtl,
    )..layout();
    final scale = first.getTransformTo(null).entry(0, 0);
    expect(gap, closeTo(painter.width * .30 * scale, .1));
    expect(gap, greaterThan(.5));
    expect(gap, lessThan(3));
    painter.dispose();
  });

  testWidgets('Arabic ink is 15 percent larger within unchanged line pitch',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    final first =
        mushafParagraphElements(tester).first.renderObject! as RenderBox;
    final transform = first.getTransformTo(null);
    const oldScale = (560 / 15) / (32 * 1.55);
    expect(transform.entry(1, 1), closeTo(oldScale * 1.15, 0.00001));
    expect(tester.getSize(find.byType(MushafRevealView)).height, 560);
  });

  testWidgets('opening lines share a scale and regular-page glyph height',
      (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MushafRevealView(
      words: ['بِسْمِ', 'ٱللَّهِ', 'ٱلرَّحْمَٰنِ', 'ٱلرَّحِيمِ'],
      statuses: [],
      lineNumbers: [2, 2, 3, 3],
      centeredLines: true,
      lineCount: 8,
      minimumHeight: 560,
      mushaf: MushafTheme.night,
    ))));
    final paragraphs = mushafParagraphElements(tester).toList();
    final first =
        (paragraphs.first.renderObject! as RenderBox).getTransformTo(null);
    final last =
        (paragraphs.last.renderObject! as RenderBox).getTransformTo(null);
    expect(first.entry(0, 0), closeTo(last.entry(0, 0), 0.00001));
    expect(first.entry(1, 1), closeTo(last.entry(1, 1), 0.00001));
    expect(first.entry(1, 1),
        closeTo((560 / 15) / (32 * MushafRevealView.baseLineHeight), 0.00001));
    expect(tester.getSize(find.byType(MushafRevealView)).height, 560);
  });

  testWidgets('scaled cursor and Hifz keep the same word geometry',
      (tester) async {
    final anchor = GlobalKey();
    await tester.pumpWidget(page(cursor: 17, anchor: anchor));
    final before = [for (final word in words.toSet()) rectOf(tester, word)];
    final active = rectOf(tester, words[17]);
    final box = anchor.currentContext!.findRenderObject()! as RenderBox;
    expect((box.localToGlobal(Offset.zero) - active.topRight).distance,
        lessThan(0.5));
    await tester.pumpWidget(page(cursor: 17, hidden: true, anchor: anchor));
    expect([for (final word in words.toSet()) rectOf(tester, word)], before);
    expect(inkOf(tester, words.last)?.a, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verse marker may occupy the next printed row', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MushafRevealView(
      words: ['ٱلْحَمْدُ', 'لِلَّهِ'],
      statuses: [LiveWordStatus.pending, LiveWordStatus.pending],
      lineNumbers: [1, 2],
      ayahBoundaries: [0, 1],
      ayahLabels: ['2', '3'],
      ayahLineNumbers: [2, 2],
      lineCount: 2,
      minimumHeight: 180,
      mushaf: MushafTheme.classic,
    ))));
    final word = rectOf(tester, 'ٱلْحَمْدُ');
    final marker = rectOf(tester, '٢');
    expect(marker.top, greaterThan(word.top));
    expect(marker.right, greaterThan(rectOf(tester, 'لِلَّهِ').right));
    expect(countOf(tester, '٢'), 1);
  });

  testWidgets('a surah range remains readable across several printed pages',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: MushafRevealView(
        words: List.generate(45, (_) => 'ٱلْحَمْدُ'),
        statuses: List.filled(45, LiveWordStatus.pending),
        lineNumbers: List.generate(45, (i) => i + 16),
        minimumHeight: 560,
        mushaf: MushafTheme.classic,
      ),
    ))));
    expect(tester.getSize(find.byType(MushafRevealView)).height,
        closeTo(1680, 0.1));
    expect(tester.getSize(find.byKey(const ValueKey('mushaf-line-16'))).height,
        closeTo(560 / 15, 0.01));
    expect(tester.takeException(), isNull);
  });
}
