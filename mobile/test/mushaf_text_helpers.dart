// Inspect the word/marker paragraphs inside independently fitted lines.
// localToGlobal includes the FittedBox transform for taps and cursor checks.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qari/features/recitation/presentation/widgets/mushaf_reveal_view.dart';

/// Every word/marker paragraph, in reading order, excluding surah openings.
List<Element> mushafParagraphElements(WidgetTester tester) => find
    .descendant(
      of: find.byType(MushafRevealView),
      matching: find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('mushaf-unit-') &&
            w.textDirection == TextDirection.rtl,
      ),
    )
    .evaluate()
    .toList();

/// The page's own root span. `Text.rich` wraps the span it is given inside a
/// single-child root carrying the effective style; unwrap such wrappers.
TextSpan? _rootOf(RichText paragraph) {
  final root = paragraph.text;
  return root is TextSpan ? root : null;
}

/// Word and medallion spans of one paragraph, in reading order.
List<TextSpan> _units(RichText paragraph) {
  final root = _rootOf(paragraph);
  if (root == null) return const [];
  return [
    for (final child in root.children ?? const <InlineSpan>[])
      if (child is TextSpan && child.style != null) child,
  ];
}

/// All word and medallion spans on the page, in reading order.
List<TextSpan> mushafUnits(WidgetTester tester) => [
  for (final e in mushafParagraphElements(tester))
    ..._units(e.widget as RichText),
];

/// The plain text of every word / medallion on the page, in reading order.
List<String> mushafUnitTexts(WidgetTester tester) => [
  for (final s in mushafUnits(tester)) s.toPlainText(),
];

/// How many times [text] (a word or `ayahMarkerText(label)`) is rendered.
int countOf(WidgetTester tester, String text) =>
    mushafUnits(tester)
        .where((s) => s.toPlainText() == mushafDisplayText(text))
        .length;

/// The span of the first (or last) occurrence of [text], or null.
TextSpan? spanOf(WidgetTester tester, String text, {bool last = false}) {
  final shown = mushafDisplayText(text);
  final matches = mushafUnits(tester)
      .where((s) => s.toPlainText() == shown)
      .toList();
  if (matches.isEmpty) return null;
  return last ? matches.last : matches.first;
}

/// The rendered ink colour of [text].
Color? inkOf(WidgetTester tester, String text, {bool last = false}) =>
    spanOf(tester, text, last: last)?.style?.color;

/// The font size of the Mushaf paragraph.
double? mushafFontSize(WidgetTester tester) {
  final elements = mushafParagraphElements(tester);
  if (elements.isEmpty) return null;
  return (elements.first.widget as RichText).text.style?.fontSize;
}

/// The global rect of the glyph boxes of [text] (first or last occurrence).
Rect rectOf(WidgetTester tester, String text, {bool last = false}) {
  final hits = <(RenderParagraph, TextRange)>[];
  for (final element in mushafParagraphElements(tester)) {
    final root = _rootOf(element.widget as RichText);
    if (root == null) continue;
    var offset = 0;
    for (final child in root.children ?? const <InlineSpan>[]) {
      final length = child.toPlainText().length;
      if (child is TextSpan &&
          child.style != null &&
          child.toPlainText() == mushafDisplayText(text)) {
        hits.add((
          element.renderObject! as RenderParagraph,
          TextRange(start: offset, end: offset + length),
        ));
      }
      offset += length;
    }
  }
  if (hits.isEmpty) throw StateError('"$text" is not on the Mushaf page');
  final (paragraph, range) = last ? hits.last : hits.first;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: range.start, extentOffset: range.end),
    boxHeightStyle: ui.BoxHeightStyle.max,
  );
  if (boxes.isEmpty) throw StateError('"$text" has no glyph boxes');
  var rect = boxes.first.toRect();
  for (final b in boxes.skip(1)) {
    rect = rect.expandToInclude(b.toRect());
  }
  return Rect.fromPoints(
    paragraph.localToGlobal(rect.topLeft),
    paragraph.localToGlobal(rect.bottomRight),
  );
}

/// Taps the centre of [text] on the page.
Future<void> tapWord(WidgetTester tester, String text) =>
    tester.tapAt(rectOf(tester, text).center);

/// The background wash painted behind [text], if any. `Paint.color` comes
/// back in a float colour space, so it is normalised to a plain ARGB colour
/// that compares equal to the theme's const tints.
Color? washOf(WidgetTester tester, String text) {
  final paint = spanOf(tester, text)?.style?.background;
  return paint == null ? null : Color(paint.color.toARGB32());
}

/// Background washes painted behind words.
Set<Color> washes(WidgetTester tester) => {
  for (final s in mushafUnits(tester))
    if (s.style?.background case final Paint p) Color(p.color.toARGB32()),
};

/// Number of words carrying the mistake underline in [color].
int underlineCount(WidgetTester tester, Color color) =>
    mushafUnits(tester)
        .where(
          (s) =>
              s.style?.decoration == TextDecoration.underline &&
              s.style?.decorationColor?.toARGB32() ==
                  color.withValues(alpha: 0.9).toARGB32(),
        )
        .length;

/// Words whose RENDERED colour is [color].
List<String> wordsInColor(WidgetTester tester, Color color) => [
  for (final s in mushafUnits(tester))
    if (s.style?.color == color) s.toPlainText(),
];
