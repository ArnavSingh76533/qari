import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/mushaf_paragraph_helpers.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('KFGQPCUthmanicHafs')
          ..addFont(
              rootBundle.load('assets/fonts/KFGQPCUthmanicHafs-Regular.otf')))
        .load();
  });

  testWidgets('body uses the printed word boundaries for separate RTL lines',
      (tester) async {
    final words = List.generate(
        30,
        (i) => [
              'إِنَّ',
              'ٱلَّذِينَ',
              'كَفَرُوا۟',
              'سَوَآءٌ',
              'عَلَيْهِمْ'
            ][i % 5]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 320,
      child: MushafRevealView(
          words: words,
          statuses: const [],
          mushaf: MushafTheme.classic,
          minimumHeight: 500,
          lineEnds: const [4, 14, 29]),
    ))));
    await tester.pumpAndSettle();
    final body = find.byType(MushafRevealView);
    expect(
        find.descendant(of: body, matching: find.byType(Wrap)), findsNothing);
    expect(mushafWords(), words);
    final paragraphs = tester
        .widgetList<MushafParagraph>(find.byType(MushafParagraph))
        .toList();
    expect(paragraphs.length, 3,
        reason: 'printed line data must define the three shaped lines');
    expect(paragraphs.map((p) => p.wordSpans.length), [5, 10, 15]);
    for (final paragraph in paragraphs) {
      expect(paragraph.textDirection, TextDirection.rtl);
      expect(paragraph.textAlign, isNot(TextAlign.justify));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('every body line fills both margins without expanded spaces',
      (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 320,
      child: MushafRevealView(
          words: words,
          statuses: const [],
          mushaf: MushafTheme.classic,
          fontSize: 20,
          lineEnds: const [3]),
    ))));
    await tester.pumpAndSettle();
    final frame = tester.getRect(find.byType(MushafRevealView));
    for (final row in mushafTextRows(tester)) {
      expect(row.left, closeTo(frame.left, 0.5),
          reason: 'whole-line fitting must remove the ragged left margin');
      expect(row.right, closeTo(frame.right, 0.5));
    }
    expectNaturalMushafSpaces(tester, reason: 'dense Mushaf rows');
    expect(tester.takeException(), isNull);
  });

  testWidgets('only a true surah ending keeps its natural width',
      (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'];
    Future<Rect> row({required bool endsSurah}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: MushafRevealView(
                      words: words,
                      statuses: const [],
                      mushaf: MushafTheme.classic,
                      fontSize: 20,
                      lineEnds: const [3],
                      surahEnds: endsSurah ? const [3] : const [],
                      ayahBoundaries: const [3],
                      ayahLabels: const ['7'])))));
      await tester.pumpAndSettle();
      expectNaturalMushafSpaces(tester, reason: 'surah-ending exception');
      return mushafTextRows(tester).single;
    }

    final continuing = await row(endsSurah: false);
    expect(continuing.left, closeTo(0, 0.5));
    expect(continuing.right, closeTo(320, 0.5));
    final ending = await row(endsSurah: true);
    expect(ending.left, greaterThan(100),
        reason: 'a short surah ending must not expand');
    expect(ending.right, closeTo(320, 0.5));
    expect(ending.height, lessThan(continuing.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'surah opening starts a new line and preserves the preceding ending',
      (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'];
    const opening = SizedBox(height: 40, child: Text('Next surah'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                child: const MushafRevealView(
                    words: words,
                    statuses: [],
                    mushaf: MushafTheme.classic,
                    lineEnds: [3],
                    surahEnds: [1],
                    blocksBefore: {2: opening},
                    blockHeights: {2: 40})))));
    await tester.pumpAndSettle();
    final rows = mushafTextRows(tester);
    expect(rows.length, 2);
    expect(mushafWords(), words);
    expect(mushafRect(tester, find.text('Next surah')).top,
        greaterThan(rows.first.bottom));
    expect(mushafRect(tester, find.text('Next surah')).bottom,
        lessThan(rows.last.top));
    expect(rows.last.left, closeTo(0, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid or incomplete printed metadata never loses a word',
      (tester) async {
    final words = List.filled(19, 'ءَأَنذَرْتَهُمْ');
    for (final ends in [
      <int>[],
      [3],
      [4, 2, 50]
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: SizedBox(
                      width: 200,
                      child: MushafRevealView(
                          words: words,
                          statuses: const [],
                          mushaf: MushafTheme.classic,
                          lineEnds: ends))))));
      await tester.pumpAndSettle();
      expect(mushafWords(), words);
      expect(mushafTextRows(tester).length, greaterThan(1));
      expect(mushafWordRects(tester),
          everyElement(predicate<Rect>((r) => r.width > 0)));
      expectNaturalMushafSpaces(tester, reason: 'fallback for $ends');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'scaled line keeps review taps and cursor on source word geometry',
      (tester) async {
    const words = ['ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ'];
    final cursor = GlobalKey();
    int? tapped;
    Future<void> render(bool review) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: MushafRevealView(
                      words: words,
                      statuses: const [
                        LiveWordStatus.matched,
                        LiveWordStatus.error,
                        LiveWordStatus.matched,
                        LiveWordStatus.matched
                      ],
                      mushaf: MushafTheme.classic,
                      fontSize: 20,
                      cursor: review ? 4 : 1,
                      lineEnds: const [3],
                      cursorKey: cursor,
                      reviewMode: review,
                      onMistakeTap: (i) => tapped = i)))));
      await tester.pumpAndSettle();
    }

    await render(false);
    final anchor = cursor.currentContext!.findRenderObject()! as RenderBox;
    final bounds = MatrixUtils.transformRect(
        anchor.getTransformTo(null), Offset.zero & anchor.size);
    expect(bounds, mushafWordRect(tester, 1));
    final before = mushafWordRects(tester);
    await render(true);
    expect(mushafWordRects(tester), before);
    await tester.tapAt(mushafWordRect(tester, 1).center);
    expect(tapped, 1);
    expect(tester.takeException(), isNull);
  });
}
