import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../mushaf/mushaf_theme.dart';
import '../word_view_state.dart';

/// A continuous, book-like (Mushaf) render of the recitation target.
///
/// The whole page body is ONE justified right-to-left paragraph — a single
/// [Text.rich] whose spans are the words, the natural inter-word spaces and
/// the inline ayah medallions — exactly like a printed Madinah Mushaf:
///
///   * words sit tightly next to each other, separated only by the font's own
///     space glyph (no per-word widgets, no `Wrap` spacing, no spacers);
///   * every line is stretched flush to both margins by `TextAlign.justify`,
///     so the left and right edges of the block are straight;
///   * everything is set in the KFGQPC Uthmanic Script HAFS face, including
///     the ayah medallion (the verse number in Arabic-Indic digits), which
///     the font draws as the ornate end-of-ayah mark with the number inside.
///
/// Live verdicts only recolour spans in place, so the layout never shifts.
///
/// Two reading modes decide how an unspoken word looks:
///   * Tilawat (default) — the full page is visible in crisp book ink.
///   * Hifz ([hideUnspoken]) — unspoken words are fully transparent but keep
///     their exact size, so revealing a word never reflows the line. The ayah
///     medallions stay visible to guide the reciter.
///
/// Surah openings ([blocksBefore]) are full-width widgets that always start a
/// fresh line, so the body is split into one justified paragraph per surah
/// segment; a page inside a single surah is literally one `Text.rich`.
///
/// A stable [cursorKey] is attached to a zero-size anchor positioned at the
/// top-right corner of the cursor word (measured from the paragraph's own
/// glyph boxes, never by inserting anything into the text), so the parent
/// page can auto-scroll the active word back into the upper half of the
/// viewport. [caretKey] is a fallback anchor at the end of the sheet.
class MushafRevealView extends StatefulWidget {
  /// Words revealed so far, in recitation order. Starts empty → blank canvas.
  final List<String> words;

  /// Per-word live status, aligned 1:1 with [words]. Only used for tinting
  /// mispronounced / skipped words; correct words read as plain book ink.
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

  /// 0-based indices (into [words]) of the LAST word of each ayah. The ayah
  /// medallion is rendered inline right after that word.
  final List<int> ayahBoundaries;

  /// Verse numbers, aligned 1:1 with [ayahBoundaries].
  final List<String> ayahLabels;

  /// Font size used when the view is not asked to fill a sheet
  /// ([minimumHeight] == 0).
  final double fontSize;

  /// Anchor key for the end of the sheet, used only while no word is active.
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

  /// Available paper height. When > 0 the font size is chosen so the whole
  /// page fits the sheet, and the line pitch is then opened up so the lines
  /// spread evenly over the paper like the fixed 15-line Madinah layout.
  final double minimumHeight;

  /// Heights of the [blocksBefore] widgets, used when fitting the page.
  final Map<int, double> blockHeights;

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
  });

  /// Natural line pitch of the Uthmanic face: tight enough to read as a solid
  /// block, loose enough for the stacked harakat and the ayah medallions.
  static const double baseLineHeight = 1.7;

  /// Widest the line pitch is allowed to open when spreading a short page.
  static const double _maxLineHeight = 3.0;

  static const double _minFontSize = 13;
  static const double _maxFontSize = 48;
  static const double _defaultBlockHeight = 92;

  static final Map<String, ({double fontSize, double lineHeight})> _fitCache =
      {};

  @override
  State<MushafRevealView> createState() => _MushafRevealViewState();
}

/// The inline end-of-ayah medallion text: the verse number in Arabic-Indic
/// digits. The KFGQPC Hafs font draws those digits as the ornate end-of-ayah
/// medallion with the number inside it (one glyph, even for "١٢٣"), exactly
/// as in the printed Madinah Mushaf — so no U+06DD prefix, which this font
/// would render as a second, empty medallion.
String ayahMarkerText(String label) => toArabicIndicDigits(label);

/// The word exactly as it is drawn on the page.
///
/// The bundled KFGQPC Hafs face (v0.09) draws two of the corpus' Quranic
/// annotation marks as a large filled disc instead of the small sign: the
/// silent-alif rounded zero (U+06DF) and the iqlab low meem (U+06ED). The
/// same face draws U+06E0 as the small rounded zero and U+06E2 as the small
/// meem, so those are substituted for display only. Both are one code unit,
/// so word lengths and tajweed offsets are unchanged.
String mushafDisplayText(String word) =>
    word.replaceAll('\u06DF', '\u06E0').replaceAll('\u06ED', '\u06E2');

/// "12" -> "١٢". Non-digits pass through unchanged.
String toArabicIndicDigits(String western) {
  final out = StringBuffer();
  for (final c in western.codeUnits) {
    out.writeCharCode(c >= 0x30 && c <= 0x39 ? 0x0660 + (c - 0x30) : c);
  }
  return out.toString();
}

/// A run of consecutive words rendered as one justified paragraph.
class _Segment {
  final int start;
  final int end; // exclusive
  const _Segment(this.start, this.end);
}

class _MushafRevealViewState extends State<MushafRevealView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  String? _labelForBoundary(int wordIndex) {
    final w = widget;
    if (w.ayahBoundaries.isEmpty || w.ayahLabels.isEmpty) return null;
    final pos = w.ayahBoundaries.indexOf(wordIndex);
    return pos >= 0 && pos < w.ayahLabels.length ? w.ayahLabels[pos] : null;
  }

  /// Splits the page at every surah opening so each block sits on its own
  /// line between two justified paragraphs.
  List<_Segment> _segments() {
    final n = widget.words.length;
    final cuts = widget.blocksBefore.keys.where((i) => i > 0 && i < n).toList()
      ..sort();
    final out = <_Segment>[];
    var start = 0;
    for (final cut in cuts) {
      out.add(_Segment(start, cut));
      start = cut;
    }
    out.add(_Segment(start, n));
    return out;
  }

  /// The paragraph's plain text (words, spaces, medallions) for [segment].
  String _segmentText(_Segment segment) {
    final buf = StringBuffer();
    for (var i = segment.start; i < segment.end; i++) {
      if (i > segment.start) buf.write(' ');
      buf.write(mushafDisplayText(widget.words[i]));
      final label = _labelForBoundary(i);
      if (label != null) {
        buf.write(' ');
        buf.write(ayahMarkerText(label));
      }
    }
    return buf.toString();
  }

  TextStyle _baseStyle(BuildContext context, double size, double lineHeight) {
    // Start from the app's Quran style (Uthmanic Hafs face, zero letter
    // spacing) and resolve it against the ambient DefaultTextStyle, so the
    // paragraph we measure is byte-for-byte the paragraph we paint.
    final base =
        AppTheme.arabicTextStyle(fontSize: size, color: widget.mushaf.text)
            .copyWith(
      fontSize: size,
      height: lineHeight,
      letterSpacing: 0,
      wordSpacing: 0,
      leadingDistribution: TextLeadingDistribution.even,
    );
    return DefaultTextStyle.of(context).style.merge(base);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.words.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final fit = _fitPage(context, constraints.maxWidth);
      return _buildPage(context, fit.fontSize, fit.lineHeight);
    });
  }

  // ── Page fitting ───────────────────────────────────────────────────────

  /// Measures the real paragraphs (same text, same face, same width) rather
  /// than guessing from character counts. Quran text and verse order never
  /// change, so the result is cached per page/width.
  ({double fontSize, double lineHeight}) _fitPage(
      BuildContext context, double width) {
    final w = widget;
    if (w.minimumHeight <= 0 || !width.isFinite) {
      return (
        fontSize: w.fontSize,
        lineHeight: MushafRevealView.baseLineHeight
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    final segments = _segments();
    final cacheKey = [
      w.words.join('\u0000'),
      w.ayahBoundaries.join(','),
      w.ayahLabels.join(','),
      w.blocksBefore.keys.join(','),
      w.blockHeights.entries.map((e) => '${e.key}:${e.value}').join(','),
      width,
      w.minimumHeight,
      scaler,
    ].join('\u0001');
    final cached = MushafRevealView._fitCache[cacheKey];
    if (cached != null) return cached;

    final texts = [for (final s in segments) _segmentText(s)];
    double heightAt(double size, double lineHeight) {
      final style = _baseStyle(context, size, lineHeight);
      var total = 0.0;
      for (final text in texts) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.justify,
          textScaler: scaler,
        )..layout(maxWidth: width);
        total += painter.height;
        painter.dispose();
      }
      for (final i in w.blocksBefore.keys) {
        total += w.blockHeights[i] ?? MushafRevealView._defaultBlockHeight;
      }
      return total;
    }

    // 1. The largest face that fits the sheet at the natural line pitch.
    var low = MushafRevealView._minFontSize;
    var high = MushafRevealView._maxFontSize;
    for (var i = 0; i < 7; i++) {
      final mid = (low + high) / 2;
      if (heightAt(mid, MushafRevealView.baseLineHeight) <= w.minimumHeight) {
        low = mid;
      } else {
        high = mid;
      }
    }
    final size = low;

    // 2. Open the line pitch so the lines spread evenly over the paper.
    var lhLow = MushafRevealView.baseLineHeight;
    var lhHigh = MushafRevealView._maxLineHeight;
    for (var i = 0; i < 6; i++) {
      final mid = (lhLow + lhHigh) / 2;
      if (heightAt(size, mid) <= w.minimumHeight) {
        lhLow = mid;
      } else {
        lhHigh = mid;
      }
    }

    final fit = (fontSize: size, lineHeight: lhLow);
    if (MushafRevealView._fitCache.length >= 8) {
      MushafRevealView._fitCache.remove(MushafRevealView._fitCache.keys.first);
    }
    MushafRevealView._fitCache[cacheKey] = fit;
    return fit;
  }

  // ── Rendering ──────────────────────────────────────────────────────────

  Widget _buildPage(BuildContext context, double size, double lineHeight) {
    final w = widget;
    _disposeRecognizers();

    // Every word's final look is decided by [resolveWordViewState], never by
    // [LiveWordStatus] alone — that is what guarantees a word ahead of the
    // cursor can never be painted as a mistake.
    final viewStates = w.reviewMode
        ? <LiveWordViewState>[
            for (var i = 0; i < w.statuses.length; i++)
              resolveReviewWordViewState(
                serverStatus: w.statuses[i],
                index: i,
                reach: w.cursor,
              ),
          ]
        : resolveWordViewStates(statuses: w.statuses, cursor: w.cursor);

    final style = _baseStyle(context, size, lineHeight);
    final brightness = w.mushaf.isDark ? Brightness.dark : Brightness.light;
    final hasCursor = !w.reviewMode &&
        w.cursorKey != null &&
        w.cursor >= 0 &&
        w.cursor < w.words.length;

    final children = <Widget>[];
    for (final segment in _segments()) {
      final block = w.blocksBefore[segment.start];
      if (block != null) children.add(block);

      final spans = <InlineSpan>[];
      var offset = 0;
      TextRange? cursorRange;
      for (var i = segment.start; i < segment.end; i++) {
        if (i > segment.start) {
          spans.add(const TextSpan(text: ' '));
          offset += 1;
        }
        final viewState =
            i < viewStates.length ? viewStates[i] : LiveWordViewState.unspoken;
        if (hasCursor && i == w.cursor) {
          cursorRange =
              TextRange(start: offset, end: offset + w.words[i].length);
        }
        spans.add(_wordSpan(i, viewState, brightness));
        offset += w.words[i].length;
        final label = _labelForBoundary(i);
        if (label != null) {
          final marker = ayahMarkerText(label);
          spans.add(const TextSpan(text: ' '));
          spans.add(TextSpan(
            text: marker,
            style: TextStyle(color: w.mushaf.accent),
          ));
          offset += 1 + marker.length;
        }
      }

      // The paragraph: one justified RTL block, flush at both margins.
      final paragraph = Text.rich(
        TextSpan(style: style, children: spans),
        style: style,
        textAlign: TextAlign.justify,
        textDirection: TextDirection.rtl,
        softWrap: true,
      );
      children.add(cursorRange == null
          ? paragraph
          : _AnchoredParagraph(
              anchorRange: cursorRange,
              anchor: SizedBox(key: w.cursorKey, width: 0, height: 0),
              child: paragraph,
            ));
    }

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: w.minimumHeight),
            child: body,
          ),
          // A positioned fallback measures the end of the sheet without
          // adding a line or shifting words when listening starts.
          if (w.caretKey != null && !hasCursor)
            Positioned(
              bottom: 0,
              left: 0,
              child: SizedBox(key: w.caretKey, width: 0, height: 0),
            ),
        ],
      ),
    );
  }

  /// One word of the paragraph, styled per the Mushaf word-state spec:
  ///   unspoken  -> plain book ink (ghost ink on the review page)
  ///   active    -> book ink on the golden listening wash, with a soft glow
  ///   correct   -> book ink on a soft green wash (live only)
  ///   mismatch  -> red ink + a red underline (the only red on the page)
  /// In Hifz, unspoken and active words are transparent but keep their size.
  InlineSpan _wordSpan(int i, LiveWordViewState state, Brightness brightness) {
    final w = widget;
    final text = mushafDisplayText(w.words[i]);
    final isMistake = state == LiveWordViewState.mismatch;
    final isActive = state == LiveWordViewState.active;
    final isUnspoken = state == LiveWordViewState.unspoken;
    final hidden = !w.reviewMode && w.hideUnspoken && (isUnspoken || isActive);
    final ghost = w.reviewMode && isUnspoken;
    final isCorrect = !w.reviewMode && state == LiveWordViewState.correct;

    // Red is reachable ONLY via [LiveWordViewState.mismatch], which
    // [resolveWordViewState] grants only behind the cursor.
    final Color ink = isMistake
        ? w.mushaf.mismatchInk
        : hidden
            // Transparent, not removed: the glyphs still take their space.
            ? w.mushaf.text.withValues(alpha: 0)
            : ghost
                ? w.mushaf.ghostInk
                : w.mushaf.text;
    final Color? wash = isActive
        ? w.mushaf.activeTint
        : (isCorrect ? w.mushaf.correctTint : null);

    final style = TextStyle(
      color: ink,
      background: wash == null ? null : (Paint()..color = wash),
      // Only a genuine mistake gets the red underline; the cursor gets a glow
      // instead, so "expected now" never reads as "you made a mistake".
      decoration: isMistake ? TextDecoration.underline : null,
      decorationColor:
          isMistake ? w.mushaf.mismatchInk.withValues(alpha: 0.9) : null,
      decorationThickness: isMistake ? 2.0 : null,
      // The glow traces the glyphs, so it is never drawn on a hidden word.
      shadows: isActive && !hidden
          ? [
              Shadow(
                  color: w.mushaf.accent.withValues(alpha: 0.55),
                  blurRadius: 12)
            ]
          : null,
    );

    GestureRecognizer? recognizer;
    final tap = w.onMistakeTap;
    if (tap != null && isMistake) {
      final r = TapGestureRecognizer()..onTap = () => tap(i);
      _recognizers.add(r);
      recognizer = r;
    }

    // Tajweed colours never leak through a mistake, a hidden (Hifz) word or a
    // ghosted (review, unreached) word.
    final tajweed = w.tajweedEnabled && i < w.tajweedSpans.length
        ? w.tajweedSpans[i]
        : null;
    if (isMistake || hidden || ghost || tajweed == null || tajweed.isEmpty) {
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }
    return TextSpan(
      style: style,
      recognizer: recognizer,
      children: _tajweedRuns(text, tajweed, brightness),
    );
  }

  /// Paints the word with each tajweed rule's colour on exactly the letters it
  /// covers (offsets are word-relative). Mirrors the Surah reader's per-letter
  /// tajweed rendering so the live canvas and the reader look identical.
  List<TextSpan> _tajweedRuns(
      String text, List<TajweedSpan> spans, Brightness brightness) {
    final ruleAt = List<String?>.filled(text.length, null);
    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      for (var i = start; i < end; i++) {
        ruleAt[i] = span.rule;
      }
    }
    final runs = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final rule = ruleAt[i];
      var j = i + 1;
      while (j < text.length && ruleAt[j] == rule) {
        j++;
      }
      runs.add(TextSpan(
        text: text.substring(i, j),
        style: rule == null
            ? null
            : TextStyle(
                color: AppTheme.ensureContrast(
                    AppTheme.getTajweedColor(rule), brightness)),
      ));
      i = j;
    }
    return runs;
  }
}

// ── Cursor anchor ────────────────────────────────────────────────────────

/// Lays out a paragraph and parks a zero-size [anchor] at the top-right of
/// the glyph box covering [anchorRange], measured from the paragraph itself.
/// Nothing is inserted into the text, so line breaking and justification are
/// untouched; the anchor only exists so an ancestor can `localToGlobal` it.
class _AnchoredParagraph extends MultiChildRenderObjectWidget {
  _AnchoredParagraph({
    required this.anchorRange,
    required Widget anchor,
    required Widget child,
  }) : super(children: [child, anchor]);

  final TextRange anchorRange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchoredParagraph(anchorRange);

  @override
  void updateRenderObject(
      BuildContext context, _RenderAnchoredParagraph renderObject) {
    renderObject.anchorRange = anchorRange;
  }
}

class _AnchorParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAnchoredParagraph extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AnchorParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AnchorParentData> {
  _RenderAnchoredParagraph(this._anchorRange);

  TextRange _anchorRange;
  TextRange get anchorRange => _anchorRange;
  set anchorRange(TextRange value) {
    if (value == _anchorRange) return;
    _anchorRange = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AnchorParentData) {
      child.parentData = _AnchorParentData();
    }
  }

  RenderBox get _text => firstChild!;
  RenderBox? get _anchor => childAfter(_text);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _text.getMinIntrinsicWidth(height);
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _text.getMaxIntrinsicWidth(height);
  @override
  double computeMinIntrinsicHeight(double width) =>
      _text.getMinIntrinsicHeight(width);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _text.getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _text.getDryLayout(constraints);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _text.getDistanceToActualBaseline(baseline);

  @override
  void performLayout() {
    final text = _text;
    text.layout(constraints, parentUsesSize: true);
    (text.parentData! as _AnchorParentData).offset = Offset.zero;
    size = text.size;

    final anchor = _anchor;
    if (anchor == null) return;
    anchor.layout(const BoxConstraints.tightFor(width: 0, height: 0));
    (anchor.parentData! as _AnchorParentData).offset = _anchorOffset(text);
  }

  Offset _anchorOffset(RenderBox text) {
    final paragraph = _findParagraph(text);
    if (paragraph == null ||
        !_anchorRange.isValid ||
        _anchorRange.isCollapsed) {
      return Offset.zero;
    }
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
          baseOffset: _anchorRange.start, extentOffset: _anchorRange.end),
      boxHeightStyle: ui.BoxHeightStyle.max,
    );
    if (boxes.isEmpty) return Offset.zero;
    // A word may yield several boxes (one per bidi run, e.g. a trailing
    // number). Take the ones on the first line the word occupies; in RTL the
    // word starts at their right edge.
    var top = boxes.first.top;
    for (final b in boxes) {
      if (b.top < top) top = b.top;
    }
    var right = double.negativeInfinity;
    for (final b in boxes) {
      if ((b.top - top).abs() < 0.5 && b.right > right) right = b.right;
    }
    final local = Offset(right, top);
    return MatrixUtils.transformPoint(paragraph.getTransformTo(this), local);
  }

  RenderParagraph? _findParagraph(RenderObject root) {
    if (root is RenderParagraph) return root;
    RenderParagraph? found;
    root.visitChildren((child) {
      found ??= _findParagraph(child);
    });
    return found;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}
