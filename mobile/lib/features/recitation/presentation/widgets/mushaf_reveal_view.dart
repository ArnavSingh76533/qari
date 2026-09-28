import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_stream_event.dart';
import '../../../../data/models/word_model.dart';
import '../mushaf/mushaf_theme.dart';
import '../word_view_state.dart';

/// A continuous, book-like (Mushaf) render of the recitation as it is revealed
/// in real time.
///
/// Unlike the old per-word grid, this view never shows placeholder dots or
/// empty boxes. It starts as a **completely blank canvas** and, as the live
/// engine confirms words, the caller appends them to [words]. The view lays
/// them out as one uninterrupted RTL paragraph that wraps line-by-line exactly
/// like a printed Quran — no artificial per-ayah containers or breaks.
///
/// When an ayah is completed (i.e. when a revealed word is the last word of an
/// ayah) the standard inline ayah marker (۝ + the verse number) is rendered
/// directly in the flow at that point, just like a real Mushaf.
///
/// A stable [caretKey] is attached to a zero-width anchor at the very end of
/// the flow, so the parent page can measure the latest revealed word's
/// position and auto-scroll it back into the upper half of the viewport.
class MushafRevealView extends StatelessWidget {
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

  /// 0-based indices (into [words]) of the LAST word of each ayah. When a word
  /// at position `i` is revealed and `i - 1` is in this list, an inline ayah
  /// marker is rendered right before word `i`.
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
  });

  String? _labelForBoundary(int wordIndex) {
    if (ayahBoundaries.isEmpty || ayahLabels.isEmpty) return null;
    final pos = ayahBoundaries.indexOf(wordIndex);
    return pos >= 0 && pos < ayahLabels.length ? ayahLabels[pos] : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A single RTL Wrap flowing right→left, wrapping line-by-line like a book.
    // Appending a word only adds one child, so this rebuilds cheaply even for
    // a full surah (hundreds of words) at human recitation cadence.
    //
    // Every word's final look is decided by [resolveWordViewState], never by
    // [LiveWordStatus] alone — that is what guarantees a word ahead of the
    // cursor can never be painted as a mistake.
    final viewStates = reviewMode
        ? <LiveWordViewState>[
            for (var i = 0; i < statuses.length; i++)
              resolveReviewWordViewState(
                serverStatus: statuses[i],
                index: i,
                reach: cursor,
              ),
          ]
        : resolveWordViewStates(statuses: statuses, cursor: cursor);
    final children = <Widget>[];
    for (var i = 0; i < words.length; i++) {
      // Attach the scroll anchor to the word at the recitation CURSOR, not to
      // the end of the flow. The page is pre-rendered in full, so an anchor
      // parked after the last word would sit at the bottom of the whole surah
      // and yank the viewport there on the first word event.
      final isCursor = !reviewMode && i == cursor;
      final viewState =
          i < viewStates.length ? viewStates[i] : LiveWordViewState.unspoken;
      final tap = onMistakeTap;
      Widget word = _RevealedWord(
          key: isCursor ? cursorKey : null,
          text: words[i],
          viewState: viewState,
          reviewMode: reviewMode,
          tajweedSpans: (tajweedEnabled && i < tajweedSpans.length)
              ? tajweedSpans[i]
              : null,
          fontSize: fontSize,
          theme: theme,
          mushaf: mushaf,
        );
      if (tap != null && viewState == LiveWordViewState.mismatch) {
        word = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => tap(i),
          child: word,
        );
      }
      children.add(word);
      // Inline ayah marker directly AFTER the last word of that ayah, so it sits
      // inside the paragraph flow exactly like a printed Mushaf. (It used to be
      // emitted BEFORE the next word, which could not attach to the word it
      // belongs to and left a stray gap at line boundaries.)
      final boundaryLabel = _labelForBoundary(i);
      if (boundaryLabel != null) {
        children.add(_AyahMarker(
          label: boundaryLabel,
          theme: theme,
          mushaf: mushaf,
          fontSize: fontSize,
        ));
      }
    }
    // Trailing anchor, used only when nothing is active yet (cursor is -1, i.e.
    // before recitation starts) so the first layout has something measurable.
    if (cursorKey == null || cursor < 0 || cursor >= words.length) {
      children.add(
        SizedBox(key: caretKey, width: 0, height: fontSize),
      );
    }

    // Natural word spacing (WrapAlignment.start), NOT justified.
    //
    // Justified Mushaf typesetting stretches every line to the full measure.
    // On a LIVE page the newest word lands on the final line, so justification
    // would re-space that line on every single event — words visibly shuffle
    // several times per second while reciting, which is both unreadable and a
    // relayout of the whole page on each frame. Natural spacing keeps the
    // reading position stable; a printed-page justification pass can be added
    // later for the non-live reader if the visual gain is judged worth it.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        direction: Axis.horizontal,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 6,
        children: children,
      ),
    );
  }
}

/// A single revealed Arabic word in the continuous book flow.
class _RevealedWord extends StatelessWidget {
  final String text;
  final LiveWordViewState viewState;
  final bool reviewMode;
  final List<TajweedSpan>? tajweedSpans;
  final double fontSize;
  final ThemeData theme;
  final MushafTheme mushaf;

  const _RevealedWord({
    super.key,
    required this.text,
    required this.viewState,
    this.reviewMode = false,
    this.tajweedSpans,
    required this.fontSize,
    required this.theme,
    required this.mushaf,
  });

  /// A word is "mistaken" when the resolved VIEW state says so.
  /// Mistakes always override tajweed colouring so the user sees the error.
  bool get _isMistake => viewState == LiveWordViewState.mismatch;

  /// The listening cursor — highlighted, but deliberately NOT a colour verdict.
  bool get _isActive => viewState == LiveWordViewState.active;

  /// Not yet said: faint ghost ink, so the pre-rendered page never reads as
  /// "already recognised" before the reciter speaks.
  bool get _isUnspoken => viewState == LiveWordViewState.unspoken;

  Color get _ink {
    // Red is reachable ONLY via [LiveWordViewState.mismatch], which
    // [resolveWordViewState] grants only at/behind the cursor.
    if (_isMistake) return mushaf.mismatchInk;
    if (_isUnspoken) return mushaf.ghostInk;
    // correct / active: crisp, solid book ink (never red, never amber).
    return mushaf.text;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = theme.brightness;
    // Tajweed colours only ever appear on a word that has been said — an
    // unspoken word stays uniformly ghosted.
    final canColorTajweed = !_isMistake &&
        !_isUnspoken &&
        tajweedSpans != null &&
        tajweedSpans!.isNotEmpty;

    // Per-state treatment, exactly per the Mushaf word-state spec:
    //   unspoken  -> no decoration, faint ghost ink
    //   active    -> soft background wash (golden glow cursor)
    //   correct   -> solid ink + soft green background tint (live only; the
    //                review page keeps correct words plain)
    //   mismatch  -> red ink + a red underline
    final isCorrect =
        !reviewMode && viewState == LiveWordViewState.correct;
    final Color? wash = _isActive
        ? mushaf.activeTint
        : (isCorrect ? mushaf.correctTint : null);
    // Only a genuine mistake gets a red underline. The active cursor gets a
    // halo instead of an underline so the listening word is unmistakable
    // without borrowing the visual language of an error.
    final bool underline = _isMistake;

    final content = canColorTajweed
        ? Text.rich(
            _buildTajweedSpan(brightness),
            textAlign: TextAlign.right,
          )
        : Text(
            text,
            style: AppTheme.arabicTextStyle(fontSize: fontSize, color: _ink),
            textAlign: TextAlign.right,
          );

    final word = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
      child: content,
    );

    if (wash == null && !underline && !_isActive) return word;
    return Container(
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(6),
        // Golden halo on the listening cursor — a soft glow rather than an
        // underline, so "currently expected" never reads as "you made a mistake".
        boxShadow: _isActive
            ? [
                BoxShadow(
                  color: mushaf.accent.withValues(alpha: 0.45),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
        border: underline
            ? Border(
                bottom: BorderSide(
                  color: mushaf.mismatchInk.withValues(alpha: 0.9),
                  width: 2.0,
                ),
              )
            : null,
      ),
      child: word,
    );
  }

  /// Paints the word with each tajweed rule's colour on exactly the letters it
  /// covers (offsets are word-relative, matching [text]). Mirrors the Surah
  /// reader's per-letter tajweed rendering so the live canvas and the reader
  /// look identical.
  TextSpan _buildTajweedSpan(Brightness brightness) {
    final spans = tajweedSpans!;
    final ruleAt = List<String?>.filled(text.length, null);
    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      for (var i = start; i < end && i < text.length; i++) {
        ruleAt[i] = span.rule;
      }
    }

    final children = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final rule = ruleAt[i];
      var j = i + 1;
      while (j < text.length && ruleAt[j] == rule) j++;
      final color = rule == null
          ? null
          : AppTheme.ensureContrast(
              AppTheme.getTajweedColor(rule), brightness);
      children.add(
        TextSpan(
          text: text.substring(i, j),
          style: AppTheme.arabicTextStyle(fontSize: fontSize, color: color),
        ),
      );
      i = j;
    }
    return TextSpan(children: children);
  }
}

/// Inline end-of-ayah marker (۝ + verse number), rendered directly in the
/// reading flow — exactly like a printed Mushaf. Uses the theme accent so it
/// blends into the paper rather than shouting over the text.
class _AyahMarker extends StatelessWidget {
  final String label;
  final ThemeData theme;
  final MushafTheme mushaf;
  final double fontSize;

  const _AyahMarker({
    required this.label,
    required this.theme,
    required this.mushaf,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final size = (fontSize * 0.86).clamp(18.0, 34.0);
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: mushaf.accent.withValues(alpha: 0.75),
          width: 1.4,
        ),
      ),
      child: Center(
        child: Text(
          // ۝ (Arabic end-of-ayah) followed by the verse number.
          '۝$label',
          style: theme.textTheme.labelSmall?.copyWith(
            color: mushaf.accent,
            fontWeight: FontWeight.w700,
            height: 1.0,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}
