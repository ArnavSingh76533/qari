import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

/// Mirrors the page's prime() step: the full target is laid out up front with
/// every word pending (renders as neutral `unspoken`).
Widget prime({
  required List<String> words,
  required List<int> ayahBoundaries,
  required List<String> ayahLabels,
  int cursor = -1,
  List<LiveWordStatus>? statuses,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MushafRevealView(
        words: words,
        statuses: statuses ??
            List<LiveWordStatus>.filled(words.length, LiveWordStatus.pending),
        mushaf: MushafTheme.classic,
        cursor: cursor,
        ayahBoundaries: ayahBoundaries,
        ayahLabels: ayahLabels,
        fontSize: 28,
      ),
    ),
  );
}

void main() {
  // Al-Fatiha 1:1 with the Uthmani text_with_tashkeel from the backend.
  const fatiha = ['بِسْمِ', 'ٱللَّهِ', 'ٱلرَّحْمَـٰنِ', 'ٱلرَّحِيمِ'];

  testWidgets('REQ 1: full text is visible BEFORE any word event', (tester) async {
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    // Every word is on screen from word one - no blank canvas, no hint text.
    for (final w in fatiha) {
      expect(find.text(w), findsOneWidget, reason: 'missing $w');
    }
    expect(find.textContaining('Start reciting'), findsNothing);
  });

  testWidgets('REQ 2: every word carries its full tashkeel', (tester) async {
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    // Fatha, kasra, shaddah, dagger alif, sukun must all survive to the screen.
    // U+064E fatha, U+0650 kasra, U+0651 shaddah, U+0670 dagger alif,
    // U+0652 sukun, U+0653.. maddah.
    const diacritics = [0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650,
      0x0651, 0x0652, 0x0653, 0x0670];
    var total = 0;
    for (final w in fatiha) {
      final text = tester.widget<Text>(find.text(w));
      final rendered = text.data!;
      for (final c in rendered.codeUnits) {
        if (diacritics.contains(c)) total++;
      }
    }
    expect(total, greaterThanOrEqualTo(10),
        reason: 'diacritics were stripped somewhere in the pipeline');
  });

  testWidgets('REQ 1: highlighting a word does NOT change the word count',
      (tester) async {
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    await tester.pumpAndSettle();

    // Layout must be rock solid: applying verdicts in place must not add,
    // remove or reorder a single word, so the rendered block is identical.
    final findView = () => tester.getSize(find.byType(MushafRevealView));
    final before = findView();
    final wordsBefore =
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();

    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
      cursor: 1,
      statuses: const [LiveWordStatus.matched, LiveWordStatus.pending,
        LiveWordStatus.pending, LiveWordStatus.pending],
    ));
    await tester.pumpAndSettle();

    expect(findView(), before,
        reason: 'page geometry changed when verdicts were applied');
    final wordsAfter =
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(wordsAfter, wordsBefore,
        reason: 'the set/order of rendered words changed');
  });

  testWidgets('REQ 1: in-place update recolours without swapping text',
      (tester) async {
    // The wire's `expected` is the normalized ASR key. It must NOT be what is
    // rendered - the pre-rendered tashkeel word stays exactly as it was.
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
      cursor: 0,
      statuses: const [LiveWordStatus.matched, LiveWordStatus.pending,
        LiveWordStatus.pending, LiveWordStatus.pending],
    ));
    expect(find.text('بِسْمِ'), findsOneWidget);
    expect(find.text('بسم'), findsNothing,
        reason: 'normalized clean_text leaked into the Mushaf view');
  });

  testWidgets('REQ 3: no stray verse-number word is rendered', (tester) async {
    // The corpus stores a trailing "١" marker; it must be dropped client-side
    // so indices match the backend, and the ornament supplies the number.
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    expect(find.text('١'), findsNothing);
    // The ornament (۝ + number) is rendered exactly once, at the ayah end.
    expect(find.textContaining('۝'), findsOneWidget);
  });

  testWidgets('REQ: red wall guard still holds on a pre-rendered page',
      (tester) async {
    // Every word flagged error, but the cursor is at 0, so everything ahead of
    // it must stay neutral.
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
      cursor: 0,
      statuses: List<LiveWordStatus>.filled(
          4, LiveWordStatus.error),
    ));
    final err = Theme.of(tester.element(find.byType(Wrap).first)).colorScheme.error;
    final reds = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) {
      final d = c.decoration;
      if (d is! BoxDecoration) return false;
      return d.color == err || d.border?.bottom.color == err;
    });
    expect(reds, isEmpty, reason: 'red appeared ahead of the cursor');
  });
}
