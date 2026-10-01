import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../mushaf/mushaf_theme.dart';
import '../word_view_state.dart';

/// A printed Mushaf assembled from individually shaped RTL lines.
///
/// Each complete line is fitted as one unit: letters, natural font spaces and
/// inline ayah medallions share the same uniform transform. Verdicts, Tajweed
/// colours and Hifz visibility only change ink, never the line allocation.
/// Actual surah-ending lines keep their natural width at the right margin.
class MushafRevealView extends StatelessWidget {
  /// Complete target words in recitation order; verdicts only change their ink.
  final List<String> words;

  /// Per-word live status, aligned 1:1 with [words].
  final List<LiveWordStatus> statuses;

  /// Index of the word the reciter is expected to say next.
  ///
  /// THIS IS THE RED-WALL GUARD. Rendering routes every word through
  /// [resolveWordViewState], so a word at an index AHEAD of this cursor is
  /// always drawn as [LiveWordViewState.unspoken] — neutral ink, never red —
  /// even if [statuses] claims it was skipped. Without that guard a single
  /// stale/overlapping server window paints the rest of the surah red (the
  /// "red screen from ayah 2 down to الضالين" bug).
  final int cursor;

  /// Paper/ink palette. Required — the view paints from the Mushaf presets
  /// directly rather than from Material's colour scheme.
  final MushafTheme mushaf;

  /// Per-word tajweed spans, aligned 1:1 with [words]. When [tajweedEnabled] is
  /// true and a word has spans, its letters are coloured by their tajweed rule
  /// (exactly like the Surah reader). Offsets are word-relative and match the
  /// (plain) [words] text, not the diacritic-laden `expected` payload.
  final List<List<TajweedSpan>?> tajweedSpans;

  /// Whether to colour tajweed rules on revealed (correct) words.
  final bool tajweedEnabled;

  /// 0-based indices of each ayah's final word; markers follow these words.
  final List<int> ayahBoundaries;

  /// Verse numbers, aligned 1:1 with [ayahBoundaries].
  final List<String> ayahLabels;

  final double fontSize;

  /// Anchor key for the newest revealed word (placed at the end of the flow).
  final Key? caretKey;

  /// Anchor key attached to the word at [cursor].
  ///
  /// The page is pre-rendered in full, so the parent must scroll to the
  /// RECITATION CURSOR, not to the end of the document. Passing this lets the
  /// caller keep the active word in view without disturbing the page layout.
  final Key? cursorKey;

  /// Post-recitation review: there is no listening cursor, [cursor] is the
  /// REACH (exclusive end of the words the reciter got to), and a correct word
  /// is plain book ink so only the red-underlined mistakes stand out.
  final bool reviewMode;

  /// Called with the word index when a mistake is tapped (review mode only).
  final ValueChanged<int>? onMistakeTap;

  /// Hifz (memorisation) mode: unspoken words — including the active one —
  /// are drawn fully transparent with their layout preserved.
  final bool hideUnspoken;

  /// Full-width blocks (surah banner, Bismillah) inserted on their own line
  /// directly BEFORE the word at the given index, so a page that crosses a
  /// surah boundary opens the new surah inline, like a printed Mushaf.
  final Map<int, Widget> blocksBefore;

  /// Available paper height. Short pages spread their lines over the sheet;
  /// dense pages use a smaller font and remain scrollable at large text sizes.
  final double minimumHeight;
  final Map<int, double> blockHeights;

  /// Inclusive body-word indices of the verified printed line endings.
  final List<int> lineEnds;

  /// Inclusive body-word indices ending a surah, rather than just a page.
  /// These lines are right-aligned at their natural size and never expanded.
  final List<int> surahEnds;

  static const _openingGap = 4.0;
  static final Map<(String, TextScaler), _PageLayout> _layoutCache = {};

  const MushafRevealView({
    super.key,
    required this.words,
    required this.statuses,
    required this.mushaf,
    this.cursor = 0,
    this.ayahBoundaries = const [],
    this.ayahLabels = const [],
    this.tajweedSpans = const [],
    this.tajweedEnabled = false,
    this.fontSize = 32,
    this.caretKey,
    this.cursorKey,
    this.reviewMode = false,
    this.onMistakeTap,
    this.hideUnspoken = false,
    this.blocksBefore = const {},
    this.minimumHeight = 0,
    this.blockHeights = const {},
    this.lineEnds = const [],
    this.surahEnds = const [],
  });

  String? _labelForBoundary(int wordIndex) {
    if (ayahBoundaries.isEmpty || ayahLabels.isEmpty) return null;
    final pos = ayahBoundaries.indexOf(wordIndex);
    return pos >= 0 && pos < ayahLabels.length ? ayahLabels[pos] : null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (words.isEmpty) return SizedBox(height: minimumHeight, key: caretKey);
      final width = constraints.maxWidth;
      if (!width.isFinite || width <= 0) return const SizedBox.shrink();
      final layout =
          _layoutPage(context, width, MediaQuery.textScalerOf(context));
      final gap =
          math.max(0.0, minimumHeight - layout.height) / layout.lines.length;
      final children = <Widget>[];
      var top = 0.0;
      for (final line in layout.lines) {
        final block = blocksBefore[line.start];
        if (block != null) {
          final nativeHeight = blockHeights[line.start] ?? 92;
          final height = nativeHeight * layout.blockScale;
          top += _openingGap * layout.blockScale;
          children.add(Positioned(
              top: top,
              left: 0,
              right: 0,
              height: height,
              child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                      width: width, height: nativeHeight, child: block))));
          top += height + _openingGap * layout.blockScale;
        }
        top += gap;
        final height = line.nativeSize.height * line.scale;
        children.add(Positioned(
            top: top,
            left: 0,
            right: 0,
            height: height,
            child: _buildLine(context, line, layout.fontSize, layout.leading)));
        top += height;
      }
      if (caretKey != null &&
          (cursorKey == null || cursor < 0 || cursor >= words.length)) {
        children.add(Positioned(
            bottom: 0,
            left: 0,
            child: SizedBox(key: caretKey, width: 0, height: 0)));
      }
      return Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
              height: math.max(minimumHeight, top),
              child: Stack(clipBehavior: Clip.none, children: children)));
    });
  }

  Widget _buildLine(
      BuildContext context, _LineLayout line, double size, double leading) {
    var content = _compose(context, line.start, line.end, size, leading);
    final painter = content.measure(line.nativeSize.width);
    final rects = <Rect>[];
    for (final range in content.ranges) {
      final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end));
      rects.add(boxes.isEmpty
          ? Rect.zero
          : boxes
              .map((b) => b.toRect())
              .reduce((a, b) => a.expandToInclude(b)));
    }
    final markerOffsets = <int, double>{};
    final placeholders = painter.inlinePlaceholderBoxes ?? const [];
    for (final entry in content.markers.entries) {
      final (placeholderIndex, markerWidth) = entry.value;
      if (placeholderIndex < placeholders.length) {
        markerOffsets[entry.key] = rects[entry.key - line.start].left -
            markerWidth -
            placeholders[placeholderIndex].left;
      }
    }
    painter.dispose();
    content = _compose(context, line.start, line.end, size, leading,
        markerOffsets: markerOffsets);
    final tap = onMistakeTap;
    return FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.centerRight,
        child: SizedBox.fromSize(
            size: line.nativeSize,
            child: Stack(clipBehavior: Clip.none, children: [
              MushafParagraph(
                  wordRanges: content.ranges,
                  wordSpans: content.words,
                  text: content.span,
                  textScaler: TextScaler.noScaling,
                  maxLines: 1),
              if (tap != null)
                for (var local = 0; local < rects.length; local++)
                  if (_state(line.start + local) == LiveWordViewState.mismatch)
                    Positioned.fromRect(
                        rect: rects[local],
                        child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => tap(line.start + local))),
              if (!reviewMode &&
                  cursorKey != null &&
                  cursor >= line.start &&
                  cursor <= line.end)
                Positioned.fromRect(
                    rect: rects[cursor - line.start],
                    child: IgnorePointer(child: SizedBox(key: cursorKey))),
            ])));
  }

  LiveWordViewState _state(int index) {
    final status =
        index < statuses.length ? statuses[index] : LiveWordStatus.pending;
    return reviewMode
        ? resolveReviewWordViewState(
            serverStatus: status, index: index, reach: cursor)
        : resolveWordViewState(
            serverStatus: status, index: index, cursor: cursor);
  }

  _PageLayout _layoutPage(
      BuildContext context, double width, TextScaler scaler) {
    final key = (
      '${words.join(' ')}|${ayahBoundaries.join(',')}|${ayahLabels.join(',')}|'
          '${lineEnds.join(',')}|${surahEnds.join(',')}|${blocksBefore.keys.join(',')}|'
          '${blockHeights.entries.join(',')}|$width|$minimumHeight|$fontSize',
      scaler
    );
    final cached = _layoutCache[key];
    if (cached != null) return cached;
    final baseSize = scaler.scale(fontSize);
    var size = baseSize;
    var ends = _allocateLines(context, width, size);
    var result = _measurePage(context, width, size, ends);
    // Without printed metadata (surah/range targets or multi-page ayahs),
    // measure complete word/marker units at a readable size and wrap them.
    // Long targets retain a readable minimum and scroll as a whole.
    if (lineEnds.isEmpty &&
        minimumHeight > 0 &&
        result.height > minimumHeight) {
      var low = math.min(size, scaler.scale(13));
      var high = size;
      for (var i = 0; i < 10; i++) {
        final mid = (low + high) / 2;
        final candidateEnds = _allocateLines(context, width, mid);
        final candidate = _measurePage(context, width, mid, candidateEnds);
        if (candidate.height <= minimumHeight) {
          low = mid;
        } else {
          high = mid;
        }
      }
      size = low;
      ends = _allocateLines(context, width, size);
      result = _measurePage(context, width, size, ends);
    }
    if (_layoutCache.length >= 8) _layoutCache.remove(_layoutCache.keys.first);
    _layoutCache[key] = result;
    return result;
  }

  List<int> _allocateLines(BuildContext context, double width, double size) {
    final forced = <int>{
      for (final start in blocksBefore.keys)
        if (start > 0 && start < words.length) start - 1,
      for (final end in surahEnds)
        if (end >= 0 && end < words.length) end,
    };
    var previous = -1;
    final valid = lineEnds.isNotEmpty &&
        lineEnds.every((end) {
          final ok = end > previous && end < words.length;
          previous = end;
          return ok;
        });
    if (valid && lineEnds.last == words.length - 1) {
      return ({...lineEnds, ...forced}.toList()..sort());
    }
    final space = TextPainter(
        text: TextSpan(text: ' ', style: _arabicStyle(size, mushaf.text, 1.65)),
        textDirection: TextDirection.rtl)
      ..layout();
    final spaceWidth = space.width;
    space.dispose();
    final ends = <int>[];
    final widths = <String, double>{};
    var start = 0;
    var used = 0.0;
    for (var i = 0; i < words.length; i++) {
      final key = '${words[i]}|${_labelForBoundary(i)}';
      final wordWidth = widths.putIfAbsent(key, () {
        final painter =
            _compose(context, i, i, size, 1.65, decorate: false).measure();
        final measured = painter.width;
        painter.dispose();
        return measured;
      });
      if (i > start &&
          (forced.contains(i - 1) || used + spaceWidth + wordWidth > width)) {
        ends.add(i - 1);
        start = i;
        used = 0;
      }
      used += (i == start ? 0 : spaceWidth) + wordWidth;
    }
    ends.add(words.length - 1);
    return ends;
  }

  _PageLayout _measurePage(
      BuildContext context, double width, double size, List<int> ends) {
    const normalLeading = 1.65;
    final sizes = <Size>[];
    final scales = <double>[];
    var start = 0;
    for (final end in ends) {
      final painter =
          _compose(context, start, end, size, normalLeading, decorate: false)
              .measure();
      sizes.add(Size(painter.width, painter.height));
      scales.add(width / math.max(painter.width, 0.001));
      painter.dispose();
      start = end + 1;
    }
    final bodyScales = [
      for (var i = 0; i < ends.length; i++)
        if (!surahEnds.contains(ends[i])) scales[i]
    ]..sort();
    final endingScale = bodyScales.isEmpty
        ? 1.0
        : math.min(1.0, bodyScales[bodyScales.length ~/ 2]);
    for (var i = 0; i < ends.length; i++) {
      if (surahEnds.contains(ends[i]))
        scales[i] = math.min(scales[i], endingScale);
    }
    final openings = blocksBefore.keys
        .where((i) => i >= 0 && i < words.length)
        .fold(0.0, (height, i) => height + (blockHeights[i] ?? 92) + 2 * _openingGap);
    final bodyHeight =
        List.generate(sizes.length, (i) => sizes[i].height * scales[i])
            .fold(0.0, (a, b) => a + b);
    var leading = normalLeading;
    var blockScale = 1.0;
    List<Size> measureSizes(double lineLeading) {
      final measured = <Size>[];
      var first = 0;
      for (final end in ends) {
        final painter = _compose(context, first, end, size, lineLeading,
          decorate: false).measure();
        measured.add(Size(painter.width, painter.height));
        painter.dispose();
        first = end + 1;
      }
      return measured;
    }
    double pageHeight(List<Size> measured) => openings * blockScale +
      List.generate(measured.length, (i) => measured[i].height * scales[i])
        .fold(0.0, (a, b) => a + b);
    if (lineEnds.isNotEmpty && minimumHeight > 0 && bodyHeight + openings > minimumHeight) {
      if (openings > 0) {
        blockScale = ((minimumHeight - bodyHeight) / openings).clamp(0.5, 1.0);
      }
      // TextPainter rounds each native line height separately. Fit those exact
      // measured heights; multiplying a page-wide height ratio can overshoot.
      var low = 1.1;
      var high = normalLeading;
      for (var i = 0; i < 12; i++) {
        final mid = (low + high) / 2;
        if (pageHeight(measureSizes(mid)) <= minimumHeight) {
          low = mid;
        } else {
          high = mid;
        }
      }
      leading = low;
      sizes.setAll(0, measureSizes(leading));
    }
    final lines = <_LineLayout>[];
    var height = openings * blockScale;
    start = 0;
    for (var i = 0; i < ends.length; i++) {
      lines.add(_LineLayout(start, ends[i], sizes[i], scales[i]));
      height += sizes[i].height * scales[i];
      start = ends[i] + 1;
    }
    return _PageLayout(size, leading, blockScale, height, lines);
  }

  _ParagraphContent _compose(
      BuildContext context, int start, int end, double size, double leading,
      {bool decorate = true, Map<int, double> markerOffsets = const {}}) {
    final children = <InlineSpan>[];
    final ranges = <TextRange>[];
    final wordSpans = <TextSpan>[];
    final dimensions = <PlaceholderDimensions>[];
    final markers = <int, (int, double)>{};
    var offset = 0;
    void text(String value) {
      children.add(TextSpan(text: value));
      offset += value.length;
    }

    void placeholder(Widget child, Size size, {double? baseline}) {
      final alignment = baseline == null
          ? PlaceholderAlignment.top
          : PlaceholderAlignment.baseline;
      children.add(WidgetSpan(
        alignment: alignment,
        baseline: baseline == null ? null : TextBaseline.alphabetic,
        child: MediaQuery.withNoTextScaling(
            child: SizedBox.fromSize(size: size, child: child)),
      ));
      dimensions.add(PlaceholderDimensions(
          size: size,
          alignment: alignment,
          baseline: baseline == null ? null : TextBaseline.alphabetic,
          baselineOffset: baseline));
      offset++;
    }

    for (var i = start; i <= end; i++) {
      if (i > start) text(' ');
      final span = _wordSpan(i, context, decorate);
      ranges.add(TextRange(start: offset, end: offset + words[i].length));
      wordSpans.add(span);
      children.add(span);
      offset += words[i].length;
      final label = _labelForBoundary(i);
      if (label != null) {
        final digits = toArabicIndicDigits(label);
        // Skia treats a WidgetSpan as a separate breakable word even after a
        // word joiner. Reserve the medallion as joined text, then paint its
        // inline widget over that reservation. The marker cannot orphan and
        // the body words remain TextSpans in the same shaped paragraph.
        final reservation = '\u2060$digits\u200f';
        children.add(TextSpan(
            text: reservation,
            semanticsLabel: '',
            style: const TextStyle(color: Colors.transparent)));
        offset += reservation.length;
        final style = _arabicStyle(size, mushaf.accent, leading);
        final marker = TextPainter(
          text: TextSpan(text: digits, style: style),
          textDirection: TextDirection.rtl,
        )..layout();
        final markerWidth = marker.width;
        final markerHeight = marker.height;
        final baseline =
            marker.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        marker.dispose();
        markers[i] = (dimensions.length, markerWidth);
        placeholder(
          Baseline(
            baseline: baseline,
            baselineType: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(markerOffsets[i] ?? 0, 0),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: markerWidth,
                maxWidth: markerWidth,
                minHeight: markerHeight,
                maxHeight: markerHeight,
                child: Semantics(
                    label: 'End of ayah $label',
                    excludeSemantics: true,
                    child: Text(digits, style: style, softWrap: false)),
              ),
            ),
          ),
          Size(0, markerHeight),
          baseline: baseline,
        );
      }
    }
    return _ParagraphContent(
      TextSpan(
          style: _arabicStyle(size, mushaf.text, leading), children: children),
      dimensions,
      ranges,
      wordSpans,
      markers,
    );
  }

  TextSpan _wordSpan(int index, BuildContext context, bool decorate) {
    final state = _state(index);
    final mistake = state == LiveWordViewState.mismatch;
    final unspoken = state == LiveWordViewState.unspoken;
    final active = state == LiveWordViewState.active;
    final hidden = !reviewMode && hideUnspoken && (unspoken || active);
    final ink = mistake
        ? mushaf.mismatchInk
        : hidden
            ? mushaf.text.withValues(alpha: 0)
            : reviewMode && unspoken
                ? mushaf.ghostInk
                : mushaf.text;
    final style = TextStyle(
      color: decorate ? ink : mushaf.text,
      backgroundColor: !decorate || hidden || reviewMode
          ? null
          : active
              ? mushaf.activeTint
              : state == LiveWordViewState.correct
                  ? mushaf.correctTint
                  : null,
      decoration:
          decorate && mistake ? TextDecoration.underline : TextDecoration.none,
      decorationColor: mushaf.mismatchInk.withValues(alpha: 0.9),
      decorationThickness: 2,
    );
    final spans = tajweedEnabled && index < tajweedSpans.length
        ? tajweedSpans[index]
        : null;
    final original = words[index];
    // A corpus word can contain a pause sign after a space. Keep that space
    // non-breaking and unexpanded, so the sign stays with its Arabic word.
    // The semantic label retains the exact source text and ASR word identity.
    final value = original.replaceAll(' ', '\u00a0');
    if (!decorate ||
        mistake ||
        hidden ||
        (reviewMode && unspoken) ||
        spans == null ||
        spans.isEmpty) {
      return TextSpan(text: value, semanticsLabel: original, style: style);
    }
    final ruleAt = List<String?>.filled(value.length, null);
    for (final span in spans) {
      for (var i = span.start.clamp(0, value.length);
          i < span.end.clamp(0, value.length);
          i++) {
        ruleAt[i] = span.rule;
      }
    }
    // A colour boundary must not separate a base letter from its harakat.
    // Such splits produce invalid shaped selection boxes in justified RTL
    // text. Paint each grapheme using its applicable tajweed rule.
    var clusterOffset = 0;
    for (final cluster in value.characters) {
      String? rule;
      for (var i = clusterOffset; i < clusterOffset + cluster.length; i++) {
        rule ??= ruleAt[i];
      }
      for (var i = clusterOffset; i < clusterOffset + cluster.length; i++) {
        ruleAt[i] = rule;
      }
      clusterOffset += cluster.length;
    }
    final children = <TextSpan>[];
    var i = 0;
    while (i < value.length) {
      final rule = ruleAt[i];
      var end = i + 1;
      while (end < value.length && ruleAt[end] == rule) {
        end++;
      }
      children.add(TextSpan(
          text: value.substring(i, end),
          semanticsLabel: original.substring(i, end),
          style: TextStyle(
              color: rule == null
                  ? null
                  : AppTheme.ensureContrast(AppTheme.getTajweedColor(rule),
                      Theme.of(context).brightness))));
      i = end;
    }
    return TextSpan(style: style, children: children);
  }
}

/// One shaped RTL line and its source-word ranges. Keeping ranges
/// alongside the spans lets cursor anchors and review taps use glyph geometry
/// without adding inline word containers or changing Arabic shaping.
class MushafParagraph extends RichText {
  final List<TextRange> wordRanges;
  final List<TextSpan> wordSpans;

  MushafParagraph(
      {super.key,
      required this.wordRanges,
      required this.wordSpans,
      required super.text,
      required super.textScaler,
      required super.maxLines})
      // Stock paragraph justification expands blank spaces. Keep the Hafs
      // font's natural advances on every row, including short/final rows.
      : super(
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            softWrap: false);
}

class _ParagraphContent {
  final TextSpan span;
  final List<PlaceholderDimensions> dimensions;
  final List<TextRange> ranges;
  final List<TextSpan> words;
  final Map<int, (int, double)> markers;
  const _ParagraphContent(
      this.span, this.dimensions, this.ranges, this.words, this.markers);

  TextPainter measure([double? width]) => TextPainter(
      text: span,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      textScaler: TextScaler.noScaling,
      maxLines: width == null ? null : 1)
    ..setPlaceholderDimensions(dimensions)
    ..layout(minWidth: width ?? 0, maxWidth: width ?? double.infinity);
}

class _LineLayout {
  final int start;
  final int end;
  final Size nativeSize;
  final double scale;
  const _LineLayout(this.start, this.end, this.nativeSize, this.scale);
}

class _PageLayout {
  final double fontSize;
  final double leading;
  final double blockScale;
  final double height;
  final List<_LineLayout> lines;
  const _PageLayout(
      this.fontSize, this.leading, this.blockScale, this.height, this.lines);
}

TextStyle _arabicStyle(double size, Color? color, double height) =>
    AppTheme.arabicTextStyle(fontSize: size, color: color)
        .copyWith(fontSize: size, height: height);

/// "12" -> "١٢". Non-digits pass through unchanged.
String toArabicIndicDigits(String western) {
  final out = StringBuffer();
  for (final c in western.codeUnits) {
    out.writeCharCode(c >= 0x30 && c <= 0x39 ? 0x0660 + (c - 0x30) : c);
  }
  return out.toString();
}
