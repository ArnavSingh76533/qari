import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'mushaf_text_helpers.dart';

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

  testWidgets('REQ 1: full text is visible BEFORE any word event',
      (tester) async {
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    // Every word is on screen from word one - no blank canvas, no hint text.
    for (final w in fatiha) {
      expect(countOf(tester, w), 1, reason: 'missing $w');
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
    const diacritics = [
      0x064B,
      0x064C,
      0x064D,
      0x064E,
      0x064F,
      0x0650,
      0x0651,
      0x0652,
      0x0653,
      0x0670
    ];
    var total = 0;
    for (final w in fatiha) {
      final rendered = spanOf(tester, w)!.toPlainText();
      for (final c in rendered.codeUnits) {
        if (diacritics.contains(c)) total++;
      }
    }
    expect(total, greaterThanOrEqualTo(10),
        reason: 'diacritics were stripped somewhere in the pipeline');
  });

  testWidgets('words and inline markers belong to a fitted RTL line',
      (tester) async {
    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
    ));
    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(find.byType(Spacer), findsNothing);
    final paragraphs = mushafParagraphElements(tester);
    expect(paragraphs, hasLength(5));
    final rich = paragraphs.first.widget as RichText;
    expect(rich.textAlign, TextAlign.start);
    expect(rich.textDirection, TextDirection.rtl);
    expect(rich.text.style?.fontFamily, 'KFGQPCUthmanicHafs');
    expect(mushafUnitTexts(tester), [...fatiha, ayahMarkerText('1')]);
    expect(rich.text.style?.letterSpacing, 0);
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
    Size findView() => tester.getSize(find.byType(MushafRevealView));
    final before = findView();
    final wordsBefore = mushafUnitTexts(tester);
    final rectsBefore = [for (final w in fatiha) rectOf(tester, w)];

    await tester.pumpWidget(prime(
      words: fatiha,
      ayahBoundaries: const [3],
      ayahLabels: const ['1'],
      cursor: 1,
      statuses: const [
        LiveWordStatus.matched,
        LiveWordStatus.pending,
        LiveWordStatus.pending,
        LiveWordStatus.pending
      ],
    ));
    await tester.pumpAndSettle();

    expect(findView(), before,
        reason: 'page geometry changed when verdicts were applied');
    expect(mushafUnitTexts(tester), wordsBefore,
        reason: 'the set/order of rendered words changed');
    expect([for (final w in fatiha) rectOf(tester, w)], rectsBefore,
        reason: 'a word moved when verdicts were applied');
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
      statuses: const [
        LiveWordStatus.matched,
        LiveWordStatus.pending,
        LiveWordStatus.pending,
        LiveWordStatus.pending
      ],
    ));
    expect(countOf(tester, 'بِسْمِ'), 1);
    expect(countOf(tester, 'بسم'), 0,
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
    // The medallion (the Arabic-Indic verse number, which the Hafs font draws
    // as the ornament) is rendered exactly once, at the ayah end — a stray
    // corpus "١" word would make two.
    expect(countOf(tester, ayahMarkerText('1')), 1);
    expect(ayahMarkerText('1'), '١');
    expect(inkOf(tester, ayahMarkerText('1')), MushafTheme.classic.accent);
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
      statuses: List<LiveWordStatus>.filled(4, LiveWordStatus.error),
    ));
    final err = MushafTheme.classic.mismatchInk;
    expect(wordsInColor(tester, err), isEmpty,
        reason: 'red appeared ahead of the cursor');
    expect(underlineCount(tester, err), 0);
    expect(washes(tester), isNot(contains(err)));
  });
}
