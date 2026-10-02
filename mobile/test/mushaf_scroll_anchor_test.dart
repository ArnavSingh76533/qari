import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/data/models/recitation_stream_event.dart';
import 'package:qari/features/recitation/presentation/mushaf/mushaf_theme.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

import 'mushaf_text_helpers.dart';

/// A long surah-ish block so the flow is taller than the viewport.
List<String> bigWords(int n) => List.generate(n, (i) => 'وَٰلْعَصْرِ$i');

Widget host({
  required List<String> words,
  required int cursor,
  required GlobalKey cursorKey,
  GlobalKey? caretKey,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 300,
        child: SingleChildScrollView(
          child: MushafRevealView(
            words: words,
            statuses: List<LiveWordStatus>.filled(
                words.length, LiveWordStatus.pending),
            mushaf: MushafTheme.classic,
            cursor: cursor,
            fontSize: 28,
            cursorKey: cursorKey,
            caretKey: caretKey,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('scroll anchor sits on the CURSOR word, not the end',
      (tester) async {
    final words = bigWords(60);
    final cursorKey = GlobalKey();

    // Cursor is on word 2 (near the top). The anchor must measure near the top
    // of the flow, NOT at the bottom of the 60-word document.
    await tester
        .pumpWidget(host(words: words, cursor: 2, cursorKey: cursorKey));
    await tester.pumpAndSettle();

    final ctx = cursorKey.currentContext;
    expect(ctx, isNotNull, reason: 'cursor key was never attached to any word');

    final anchor = ctx!.findRenderObject()! as RenderBox;
    final flow = find.byType(MushafRevealView);
    final flowBottom = tester.getBottomLeft(flow).dy;
    final flowTop = tester.getTopLeft(flow).dy;

    // The anchor is within the first quarter of the document, well clear of the
    // end. Before the fix this would have measured at the very bottom.
    expect(anchor.localToGlobal(Offset.zero).dy,
        lessThan(flowTop + (flowBottom - flowTop) * 0.25));
  });

  testWidgets('the anchor sits exactly on the cursor word', (tester) async {
    final words = bigWords(60);
    final cursorKey = GlobalKey();
    await tester
        .pumpWidget(host(words: words, cursor: 23, cursorKey: cursorKey));
    await tester.pumpAndSettle();

    final anchor = cursorKey.currentContext!.findRenderObject()! as RenderBox;
    final at = anchor.localToGlobal(Offset.zero);
    final word = rectOf(tester, words[23]);
    // Top-right corner of the word's glyph box (RTL: the word starts on the
    // right), measured from the paragraph itself.
    expect(at.dy, closeTo(word.top, 0.5));
    expect(at.dx, closeTo(word.right, 0.5));
    expect(mushafUnitTexts(tester), words);
  });

  testWidgets('anchor follows the cursor as it advances', (tester) async {
    final words = bigWords(60);
    final cursorKey = GlobalKey();

    double anchorDy() {
      final box = cursorKey.currentContext!.findRenderObject()! as RenderBox;
      return box.localToGlobal(Offset.zero).dy;
    }

    await tester
        .pumpWidget(host(words: words, cursor: 0, cursorKey: cursorKey));
    await tester.pumpAndSettle();
    final first = anchorDy();

    await tester
        .pumpWidget(host(words: words, cursor: 40, cursorKey: cursorKey));
    await tester.pumpAndSettle();
    final later = anchorDy();

    // The anchor must move DOWN the page as recitation progresses.
    expect(later, greaterThan(first));
  });

  testWidgets('no cursor (idle) still renders without error', (tester) async {
    final words = bigWords(30);
    final caret = GlobalKey();
    // cursor == -1: nothing active, so the trailing fallback anchor is used.
    await tester.pumpWidget(host(
        words: words, cursor: -1, cursorKey: GlobalKey(), caretKey: caret));
    await tester.pumpAndSettle();
    expect(caret.currentContext, isNotNull,
        reason: 'idle page must still expose a measurable anchor');
    expect(countOf(tester, 'وَٰلْعَصْرِ0'), 1);
  });
}
