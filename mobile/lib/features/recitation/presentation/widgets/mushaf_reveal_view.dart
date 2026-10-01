import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../mushaf/mushaf_theme.dart';
import '../word_view_state.dart';

/// A continuous, book-like (Mushaf) render of the recitation as it is revealed
/// in real time.
///
/// The whole target is laid out up front as one uninterrupted RTL paragraph
/// that wraps line-by-line exactly like a printed Quran — no per-ayah
/// containers or breaks. Live verdicts only recolour words in place, so the
/// layout never shifts.
///
/// Two reading modes decide how an unspoken word looks:
///   * Tilawat (default) — the full page is visible in crisp book ink.
///   * Hifz ([hideUnspoken]) — unspoken words are fully transparent but keep
///     their exact size, so revealing a word never reflows the line. The ayah
///     medallions stay visible to guide the reciter.
///
/// The ornate ayah medallion is drawn by the KFGQPC Hafs font itself from the
/// verse number's Arabic-Indic digits, exactly as in the printed Madinah Mushaf.
///
/// A stable [caretKey] is attached to a zero-width anchor at the very end of
/// the flow, so the parent page can measure the latest revealed word's
/// position and auto-scroll it back into the upper half of the viewport.
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

  /// Verified printed line ends supply the page's line-count budget.
  /// Actual breaks use continuous paragraph shaping, not fixed word rows.
  final List<int> lineEnds;

  static final Map<(String, TextScaler), (double, double, int)> _layoutCache =
      {};

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
      final scaler = MediaQuery.textScalerOf(context);
      final layout = _fitPage(context, width, scaler);
      final content = _compose(context, width, layout.$1, layout.$2);
      final painter =
          content.measure(width, TextScaler.noScaling, maxLines: layout.$3);
      final rects = <Rect>[];
      for (final range in content.ranges) {
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        rects.add(boxes.isEmpty
            ? Rect.zero
            : boxes
                .map((b) => b.toRect())
                .reduce((a, b) => a.expandToInclude(b)));
      }
      painter.dispose();
      final paragraph = MushafParagraph(
        wordRanges: content.ranges,
        wordSpans: content.words,
        text: content.span,
        textScaler: TextScaler.noScaling,
        maxLines: layout.$3,
      );
      final tap = onMistakeTap;
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: minimumHeight),
              child: paragraph,
            ),
            if (tap != null)
              for (var i = 0; i < rects.length; i++)
                if (_state(i) == LiveWordViewState.mismatch)
                  Positioned.fromRect(
                    rect: rects[i],
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => tap(i),
                    ),
                  ),
            if (!reviewMode &&
                cursorKey != null &&
                cursor >= 0 &&
                cursor < rects.length)
              Positioned.fromRect(
                rect: rects[cursor],
                child: IgnorePointer(child: SizedBox(key: cursorKey)),
              ),
            if (caretKey != null &&
                (cursorKey == null || cursor < 0 || cursor >= words.length))
              Positioned(
                  bottom: 0,
                  left: 0,
                  child: SizedBox(key: caretKey, width: 0, height: 0)),
          ],
        ),
      );
    });
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

  // Fit the same shaped paragraph that RichText paints. Printed page metadata
  // supplies the line budget; words wrap through the paragraph's RTL engine,
  // never through independent centered rows or manually expanded word boxes.
  (double, double, int) _fitPage(
      BuildContext context, double width, TextScaler scaler) {
    final cacheKey = (
      '${words.join(' ')}|${ayahBoundaries.join(',')}|${ayahLabels.join(',')}|'
          '${blocksBefore.keys.join(',')}|${blockHeights.entries.join(',')}|'
          '$width|$minimumHeight|$fontSize|${lineEnds.length}',
      scaler
    );
    final cached = _layoutCache[cacheKey];
    if (cached != null) return cached;
    const baseHeight = 1.65;
    (double, int) measure(double size, double height) {
      final content = _compose(context, width, size, height, decorate: false);
      final painter = content.measure(width, TextScaler.noScaling);
      final lines = painter.computeLineMetrics();
      // The final, zero-height placeholder creates a soft break after the
      // last real line. Exclude that placeholder line from the visible page.
      final count = lines.length > 1 ? lines.length - 1 : 1;
      painter.dispose();
      final visible = content.measure(width, TextScaler.noScaling, maxLines: count);
      final bottom = visible.height;
      visible.dispose();
      return (bottom, count);
    }

    var size = fontSize;
    if (minimumHeight > 0) {
      var low = 1.0;
      var high = 40.0;
      final lineBudget =
          lineEnds.isEmpty ? null : lineEnds.length + blocksBefore.length;
      for (var i = 0; i < 14; i++) {
        final mid = (low + high) / 2;
        final result = measure(mid, baseHeight);
        if (result.$1 <= minimumHeight &&
            (lineBudget == null || result.$2 <= lineBudget)) {
          low = mid;
        } else {
          high = mid;
        }
      }
      size = low;
    }
    var leading = baseHeight;
    var result = measure(size, leading);
    if (minimumHeight > 0 && result.$1 < minimumHeight) {
      var low = leading;
      var high = leading + minimumHeight / scaler.scale(size);
      for (var i = 0; i < 14; i++) {
        final mid = (low + high) / 2;
        if (measure(size, mid).$1 <= minimumHeight) {
          low = mid;
        } else {
          high = mid;
        }
      }
      leading = low;
      result = measure(size, leading);
    }
    final fitted = (size, leading, result.$2);
    if (_layoutCache.length >= 8) _layoutCache.remove(_layoutCache.keys.first);
    _layoutCache[cacheKey] = fitted;
    return fitted;
  }

  _ParagraphContent _compose(
      BuildContext context, double width, double size, double leading,
      {bool decorate = true}) {
    // Scale glyphs once, then lay out widgets and text in the same dp space.
    // RichText otherwise automatically scales WidgetSpans a second time.
    size = MediaQuery.textScalerOf(context).scale(size);
    final children = <InlineSpan>[];
    final ranges = <TextRange>[];
    final wordSpans = <TextSpan>[];
    final dimensions = <PlaceholderDimensions>[];
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

    for (var i = 0; i < words.length; i++) {
      if (i > 0) text(' ');
      final block = blocksBefore[i];
      if (block != null) {
        placeholder(block, Size(width, blockHeights[i] ?? 92));
      }
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
        children.add(TextSpan(text: reservation, semanticsLabel: '',
          style: const TextStyle(color: Colors.transparent)));
        offset += reservation.length;
        final style = _arabicStyle(size, mushaf.accent, 1.65);
        final marker = TextPainter(
          text: TextSpan(text: digits, style: style),
          textDirection: TextDirection.rtl,
        )..layout();
        final markerWidth = marker.width;
        final markerHeight = marker.height;
        final baseline = marker.computeDistanceToActualBaseline(TextBaseline.alphabetic);
        marker.dispose();
        placeholder(
          OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: markerWidth, maxWidth: markerWidth,
            minHeight: markerHeight, maxHeight: markerHeight,
            child: Semantics(label: 'End of ayah $label', excludeSemantics: true,
              child: Text(digits, style: style, softWrap: false)),
          ),
          Size(0, markerHeight), baseline: baseline,
        );
      }
    }
    // Flutter only justifies soft-wrapped lines. This non-painted trailing
    // placeholder soft-wraps the last real line as well; maxLines excludes
    // the placeholder's own line without truncating any Quran text.
    text(' ');
    placeholder(
        const ExcludeSemantics(child: SizedBox.shrink()), Size(width, 0));
    return _ParagraphContent(
      TextSpan(
          style: _arabicStyle(size, mushaf.text, leading), children: children),
      dimensions,
      ranges,
      wordSpans,
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
    final value = words[index];
    if (!decorate ||
        mistake ||
        hidden ||
        (reviewMode && unspoken) ||
        spans == null ||
        spans.isEmpty) {
      return TextSpan(text: value, style: style);
    }
    final ruleAt = List<String?>.filled(value.length, null);
    for (final span in spans) {
      for (var i = span.start.clamp(0, value.length);
          i < span.end.clamp(0, value.length);
          i++) {
        ruleAt[i] = span.rule;
      }
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

/// The single shaped body paragraph and its source-word ranges. Keeping ranges
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
      : super(textAlign: TextAlign.justify, textDirection: TextDirection.rtl);
}

class _ParagraphContent {
  final TextSpan span;
  final List<PlaceholderDimensions> dimensions;
  final List<TextRange> ranges;
  final List<TextSpan> words;
  const _ParagraphContent(this.span, this.dimensions, this.ranges, this.words);

  TextPainter measure(double width, TextScaler scaler, {int? maxLines}) =>
      TextPainter(
        text: span,
        textAlign: TextAlign.justify,
        textDirection: TextDirection.rtl,
        textScaler: scaler,
        maxLines: maxLines,
      )
        ..setPlaceholderDimensions(dimensions)
        ..layout(minWidth: width, maxWidth: width);
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
