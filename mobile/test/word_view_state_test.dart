import 'package:flutter_test/flutter_test.dart';

import '../lib/data/models/recitation_stream_event.dart';
import '../lib/features/recitation/presentation/word_view_state.dart';

/// Al-Fatiha 1:1–1:7, the exact page from the bug report: the reciter was on
/// ayah 2 and the app painted everything down to الضالين red.
const _fatiha = <String>[
  'ٱلْحَمْدُ', 'لِلَّهِ', 'رَبِّ', 'ٱلْعَٰلَمِينَ', // 1:1
  'ٱلرَّحْمَٰنِ', 'ٱلرَّحِيمِ', 'مَٰلِكِ', 'يَوْمِ', // 1:2
  'ٱلدِّينِ', 'إِيَّاكَ', 'نَعْبُدُ', 'وَإِيَّاكَ', // 1:3
  'نَسْتَعِينُ', 'ٱهْدِنَا', 'ٱلصِّرَٰطَ', 'ٱلْمُسْتَقِيمَ', // 1:4
  'صِرَٰطَ', 'ٱلَّذِينَ', 'أَنْعَمْتَ', 'عَلَيْهِمْ', // 1:5
  'غَيْرِ', 'ٱلْمَغْضُوبِ', 'عَلَيْهِمْ', 'وَلَا', 'ٱلضَّآلِّينَ', // 1:6-7
];
const _mustBeFinalWord = 'ٱلضَّآلِّينَ';
const lastIndex = 24; // _fatiha.length - 1 (Al-Fatiha 1:1-1:7 = 25 words)

void main() {
  group('resolveWordViewState — the hard rule', () {
    test('a word AHEAD of the cursor is NEVER a mistake, whatever the wire says',
        () {
      // Cursor is still on ayah 2 (index 4). The wire says the last word of the
      // surah was "skipped" — exactly the red-wall input.
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: _fatiha.length - 1,
          cursor: 4,
        ),
        LiveWordViewState.unspoken,
      );
    });

    test('a word AHEAD of the cursor is never correct either', () {
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.matched,
          index: 9,
          cursor: 4,
        ),
        LiveWordViewState.unspoken,
      );
    });

    test('the cursor word is always active, even if flagged', () {
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: 4,
          cursor: 4,
        ),
        LiveWordViewState.active,
      );
    });

    test('behind the cursor: match -> correct', () {
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.matched,
          index: 2,
          cursor: 4,
        ),
        LiveWordViewState.correct,
      );
    });

    test('behind the cursor: error_skipped -> mismatch', () {
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: 2,
          cursor: 4,
        ),
        LiveWordViewState.mismatch,
      );
    });

    test('behind the cursor but still pending -> unspoken', () {
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.pending,
          index: 1,
          cursor: 4,
        ),
        LiveWordViewState.unspoken,
      );
    });
  });

  group('the reported bug, end to end', () {
    test('a jump to the final word paints NO red AHEAD of the cursor', () {
      // Server (buggy) marks EVERY word as skipped while the reciter is on
      // ayah 2 (cursor = 4). Words already passed MAY legitimately be red —
      // the rule is that nothing AHEAD of the cursor is.
      const cursor = 4;
      final statuses =
          List<LiveWordStatus>.filled(_fatiha.length, LiveWordStatus.error);
      final view = resolveWordViewStates(statuses: statuses, cursor: cursor);
      final redAhead = <String>[
        for (var i = cursor + 1; i < view.length; i++)
          if (isErrorStyle(view[i])) _fatiha[i],
      ];
      expect(redAhead, isEmpty,
          reason: 'no word may be red ahead of the recitation cursor');
      expect(view[lastIndex], LiveWordViewState.unspoken,
          reason: 'the final word must stay neutral while the cursor is on 1:2');
      expect(view[cursor], LiveWordViewState.active);
    });

    test('a realistic run marks only genuinely-reached mistakes', () {
      // Reciter on ayah 2, cursor = 5. Words 0-3 correct, word 4 is the cursor,
      // and a stale window wrongly flags word 8 (still ahead).
      const cursor = 5;
      final statuses = [
        LiveWordStatus.matched, // 0
        LiveWordStatus.matched, // 1
        LiveWordStatus.matched, // 2
        LiveWordStatus.error, // 3  <- genuine mistake, behind cursor
        LiveWordStatus.matched, // 4
        LiveWordStatus.matched, // 5  <- the cursor word
        LiveWordStatus.error, // 6  <- stale, but at/behind cursor: allowed
        LiveWordStatus.error, // 7  <- stale
        LiveWordStatus.error, // 8  <- stale, AHEAD: must be neutral
      ];
      final view = resolveWordViewStates(statuses: statuses, cursor: cursor);
      expect(view[0], LiveWordViewState.correct);
      expect(view[3], LiveWordViewState.mismatch);
      expect(view[5], LiveWordViewState.active);
      expect(view[8], LiveWordViewState.unspoken,
          reason: 'a stale flag ahead of the cursor must not paint red');
    });

    test('the final word of Al-Fatiha can only be red if actually reached', () {
      final last = _fatiha.length - 1;
      expect(_fatiha[last], _mustBeFinalWord);
      // Cursor far earlier -> neutral.
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: last,
          cursor: 4,
        ),
        LiveWordViewState.unspoken,
      );
      // Cursor has genuinely passed it -> red is legitimate.
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: last,
          cursor: last,
        ),
        LiveWordViewState.active,
      );
      expect(
        resolveWordViewState(
          serverStatus: LiveWordStatus.error,
          index: last,
          cursor: last + 1,
        ),
        LiveWordViewState.mismatch,
      );
    });
  });

  group('wire-contract parsing', () {
    test('error_skipped maps to a mistake bucket', () {
      expect(LiveWordStatus.fromString('error_skipped'),
          LiveWordStatus.error);
      expect(LiveWordStatus.fromString('match'), LiveWordStatus.matched);
    });
  });
}
