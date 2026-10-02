import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../mushaf/mushaf_theme.dart';
import '../word_view_state.dart';

/// A Madinah page rendered as independently fitted RTL lines.
/// Printed line metadata is independent of viewport size and live verdicts.
/// Each line scales its entire natural word row; separation comes only from
/// glyph side bearings plus a small font-derived inter-word gap.
class MushafRevealView extends StatefulWidget {
  /// Complete immutable page words, in recitation order.
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

  /// Printed row numbers, aligned with words and ayah boundaries respectively.
  /// Surah ranges may use absolute row numbers across multiple pages.
  final List<int> lineNumbers;
  final List<int> ayahLineNumbers;

  /// Number of printed slots. Opening pages use eight; regular pages use 15.
  final int lineCount;
  final bool centeredLines;

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

  /// Available paper height, divided into equal printed row slots.
  final double minimumHeight;

  /// Heights used for openings in the fallback layout without printed rows.
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
    this.lineNumbers = const [],
    this.ayahLineNumbers = const [],
    this.lineCount = 15,
    this.centeredLines = false,
    this.caretKey,
    this.cursorKey,
    this.reviewMode = false,
    this.onMistakeTap,
    this.hideUnspoken = false,
    this.blocksBefore = const {},
    this.minimumHeight = 0,
    this.blockHeights = const {},
  });

  /// Increase visible Arabic ink by 15% within the fixed printed row pitch.
  /// Changing fontSize alone is cancelled by the fitted line transform.
  static const double glyphScale = 1.15;
  static const double baseLineHeight = 1.55 / glyphScale;

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

class _LineUnit {
  const _LineUnit.word(this.index) : label = null;
  const _LineUnit.marker(this.index, this.label);
  final int index;
  final String? label;
}

class _MushafRevealViewState extends State<MushafRevealView> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TextStyle _baseStyle(double size) => AppTheme.arabicTextStyle(
        fontSize: size,
        color: widget.mushaf.text,
      ).copyWith(
        height: MushafRevealView.baseLineHeight,
        letterSpacing: 0,
        wordSpacing: 0,
        leadingDistribution: TextLeadingDistribution.even,
      );

  String _unitText(_LineUnit unit) => unit.label == null
      ? mushafDisplayText(widget.words[unit.index])
      : ayahMarkerText(unit.label!);

  double _advance(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  // A fraction of the font's natural space separates words without leaving
  // the large holes produced by paragraph justification. The complete row,
  // including this fixed advance, is transformed by the same FittedBox.
  double _wordGap(TextStyle style) =>
      _advance(String.fromCharCode(0x20), style) * 0.30;

  Map<int, List<_LineUnit>> _pageLines(double width, TextStyle style) {
    final w = widget;
    final canonical = w.lineNumbers.length == w.words.length &&
        w.lineNumbers.every((line) => line > 0);
    final rows = <int, List<_LineUnit>>{};
    final markers = <int, int>{
      for (var i = 0;
          i < w.ayahBoundaries.length && i < w.ayahLabels.length;
          i++)
        w.ayahBoundaries[i]: i,
    };
    var row = 1;
    var occupied = 0.0;
    final gap = _wordGap(style);
    for (var i = 0; i < w.words.length; i++) {
      final markerIndex = markers[i];
      if (canonical) {
        row = w.lineNumbers[i];
      } else {
        if (w.blocksBefore.containsKey(i) && occupied > 0) {
          row++;
          occupied = 0;
        }
        final advance = _advance(mushafDisplayText(w.words[i]), style) +
            (markerIndex == null
                ? 0
                : gap +
                    _advance(
                      ayahMarkerText(w.ayahLabels[markerIndex]),
                      style,
                    ));
        if (occupied > 0 && occupied + gap + advance > width) {
          row++;
          occupied = 0;
        }
        occupied += (occupied > 0 ? gap : 0) + advance;
      }
      rows.putIfAbsent(row, () => []).add(_LineUnit.word(i));
      if (markerIndex != null) {
        final markerRow = canonical && markerIndex < w.ayahLineNumbers.length
            ? w.ayahLineNumbers[markerIndex]
            : row;
        rows
            .putIfAbsent(markerRow, () => [])
            .add(_LineUnit.marker(i, w.ayahLabels[markerIndex]));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    if (w.words.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        _disposeRecognizers();
        final width = constraints.maxWidth;
        final style = _baseStyle(w.fontSize);
        final rows = _pageLines(width, style);
        final first = rows.keys.reduce((a, b) => a < b ? a : b);
        final last = rows.keys.reduce((a, b) => a > b ? a : b);
        final canonical = w.lineNumbers.length == w.words.length;
        final startRow = canonical && first <= w.lineCount ? 1 : first;
        final endRow = canonical && last <= w.lineCount ? w.lineCount : last;
        final count = endRow - startRow + 1;
        // Larger accessibility text grows the sheet and remains scrollable.
        final scale =
            MediaQuery.textScalerOf(context).scale(w.fontSize) / w.fontSize;
        final slotsPerSheet = count > w.lineCount ? w.lineCount : count;
        final pitch = w.minimumHeight > 0
            ? (w.minimumHeight / slotsPerSheet) * scale
            : w.fontSize * MushafRevealView.baseLineHeight * scale;
        final centeredWidth = w.centeredLines
            ? rows.values
                .map((units) =>
                    units.fold<double>(0,
                        (sum, unit) => sum + _advance(_unitText(unit), style)) +
                    (units.length - 1) * _wordGap(style))
                .reduce((a, b) => a > b ? a : b)
            : 0.0;
        final states = w.reviewMode
            ? [
                for (var i = 0; i < w.statuses.length; i++)
                  resolveReviewWordViewState(
                    serverStatus: w.statuses[i],
                    index: i,
                    reach: w.cursor,
                  ),
              ]
            : resolveWordViewStates(statuses: w.statuses, cursor: w.cursor);
        final brightness = w.mushaf.isDark ? Brightness.dark : Brightness.light;
        final openings = <int, (Widget, int)>{};
        for (final entry in w.blocksBefore.entries) {
          if (entry.key >= w.words.length) continue;
          final wordRow = canonical
              ? w.lineNumbers[entry.key]
              : rows.entries
                  .firstWhere(
                    (e) => e.value.any(
                      (unit) => unit.label == null && unit.index == entry.key,
                    ),
                  )
                  .key;
          var vacant = wordRow - 1;
          while (vacant >= startRow && !rows.containsKey(vacant)) {
            vacant--;
          }
          final slots = wordRow - vacant - 1;
          openings[slots > 0 ? vacant + 1 : wordRow] = (entry.value, slots);
        }
        final children = <Widget>[];
        for (var row = startRow; row <= endRow; row++) {
          final opening = openings[row];
          if (opening != null) {
            final (block, slots) = opening;
            children.add(
              SizedBox(
                height: slots > 0
                    ? pitch * slots
                    : (w.blockHeights[rows[row]?.first.index] ?? 80),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(width: width, child: block),
                ),
              ),
            );
            if (slots > 0) {
              row += slots - 1;
              continue;
            }
          }
          children.add(
            _buildMushafLine(
              row,
              rows[row] ?? const [],
              width,
              pitch,
              style,
              states,
              brightness,
              centeredWidth,
            ),
          );
        }
        final hasCursor = !w.reviewMode &&
            w.cursorKey != null &&
            w.cursor >= 0 &&
            w.cursor < w.words.length;
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
              if (w.caretKey != null && !hasCursor)
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: SizedBox(key: w.caretKey, width: 0, height: 0),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMushafLine(
    int row,
    List<_LineUnit> units,
    double width,
    double pitch,
    TextStyle style,
    List<LiveWordViewState> states,
    Brightness brightness,
    double centeredWidth,
  ) {
    if (units.isEmpty) {
      return SizedBox(
          key: ValueKey('mushaf-line-$row'),
          height: pitch,
          child: _lineRule(const SizedBox.expand()));
    }
    final w = widget;
    final children = <Widget>[];
    var naturalWidth = 0.0;
    final gap = _wordGap(style);
    for (var n = 0; n < units.length; n++) {
      final unit = units[n];
      if (n > 0) {
        children.add(SizedBox(width: gap));
        naturalWidth += gap;
      }
      final text = _unitText(unit);
      final advance = _advance(text, style);
      naturalWidth += advance;
      Widget word = RichText(
        key: ValueKey('mushaf-unit-${unit.index}-${unit.label ?? "word"}'),
        text: TextSpan(
          style: style,
          children: [
            unit.label != null
                ? TextSpan(
                    text: text,
                    style: TextStyle(
                        color:
                            w.mushaf.isDark ? w.mushaf.text : w.mushaf.accent),
                  )
                : _wordSpan(
                    unit.index,
                    unit.index < states.length
                        ? states[unit.index]
                        : LiveWordViewState.unspoken,
                    brightness,
                  ),
          ],
        ),
        textDirection: TextDirection.rtl,
        softWrap: false,
        maxLines: 1,
      );
      if (unit.label == null &&
          !w.reviewMode &&
          unit.index == w.cursor &&
          w.cursorKey != null) {
        word = _AnchoredParagraph(
          anchorRange: TextRange(start: 0, end: text.length),
          anchor: SizedBox(key: w.cursorKey, width: 0, height: 0),
          child: word,
        );
      }
      children.add(SizedBox(width: advance, child: word));
    }
    // BoxFit.fill makes the complete row flush horizontally, while its
    // natural height maps to the fixed line pitch. No word can wrap or detach
    // its harakat. FittedBox also transforms hit testing and cursor anchors.
    return SizedBox(
      key: ValueKey('mushaf-line-$row'),
      width: width,
      height: pitch,
      child: _lineRule(Center(
        child: SizedBox(
          width: width,
          // Opening pages keep their eight slots, but their ink has the same
          // height as ordinary pages. Every opening row shares one transform.
          height: w.centeredLines ? pitch * w.lineCount / 15 : pitch,
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: w.centeredLines ? centeredWidth : naturalWidth,
              height: w.fontSize * MushafRevealView.baseLineHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: w.centeredLines
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                textDirection: TextDirection.rtl,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: children,
              ),
            ),
          ),
        ),
      )),
    );
  }

  Widget _lineRule(Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: widget.mushaf.isDark
              ? Colors.black.withValues(alpha: .025)
              : null,
          border: Border(
            top: BorderSide(
              color: widget.mushaf.isDark
                  ? Colors.black.withValues(alpha: .30)
                  : Colors.transparent,
              width: .5,
            ),
            bottom: BorderSide(
              color: widget.mushaf.isDark
                  ? widget.mushaf.text.withValues(alpha: .04)
                  : Colors.transparent,
              width: .5,
            ),
          ),
        ),
        child: child,
      );

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
        ? (w.mushaf.isDark ? null : w.mushaf.activeTint)
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
                blurRadius: 12,
              ),
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

  Color _nightTajweedColor(String rule) => switch (rule) {
        'ghunnah' || 'qalaqah' => const Color(0xFF28B8D6),
        'ikhafa' || 'ikhafa_shafawi' => const Color(0xFFF063BD),
        'iqlab' => const Color(0xFFF4A45D),
        'idgham_ghunnah' ||
        'idgham_wo_ghunnah' ||
        'idgham_shafawi' ||
        'idgham_mutajanisayn' =>
          const Color(0xFFBE7AE6),
        'ham_wasl' => const Color(0xFFAEB8B8),
        'normal' => widget.mushaf.text,
        _ => const Color(0xFF40C98C),
      };

  /// Paints the word with each tajweed rule's colour on exactly the letters it
  /// covers (offsets are word-relative). Mirrors the Surah reader's per-letter
  /// tajweed rendering so the live canvas and the reader look identical.
  List<TextSpan> _tajweedRuns(
    String text,
    List<TajweedSpan> spans,
    Brightness brightness,
  ) {
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
      runs.add(
        TextSpan(
          text: text.substring(i, j),
          style: rule == null
              ? null
              : TextStyle(
                  color: brightness == Brightness.dark
                      ? _nightTajweedColor(rule)
                      : AppTheme.getTajweedColor(rule),
                ),
        ),
      );
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
    BuildContext context,
    _RenderAnchoredParagraph renderObject,
  ) {
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
        baseOffset: _anchorRange.start,
        extentOffset: _anchorRange.end,
      ),
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
