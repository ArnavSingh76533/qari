import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_model.dart';
import 'package:qari/features/recitation/presentation/widgets/recitation_results.dart';

RecitationResult resultWith(List<bool> correct) {
  return RecitationResult(
    sessionId: 'r1',
    surahNumber: 1,
    ayahNumber: 1,
    overallScore: 80,
    pronunciationScore: 80,
    tajweedScore: 80,
    fluencyScore: 80,
    accuracyScore: 80,
    createdAt: DateTime(2026, 1, 1),
    feedback: 'Good effort',
    wordVerdicts: [
      for (var i = 0; i < correct.length; i++)
        WordVerdict(
          word: 'w$i',
          wordIndex: i,
          isCorrect: correct[i],
          confidence: correct[i] ? 1.0 : 0.2,
        ),
    ],
  );
}

Widget host(RecitationResult r, List<String> words) {
  return MaterialApp(
    home: Scaffold(
      body: RecitationResults(
        result: r,
        ayahWords: words,
        onWordTapped: (_) {},
        onRetry: () {},
        theme: ThemeData.light(),
      ),
    ),
  );
}

void main() {
  // Al-Fatiha 1:4 in Uthmani.
  const words = ['بِسْمِ', 'ٱللَّهِ', 'ٱلرَّحْمَـٰنِ', 'ٱلرَّحِيمِ'];

  testWidgets('REQ 4: full mushaf text is shown, not just a verdict list',
      (tester) async {
    await tester.pumpWidget(host(resultWith([true, true, true, true]), words));
    await tester.pumpAndSettle();
    for (final w in words) {
      expect(find.text(w), findsOneWidget, reason: 'missing $w');
    }
  });

  testWidgets('REQ 4: only verified mistakes are underlined', (tester) async {
    await tester.pumpWidget(host(resultWith([true, false, true, true]), words));
    await tester.pumpAndSettle();

    final bad = tester.widget<Text>(find.text('ٱللَّهِ'));
    final good = tester.widget<Text>(find.text('ٱلرَّحْمَـٰنِ'));

    expect(bad.style!.decoration, TextDecoration.underline,
        reason: 'mistake must be underlined');
    expect(good.style!.decoration, TextDecoration.none,
        reason: 'correct words must stay plain book ink');
  });

  testWidgets('REQ 4: words are not rendered as bordered tiles', (tester) async {
    await tester.pumpWidget(host(resultWith([true, false, true, true]), words));
    await tester.pumpAndSettle();

    // Scope the check to the word flow: the score header / sub-scores / feedback
    // legitimately use bordered cards, but no WORD may be a tile.
    final flow = find.ancestor(
      of: find.text('ٱلرَّحْمَـٰنِ'),
      matching: find.byType(Wrap),
    );
    expect(flow, findsOneWidget);
    final tiles = tester
        .widgetList<Container>(
          find.descendant(of: flow, matching: find.byType(Container)),
        )
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).border != null)
        .length;
    // A correct word must be bare text: no border, no wash, no tile.
    expect(tiles, 0, reason: 'correct words are still rendered as bordered tiles');
  });

  testWidgets('REQ 4: result is resilient to short/long verdict lists',
      (tester) async {
    // More verdicts than words must not throw or render stray text.
    await tester.pumpWidget(host(resultWith([true, false, true, true, true, true]), words));
    await tester.pumpAndSettle();
    expect(find.text('بِسْمِ'), findsOneWidget);
  });
}
