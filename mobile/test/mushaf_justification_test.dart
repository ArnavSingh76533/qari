import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets('engine justifies the visible final line before a wrap sentinel',
      (tester) async {
    const text = 'إِنَّ ٱلَّذِينَ كَفَرُوا۟ سَوَآءٌ عَلَيْهِمْ';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 320,
      child: RichText(
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.justify,
        maxLines: 1,
        text: TextSpan(
            style: TextStyle(fontFamily: 'KFGQPCUthmanicHafs', fontSize: 20),
            children: [
              TextSpan(text: text),
              TextSpan(text: ' '),
              WidgetSpan(child: SizedBox(width: 320, height: 0)),
            ]),
      ),
    ))));
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byType(RichText).first);
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length));
    debugPrint('final visible line boxes: $boxes');
    expect(boxes.map((b) => b.left).reduce((a, b) => a < b ? a : b),
        closeTo(0, 1));
    expect(boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b),
        closeTo(320, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mushaf body uses one justified RTL paragraph with flush edges',
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
          lineEnds: const [9, 19, 29]),
    ))));
    await tester.pumpAndSettle();
    final body = find.byType(MushafRevealView);
    expect(
        find.descendant(of: body, matching: find.byType(Wrap)), findsNothing);
    final paragraphs = find.descendant(
        of: body,
        matching: find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('كَفَرُوا۟')));
    expect(paragraphs, findsOneWidget);
    final widget = tester.widget<RichText>(paragraphs);
    expect(widget.textAlign, TextAlign.justify);
    expect(widget.textDirection, TextDirection.rtl);
    for (final row in mushafTextRows(tester)) {
      expect(row.left, closeTo(0, 1));
      expect(row.right, closeTo(320, 1));
    }
    expect(tester.takeException(), isNull);
  });
}
