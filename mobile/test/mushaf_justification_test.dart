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

  testWidgets('Mushaf body retains one natural RTL paragraph on dense lines',
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
    expect(widget.textDirection, TextDirection.rtl);
    for (final row in mushafTextRows(tester)) {
      expect(row.left, greaterThanOrEqualTo(-0.5));
      expect(row.right, closeTo(320, 1));
    }
    expectNaturalMushafSpaces(tester, reason: 'dense Mushaf rows');
    expect(tester.takeException(), isNull);
  });
}
