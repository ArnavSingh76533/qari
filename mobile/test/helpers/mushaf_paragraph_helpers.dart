import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

/// Reads the actual word spans, excluding separators and ayah markers.
/// Fail if the paragraph is absent so colour assertions cannot pass vacuously.
List<TextSpan> mushafWordSpans() {
  final paragraphs = find
      .byType(MushafParagraph)
      .evaluate()
      .map(
        (element) => element.widget as MushafParagraph,
      )
      .toList();
  expect(paragraphs, isNotEmpty, reason: 'no Mushaf paragraph was rendered');
  final spans = <TextSpan>[];
  for (final paragraph in paragraphs) {
    expect(paragraph.wordRanges.length, paragraph.wordSpans.length);
    final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
    for (var i = 0; i < paragraph.wordRanges.length; i++) {
      final range = paragraph.wordRanges[i];
      expect(range.isValid, isTrue);
      expect(range.isCollapsed, isFalse);
      expect(range.end, lessThanOrEqualTo(text.length));
      expect(text.substring(range.start, range.end).replaceAll("\u00a0", " "),
          paragraph.wordSpans[i].toPlainText(),
          reason: 'word $i must identify its actual paragraph text');
    }
    spans.addAll(paragraph.wordSpans);
  }
  expect(spans, isNotEmpty, reason: 'no Mushaf words were rendered');
  return spans;
}

List<String> mushafWords() => [
      for (final span in mushafWordSpans()) span.toPlainText(),
    ];

TextSpan mushafWordSpan(String word) => mushafWordSpans().firstWhere(
      (span) => span.toPlainText() == word,
      orElse: () => throw StateError('Mushaf word was not rendered: $word'),
    );

/// Global glyph bounds from the paragraph's actual shaped selection boxes.
Rect mushafWordRect(WidgetTester tester, int wordIndex) {
  expect(wordIndex, greaterThanOrEqualTo(0));
  final paragraphs = find.byType(MushafParagraph);
  var remaining = wordIndex;
  for (var i = 0; i < paragraphs.evaluate().length; i++) {
    final finder = paragraphs.at(i);
    final paragraph = tester.widget<MushafParagraph>(finder);
    if (remaining >= paragraph.wordRanges.length) {
      remaining -= paragraph.wordRanges.length;
      continue;
    }
    final range = paragraph.wordRanges[remaining];
    expect(range.isValid, isTrue);
    expect(range.isCollapsed, isFalse);
    final render = tester.renderObject<RenderParagraph>(finder);
    final boxes = render.getBoxesForSelection(
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    );
    expect(boxes, isNotEmpty, reason: 'word $wordIndex has no glyph bounds');
    var rect = boxes.first.toRect();
    for (final box in boxes.skip(1)) {
      rect = rect.expandToInclude(box.toRect());
    }
    expect(rect.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
    return rect.shift(render.localToGlobal(Offset.zero));
  }
  throw RangeError('Mushaf word index $wordIndex was not rendered');
}

/// Compare actual separator advances against an independently shaped space
/// in the loaded Hafs font. This detects stretched gaps even when both page
/// margins are flush. Wrapped/collapsed spaces may have zero advance.
void expectNaturalMushafSpaces(WidgetTester tester, {required String reason}) {
  var checked = 0;
  for (final element in find.byType(MushafParagraph).evaluate()) {
    final paragraph = element.widget as MushafParagraph;
    final render = tester.renderObject<RenderParagraph>(find.byWidget(paragraph));
    final reference = TextPainter(
      text: TextSpan(text: 'ا ا', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.rtl,
      textScaler: paragraph.textScaler,
    )..layout();
    final natural = reference.getBoxesForSelection(
      const TextSelection(baseOffset: 1, extentOffset: 2),
    ).single.toRect().width;
    reference.dispose();
    expect(natural, greaterThan(0), reason: 'Hafs space metric must be loaded');
    final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
    for (var i = 0; i < text.length; i++) {
      if (text[i] != ' ' && text[i] != '\u00a0') continue;
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      for (final box in boxes) {
        checked++;
        expect(box.toRect().width, lessThanOrEqualTo(natural + 0.05),
            reason: '$reason: separator $i must not exceed the natural '
                '${natural.toStringAsFixed(3)}dp Hafs space');
      }
    }
  }
  expect(checked, greaterThan(0), reason: '$reason: no spaces were measured');
}

/// Measures every word with one finder traversal, for full-corpus checks.
List<Rect> mushafWordRects(WidgetTester tester) {
  final result = <Rect>[];
  final paragraphs = find.byType(MushafParagraph);
  final count = paragraphs.evaluate().length;
  expect(count, greaterThan(0));
  for (var i = 0; i < count; i++) {
    final finder = paragraphs.at(i);
    final paragraph = tester.widget<MushafParagraph>(finder);
    final render = tester.renderObject<RenderParagraph>(finder);
    final origin = render.localToGlobal(Offset.zero);
    for (final range in paragraph.wordRanges) {
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      expect(boxes, isNotEmpty, reason: 'a body word has no selection boxes');
      result.add(boxes
          .map((box) => box.toRect())
          .reduce((a, b) => a.expandToInclude(b))
          .shift(origin));
    }
  }
  return result;
}

/// Actual body rows, including inline marker boxes and excluding header rows.
/// Select through the final word/marker, but not the final space + sentinel.
List<Rect> mushafTextRows(WidgetTester tester) {
  final rows = <Rect>[];
  for (final word in mushafWordRects(tester)) {
    final row = rows.indexWhere((rect) => (rect.top - word.top).abs() < 0.5);
    if (row < 0) {
      rows.add(word);
    } else {
      rows[row] = rows[row].expandToInclude(word);
    }
  }
  // Only visible glyph/marker bounds count. Selecting the whole paragraph
  // includes trailing soft-break whitespace boxes outside the painted row.
  for (final element in find
      .descendant(of: find.byType(MushafParagraph), matching: find.byType(Text))
      .evaluate()) {
    final text = element.widget as Text;
    if (text.data == null || !RegExp(r'^[٠-٩]+$').hasMatch(text.data!))
      continue;
    final rect = tester.getRect(find.byWidget(text));
    var best = -1;
    var overlap = 0.0;
    for (var j = 0; j < rows.length; j++) {
      final intersection = rows[j].intersect(
          Rect.fromLTRB(rows[j].left, rect.top, rows[j].right, rect.bottom));
      if (intersection.height > overlap) {
        overlap = intersection.height;
        best = j;
      }
    }
    expect(best, greaterThanOrEqualTo(0), reason: 'marker has no text row');
    rows[best] = rows[best].expandToInclude(rect);
  }
  rows.sort((a, b) => a.top.compareTo(b.top));
  return rows;
}
