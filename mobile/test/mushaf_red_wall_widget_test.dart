import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'mushaf_text_helpers.dart';

/// Wraps the view in a MaterialApp so theme colours resolve.
Widget _host({
  required List<String> words,
  required List<LiveWordStatus> statuses,
  required int cursor,
  MushafTheme? mushaf,
}) {
  final t = mushaf ?? MushafTheme.classic;
  return MaterialApp(
    theme: t.toThemeData(),
    home: Scaffold(
      body: MushafRevealView(
        words: words,
        statuses: statuses,
        mushaf: t,
        cursor: cursor,
        fontSize: 20,
      ),
    ),
  );
}

/// Words whose RENDERED colour is the preset's mismatch ink.
List<String> _redWords(WidgetTester tester, MushafTheme t) =>
    wordsInColor(tester, t.mismatchInk);

const _words = <String>[
  'ٱلْحَمْدُ',
  'لِلَّهِ',
  'رَبِّ',
  'ٱلْعَٰلَمِينَ',
  'ٱلرَّحْمَٰنِ',
  'ٱلرَّحِيمِ',
  'مَٰلِكِ',
  'يَوْمِ',
];

/// The invariant under test: a word may be red ONLY if its index is STRICTLY
/// behind the recitation cursor. Words at or ahead of the cursor are never red.
void _expectRedOnlyBehindCursor(
  WidgetTester tester, {
  required List<String> words,
  required int cursor,
}) {
  final red = _redWords(tester, MushafTheme.classic);
  final allowed = {
    for (var i = 0; i < cursor && i < words.length; i++) words[i],
  };
  for (final w in red) {
    expect(
      allowed.contains(w),
      true,
      reason: '"$w" is red but is not strictly behind the cursor ($cursor). '
          'Ahead-of-cursor words must never be red.',
    );
  }
}

void main() {
  testWidgets('a word ahead of the cursor is NOT painted red', (tester) async {
    // Reciter is on word 0 (cursor 0). The server wrongly flags EVERY word —
    // this is the red-wall input. Nothing is behind the cursor, so nothing red.
    final statuses = List<LiveWordStatus>.filled(
      _words.length,
      LiveWordStatus.error,
    );
    await tester
        .pumpWidget(_host(words: _words, statuses: statuses, cursor: 0));

    expect(_redWords(tester, MushafTheme.classic), isEmpty,
        reason: 'with the cursor on word 0, no word may be red');
  });

  testWidgets('the reported bug: cursor early, whole page flagged',
      (tester) async {
    // Reciter is still on ayah 1 word 0. Server flags the whole page.
    final statuses = List<LiveWordStatus>.filled(
      _words.length,
      LiveWordStatus.error,
    );
    await tester
        .pumpWidget(_host(words: _words, statuses: statuses, cursor: 0));

    final red = _redWords(tester, MushafTheme.classic);
    expect(red, isEmpty,
        reason: 'the page must NOT turn red while the reciter is on word 0');
    // ...including the very last word of the page (the reported الضالين case).
    expect(red, isNot(contains(_words.last)));
  });

  testWidgets('a genuine mistake BEHIND the cursor is red', (tester) async {
    // Cursor = 4. Word 1 is a real, already-passed mistake.
    final statuses =
        List<LiveWordStatus>.filled(_words.length, LiveWordStatus.matched);
    statuses[1] = LiveWordStatus.error;
    await tester
        .pumpWidget(_host(words: _words, statuses: statuses, cursor: 4));

    expect(_redWords(tester, MushafTheme.classic), contains('لِلَّهِ'),
        reason: 'a real mistake behind the cursor must still be visible');
    expect(_redWords(tester, MushafTheme.classic), isNot(contains('يَوْمِ')),
        reason: 'and nothing ahead of it');
  });

  testWidgets('red is confined to indices strictly behind the cursor',
      (tester) async {
    for (final cursor in [0, 1, 3, 5, 7]) {
      final statuses = List<LiveWordStatus>.filled(
        _words.length,
        LiveWordStatus.error,
      );
      await tester
          .pumpWidget(_host(words: _words, statuses: statuses, cursor: cursor));
      _expectRedOnlyBehindCursor(tester, words: _words, cursor: cursor);
    }
  });

  testWidgets('the cursor word is highlighted, never red', (tester) async {
    final statuses =
        List<LiveWordStatus>.filled(_words.length, LiveWordStatus.error);
    await tester
        .pumpWidget(_host(words: _words, statuses: statuses, cursor: 2));
    // Words 0,1 are behind -> red is legitimate. Word 2 is the CURSOR and must
    // not be red; nor may anything after it.
    expect(_redWords(tester, MushafTheme.classic), isNot(contains(_words[2])),
        reason: 'the active word is a highlight, not an error');
    expect(
        _redWords(tester, MushafTheme.classic), isNot(contains(_words.last)));
    // The active word carries the listening wash, not an error underline.
    expect(washOf(tester, _words[2]), MushafTheme.classic.activeTint);
    expect(spanOf(tester, _words[2])!.style!.decoration,
        isNot(TextDecoration.underline));
  });

  // ── Word-state → colour contract, across every preset ───────────────────
  // These lock in the four-state rule for the redesigned Mushaf:
  //   unspoken → book ink (Tilawat), no wash
  //   active   → activeTint wash, book ink
  //   correct  → correctTint (green) wash
  //   mismatch → mismatchInk, and ONLY strictly behind the cursor
  group('Mushaf word-state colour contract', () {
    const words = ['سَلَام', 'عَلَيْكُم', 'رَحْمَة'];
    const statuses = [
      LiveWordStatus.error, // idx 0 — behind the cursor → a real mismatch
      LiveWordStatus.matched, // idx 1 — the cursor
      LiveWordStatus.matched, // idx 2 — ahead, must be neutral
    ];

    for (final t in MushafTheme.all) {
      testWidgets('${t.label}: state → colour mapping', (tester) async {
        await tester.pumpWidget(
          _host(words: words, statuses: statuses, cursor: 1, mushaf: t),
        );
        await tester.pumpAndSettle();

        // unspoken (ahead of cursor): Tilawat book ink, never red.
        expect(inkOf(tester, words[2]), t.text);
        expect(inkOf(tester, words[2]), isNot(t.mismatchInk));

        // active: book ink (NOT red) with the active wash.
        expect(inkOf(tester, words[1]), t.text);
        expect(inkOf(tester, words[1]), isNot(t.mismatchInk));

        // mismatch (behind the cursor): the only red in the view.
        expect(inkOf(tester, words[0]), t.mismatchInk);
        expect(_redWords(tester, t), [words[0]]);

        // Dark pages use an ink glow; paper presets retain a wash.
        if (t.isDark) {
          expect(washOf(tester, words[1]), isNull);
          expect(spanOf(tester, words[1])!.style!.shadows, isNotEmpty);
        } else {
          expect(washes(tester), contains(t.activeTint));
        }
      });
    }

    testWidgets('a correct word is tinted green, in light and dark',
        (tester) async {
      for (final t in [MushafTheme.classic, MushafTheme.night]) {
        await tester.pumpWidget(
          _host(
            words: const ['مَحْمُود', 'رَبِّ'],
            statuses: const [
              LiveWordStatus.matched, // idx 0 — behind cursor → correct
              LiveWordStatus.matched, // idx 1 — the cursor → active
            ],
            cursor: 1,
            mushaf: t,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          washes(tester),
          contains(t.correctTint),
          reason: '${t.label} must paint the green correct tint',
        );
      }
    });

    testWidgets('unspoken words carry NO background wash', (tester) async {
      await tester.pumpWidget(
        _host(
          words: const ['أَولٰئِكَ', 'عَلَىٰ'],
          // Index 0 is the cursor (active); index 1 is AHEAD of it, so it must
          // be plain unspoken ink with no decoration at all.
          statuses: const [LiveWordStatus.matched, LiveWordStatus.matched],
          cursor: 0,
          mushaf: MushafTheme.classic,
        ),
      );
      await tester.pumpAndSettle();
      // The word ahead of the cursor is book ink, not washed, not red.
      expect(inkOf(tester, 'عَلَىٰ'), MushafTheme.classic.text);
      expect(spanOf(tester, 'عَلَىٰ')!.style?.background, isNull);
      // Only the active cursor carries a wash — no green/red verdict leaked
      // forward onto an unspoken word.
      expect(washes(tester), isNot(contains(MushafTheme.classic.correctTint)));
      expect(_redWords(tester, MushafTheme.classic), isEmpty);
    });

    testWidgets('the red wall survives a theme switch', (tester) async {
      // The exact stream that produced the reported "red screen" bug: EVERY
      // word claims `error_skipped`, yet the cursor is still at 0. Rule 2 makes
      // index 0 `active` and rule 1 makes 1..n `unspoken`, so the page must be
      // completely free of red — in every preset, light and dark.
      final allErrored = List.filled(_words.length, LiveWordStatus.error);
      for (final t in MushafTheme.all) {
        await tester.pumpWidget(
          _host(
            words: _words,
            statuses: allErrored,
            cursor: 0,
            mushaf: t,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          _redWords(tester, t),
          isEmpty,
          reason: '${t.label}: an all-errored stream at cursor 0 must not '
              'cascade into a red wall',
        );
      }
    });
  });
}
