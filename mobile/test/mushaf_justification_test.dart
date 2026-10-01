import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final paragraphs = tester.widgetList<MushafParagraph>(find.byType(MushafParagraph)).toList();
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
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(
      width: 320,
      child: MushafRevealView(words: words, statuses: const [],
          mushaf: MushafTheme.classic, fontSize: 20,
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
}
