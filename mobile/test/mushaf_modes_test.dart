import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_model.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_page_frame.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/pages/live_recitation_page.dart';
import 'package:qari/features/recitation/presentation/recitation_mode.dart';
import 'package:qari/features/recitation/presentation/recitation_review.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'helpers/mushaf_paragraph_helpers.dart';

const _words = <String>[
  'ٱلْحَمْدُ',
  'لِلَّهِ',
  'رَبِّ',
  'ٱلْعَٰلَمِينَ',
  'ٱلرَّحْمَٰنِ',
  'ٱلرَّحِيمِ',
  'مَٰلِكِ',
  'يَوْمِ',
  'ٱلدِّينِ',
];

Widget _view({
  required List<LiveWordStatus> statuses,
  required int cursor,
  bool reviewMode = false,
  ValueChanged<int>? onMistakeTap,
  MushafTheme theme = MushafTheme.classic,
  bool hideUnspoken = false,
  List<int> boundaries = const [],
  List<String> labels = const [],
}) {
  return MaterialApp(
    theme: theme.toThemeData(),
    home: Scaffold(
      body: MushafRevealView(
        words: _words,
        statuses: statuses,
        mushaf: theme,
        cursor: cursor,
        fontSize: 20,
        reviewMode: reviewMode,
        onMistakeTap: onMistakeTap,
        hideUnspoken: hideUnspoken,
        ayahBoundaries: boundaries,
        ayahLabels: labels,
      ),
    ),
  );
}

Color? _inkOf(String word) => mushafWordSpan(word).style?.color;

Color? _markerInk(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

/// Background washes painted by the shaped word spans.
Set<Color> _washes() => {
      for (final span in mushafWordSpans())
        if (span.style?.backgroundColor case final color?) color,
    };

int _underlineCount(Color color) => mushafWordSpans().where((span) {
      final style = span.style;
      return (style?.decoration?.contains(TextDecoration.underline) ?? false) &&
          style?.decorationColor == color.withValues(alpha: 0.9);
    }).length;

RecitationResult _server(List<bool> correct) => RecitationResult(
      sessionId: 's',
      surahNumber: 1,
      ayahNumber: 1,
      overallScore: 0,
      createdAt: DateTime(2026),
      wordVerdicts: [
        for (var i = 0; i < correct.length; i++)
          WordVerdict(word: _words[i], wordIndex: i, isCorrect: correct[i]),
      ],
    );

void main() {
  group('Tilawat mode — full page visible in crisp book ink', () {
    testWidgets('a freshly primed page (cursor -1) is entirely book ink',
        (tester) async {
      for (final t in MushafTheme.all) {
        await tester.pumpWidget(_view(
          statuses: List.filled(_words.length, LiveWordStatus.pending),
          cursor: -1,
          theme: t,
        ));
        for (final w in _words) {
          expect(_inkOf(w), t.text, reason: '${t.label}: $w');
        }
      }
    });

    testWidgets('verdicts recolour in place: green wash, red underline',
        (tester) async {
      final t = MushafTheme.classic;
      final statuses = List.filled(_words.length, LiveWordStatus.pending);
      statuses[0] = LiveWordStatus.matched;
      statuses[1] = LiveWordStatus.error;
      await tester.pumpWidget(_view(statuses: statuses, cursor: 2));
      expect(_inkOf(_words[0]), t.text);
      expect(_inkOf(_words[1]), t.mismatchInk);
      expect(_underlineCount(t.mismatchInk), 1);
      expect(_washes(), containsAll([t.correctTint, t.activeTint]));
      for (var i = 3; i < _words.length; i++) {
        expect(_inkOf(_words[i]), t.text);
      }
    });
  });

  group('Hifz mode — unsaid words hidden, layout preserved', () {
    testWidgets('unspoken + active words are transparent; medallions visible',
        (tester) async {
      final t = MushafTheme.classic;
      final statuses = List.filled(_words.length, LiveWordStatus.pending);
      statuses[0] = LiveWordStatus.matched;
      statuses[1] = LiveWordStatus.error;
      await tester.pumpWidget(_view(
        statuses: statuses,
        cursor: 2,
        hideUnspoken: true,
        boundaries: const [4],
        labels: const ['1'],
      ));
      // Confirmed word: solid ink with the green wash.
      expect(_inkOf(_words[0]), t.text);
      expect(_washes(), contains(t.correctTint));
      // Skipped word: revealed in red with an underline.
      expect(_inkOf(_words[1]), t.mismatchInk);
      expect(_underlineCount(t.mismatchInk), 1);
      // Active and upcoming words: fully transparent.
      for (var i = 2; i < _words.length; i++) {
        expect(_inkOf(_words[i])!.a, 0, reason: _words[i]);
      }
      // The ayah medallion stays visible to guide verse position.
      expect(_markerInk(tester, '١'), t.accent);
      expect(_washes(), isNot(contains(t.activeTint)),
          reason: 'a hidden Hifz cursor must not reveal its position');
    });

    testWidgets('revealing a word never moves any word on the page',
        (tester) async {
      Future<List<Rect>> layout(bool hide, int revealed) async {
        final statuses = List.filled(_words.length, LiveWordStatus.pending);
        for (var i = 0; i < revealed; i++) {
          statuses[i] = LiveWordStatus.matched;
        }
        await tester.pumpWidget(_view(
          statuses: statuses,
          cursor: revealed,
          hideUnspoken: hide,
        ));
        expect(mushafWords(), _words);
        return [for (var i = 0; i < _words.length; i++) mushafWordRect(tester, i)];
      }

      final tilawat = await layout(false, 0);
      final hifzNone = await layout(true, 0);
      final hifzSome = await layout(true, 5);
      expect(hifzNone, tilawat);
      expect(hifzSome, tilawat);
    });

    testWidgets('the page opens in Hifz with the words hidden', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: LiveRecitationPage(
          surahNumber: 1,
          ayahNumber: 1,
          initialMode: RecitationMode.hifz,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Hifz'), findsOneWidget);
      final reveal = find.byType(MushafRevealView);
      final view = tester.widget<MushafRevealView>(reveal);
      expect(view.hideUnspoken, isTrue);
      // Every Al-Fatiha word is laid out but invisible; medallions are not.
      for (final w in view.words) {
        expect(_inkOf(w)!.a, 0, reason: w);
      }
      expect(_markerInk(tester, '٧'), isNotNull);
      expect(_markerInk(tester, '٧')!.a, greaterThan(0));

      // The Hifz entry has no switch into the separate Tilawat section.
      expect(find.byTooltip('Hifz: unsaid words hidden. Tap for Tilawat'),
          findsNothing);
    });
  });

  group('Bug C — early stop never penalises unreached words', () {
    test('stop after 3 words: server fails the rest, score is NOT 0%', () {
      final live = List.filled(_words.length, LiveWordStatus.pending);
      live[0] = live[1] = live[2] = LiveWordStatus.matched;
      final review = buildRecitationReview(
        words: _words,
        liveCursor: 3,
        liveStatuses: live,
        // The server re-scores the whole target: everything unrecited fails.
        serverResult: _server(
            [true, true, true, false, false, false, false, false, false]),
      );
      expect(review.reach, 3);
      expect(review.result.overallScore, 1.0);
      expect(review.result.wordVerdicts.length, 3);
      expect(review.mistakeCount, 0);
      expect(review.unreachedCount, 6);
      for (var i = 3; i < _words.length; i++) {
        expect(review.statuses[i], LiveWordStatus.pending);
      }
    });

    test('a genuine mistake behind the reach is still reported', () {
      final live = List.filled(_words.length, LiveWordStatus.pending);
      live[0] = live[2] = live[3] = LiveWordStatus.matched;
      final review = buildRecitationReview(
        words: _words,
        liveCursor: 4,
        liveStatuses: live,
        serverResult: _server(
            [true, false, true, true, false, false, false, false, false]),
      );
      expect(review.reach, 4);
      expect(review.statuses[1], LiveWordStatus.error);
      expect(review.mistakeCount, 1);
      expect(review.result.overallScore, closeTo(0.75, 1e-9));
    });

    test('the final pass may extend reach past a lagging live cursor', () {
      final review = buildRecitationReview(
        words: _words,
        liveCursor: 2,
        liveStatuses: List.filled(_words.length, LiveWordStatus.pending),
        serverResult:
            _server([true, true, true, true, true, false, false, false, false]),
      );
      expect(review.reach, 5);
      expect(review.result.overallScore, 1.0);
    });

    test('with no server payload the live verdicts are used, reach-limited',
        () {
      final live = List.filled(_words.length, LiveWordStatus.pending);
      live[0] = LiveWordStatus.matched;
      live[1] = LiveWordStatus.error;
      // A stale window flagged a word far ahead: must not count.
      live[7] = LiveWordStatus.error;
      final review = buildRecitationReview(
        words: _words,
        liveCursor: 2,
        liveStatuses: live,
      );
      expect(review.reach, 2);
      expect(review.statuses[7], LiveWordStatus.pending);
      expect(review.result.overallScore, 0.5);
    });

    test('nothing recited: empty review, no red', () {
      final review = buildRecitationReview(
        words: _words,
        liveCursor: 0,
        liveStatuses: List.filled(_words.length, LiveWordStatus.pending),
        serverResult: _server(List.filled(_words.length, false)),
      );
      expect(review.reach, 0);
      expect(review.mistakeCount, 0);
      expect(review.result.wordVerdicts, isEmpty);
    });
  });

  group('Bug D — review renders on the Mushaf page', () {
    testWidgets('mistake is red + underlined; unreached stays ghost, no red',
        (tester) async {
      final t = MushafTheme.classic;
      final statuses = List.filled(_words.length, LiveWordStatus.pending);
      statuses[0] = LiveWordStatus.matched;
      statuses[1] = LiveWordStatus.error;
      statuses[2] = LiveWordStatus.matched;
      // Even if a stale status leaks past the reach, it must not render red.
      statuses[6] = LiveWordStatus.error;
      await tester
          .pumpWidget(_view(statuses: statuses, cursor: 3, reviewMode: true));

      expect(_inkOf(_words[0]), t.text);
      expect(_inkOf(_words[1]), t.mismatchInk);
      expect(_inkOf(_words[2]), t.text);
      for (var i = 3; i < _words.length; i++) {
        expect(_inkOf(_words[i]), t.ghostInk, reason: _words[i]);
      }
      expect(_underlineCount(t.mismatchInk), 1);
    });

    testWidgets('review has no active cursor and no green wash',
        (tester) async {
      final t = MushafTheme.classic;
      final statuses = List.filled(_words.length, LiveWordStatus.matched);
      await tester.pumpWidget(
          _view(statuses: statuses, cursor: _words.length, reviewMode: true));
      expect(mushafWords(), _words);
      expect(_washes(), isNot(contains(t.correctTint)));
      expect(_washes(), isNot(contains(t.activeTint)));
    });

    testWidgets('tapping a mistake reports its index', (tester) async {
      final statuses = List.filled(_words.length, LiveWordStatus.matched);
      statuses[4] = LiveWordStatus.error;
      int? tapped;
      await tester.pumpWidget(_view(
        statuses: statuses,
        cursor: _words.length,
        reviewMode: true,
        onMistakeTap: (i) => tapped = i,
      ));
      await tester.tapAt(mushafWordRect(tester, 4).center);
      expect(tapped, 4);
    });
  });

  group('Bug A — text stays inside the frame, clear of the mic bar', () {
    testWidgets('Al-Fatiha on a phone: no overflow, last ayah above the bar',
        (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: LiveRecitationPage(surahNumber: 1, ayahNumber: 1),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final lastMarker = find.text('٧');
      expect(lastMarker, findsOneWidget);

      // Scroll the page to its end, as a reciter would near the last ayah.
      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      final frame = tester.getRect(find.byType(MushafPageFrame));
      final marker = tester.getRect(lastMarker);
      final bar = tester.getRect(find.byType(FloatingRecitationBar));
      // The last ayah is inside the page border...
      expect(frame.contains(marker.topLeft), isTrue);
      expect(marker.bottom, lessThanOrEqualTo(frame.bottom));
      // ...and not buried under the floating mic bar.
      expect(marker.bottom, lessThanOrEqualTo(bar.top));
      expect(frame.bottom, lessThanOrEqualTo(bar.top));
    });
  });
}
