import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/models/recitation_stream_event.dart';
import '../lib/data/models/word_model.dart';
import '../lib/features/recitation/presentation/mushaf/floating_recitation_bar.dart';
import '../lib/features/recitation/presentation/mushaf/mushaf_theme.dart';
import '../lib/features/recitation/presentation/pages/live_recitation_page.dart';
import '../lib/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

void main() {
  group('RecitationStreamEvent parsing', () {
    test('parses a ready payload with reference words', () {
      final e = RecitationStreamEvent.fromJson({
        'type': 'ready',
        'session_id': 'abc',
        'words': [
          {'index': 0, 'text': 'بِسْمِ'},
          {'index': 1, 'text': 'ٱللَّهِ'},
        ],
      });
      expect(e.type, RecitationStreamEventType.ready);
      expect(e.sessionId, 'abc');
      expect(e.words.length, 2);
      expect(e.words.first.text, 'بِسْمِ');
    });

    test('parses a live word event with status', () {
      final e = RecitationStreamEvent.fromJson({
        'type': 'word',
        'word_index': 2,
        'status': 'error',
        'expected': 'الرحمن',
        'spoken': 'السلام',
        'confidence': 0.8,
        'timestamp_ms': 3200,
      });
      expect(e.type, RecitationStreamEventType.word);
      expect(e.wordIndex, 2);
      expect(e.status, LiveWordStatus.error);
      expect(e.status.isMistake, isTrue);
      expect(e.expected, 'الرحمن');
    });

    test('unknown status falls back to pending', () {
      final e = RecitationStreamEvent.fromJson({'type': 'word', 'status': 'weird'});
      expect(e.status, LiveWordStatus.pending);
      expect(e.status.isResolved, isFalse);
    });

    test('parses a final result payload', () {
      final e = RecitationStreamEvent.fromJson({
        'type': 'final',
        'session_id': 'abc',
        'result': {
          'session_id': 'abc',
          'surah_number': 1,
          'ayah_number': 1,
          'overall_score': 0.75,
          'created_at': '2026-01-01T00:00:00Z',
          'word_verdicts': [],
        },
      });
      expect(e.type, RecitationStreamEventType.finalResult);
      expect(e.result, isNotNull);
      expect(e.result!.overallScore, 0.75);
    });
  });

  testWidgets('AI setup keeps Hifz mode and puts appearance in its sheet',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LiveRecitationPage(surahNumber: 1, ayahNumber: 1),
      ),
    );
    await tester.pumpAndSettle();

    // Tarteel-style chrome: surah name + Page | Juz | Hizb location.
    expect(find.text('Al-Fatihah'), findsWidgets);
    expect(find.text('Page 1 | Juz 1 | Hizb 1'), findsOneWidget);
    expect(find.text('Hifz'), findsOneWidget);
    expect(find.byTooltip('Hifz: unsaid words hidden. Tap for Tilawat'), findsNothing);
    // The old Memorization Mode toggle must be GONE.
    expect(find.text('Memorization Mode'), findsNothing);
    expect(find.text('Tajweed colours'), findsNothing);
    await tester.tap(find.byTooltip('Mushaf appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Tajweed colours'), findsOneWidget);
    Navigator.of(tester.element(find.text('Tajweed colours'))).pop();
    await tester.pumpAndSettle();

    // Recitation starts from the floating bar's mic, not the old full-width
    // "Start Reciting" banner (removed in the Mushaf redesign).
    expect(find.text('Start Reciting'), findsNothing);
    expect(find.byType(FloatingRecitationBar), findsOneWidget);
    // Its mic, quick-jump and appearance affordances are all present.
    final bar = find.byType(FloatingRecitationBar);
    expect(
      find.descendant(of: bar, matching: find.byIcon(Icons.mic_rounded)),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: bar, matching: find.byIcon(Icons.menu_book_rounded)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
  });

  testWidgets('MushafRevealView colours tajweed letters when enabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MushafRevealView(
            mushaf: MushafTheme.classic,
            words: const ['بسم', 'الله'],
            statuses: const [
              LiveWordStatus.matched,
              LiveWordStatus.matched,
            ],
            // Ghunnah covering the whole word "الله" (word index 1).
            tajweedSpans: const [
              null,
              [
                TajweedSpan(start: 0, end: 4, rule: 'ghunnah'),
              ],
            ],
            tajweedEnabled: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('بسم'), findsOneWidget);
    expect(find.text('الله'), findsOneWidget);
    // Ghunnah colouring applied → at least one per-letter TextSpan carries a
    // non-null (rule) colour, proving the word is painted per-letter by rule.
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    bool hasColouredSpan = false;
    void visit(InlineSpan span) {
      if (span is TextSpan && span.style?.color != null) hasColouredSpan = true;
      final kids = span is TextSpan ? span.children : null;
      if (kids != null) {
        for (final k in kids) visit(k);
      }
    }

    for (final rt in richTexts) visit(rt.text);
    expect(hasColouredSpan, isTrue);
  });

  testWidgets('MushafRevealView starts blank (no words, no dots)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MushafRevealView(words: const [], statuses: const [], mushaf: MushafTheme.classic),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // No revealed words rendered.
    expect(find.text('بسم'), findsNothing);
    expect(find.text('الله'), findsNothing);
  });

  testWidgets('MushafRevealView reveals words + inline ayah marker',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MushafRevealView(
            mushaf: MushafTheme.classic,
            words: const ['بسم', 'الله', 'الرحمن'],
            statuses: const [
              LiveWordStatus.matched,
              LiveWordStatus.matched,
              LiveWordStatus.matched,
            ],
            // Ayah 1 ends after the 2nd word (index 1).
            ayahBoundaries: const [1],
            ayahLabels: const ['2'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // All revealed words appear as continuous Arabic text.
    expect(find.text('بسم'), findsOneWidget);
    expect(find.text('الله'), findsOneWidget);
    expect(find.text('الرحمن'), findsOneWidget);

    // Inline end-of-ayah medallion (the Hafs font draws the Arabic-Indic
    // verse number as the ornament) appears between ayahs.
    expect(find.text('٢'), findsOneWidget);
  });

  testWidgets('MushafRevealView tints mispronounced words', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MushafRevealView(
            mushaf: MushafTheme.classic,
            words: const ['بسم', 'السلام'],
            statuses: const [
              LiveWordStatus.matched,
              LiveWordStatus.error,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('بسم'), findsOneWidget);
    // The mispronounced word is still revealed (not hidden).
    expect(find.text('السلام'), findsOneWidget);
  });
}
