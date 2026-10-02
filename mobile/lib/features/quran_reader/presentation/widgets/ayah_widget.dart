import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/word_model.dart';
import '../../../../core/utils/arabic_text_utils.dart';

/// Ayah widget — displays an ayah with color-coded word-by-word tap targets,
/// density controls, and an action row (play, recite, context, share).
class AyahWidget extends StatelessWidget {
  final AyahModel ayah;
  final String languageCode;
  final String translationLanguageCode;
  final double arabicFontSize;
  final int densityLevel; // 0=Arabic only, 1=+translit, 2=+word meaning, 3=+full translation
  final bool grammarColorsEnabled;
  final bool tajweedColorsEnabled;
  final bool isPlaying;
  final void Function(WordModel word) onWordTapped;
  final VoidCallback onPlayTapped;
  final VoidCallback onReciteTapped;
  final VoidCallback onContextStoryTapped;
  final VoidCallback onShareTapped;
  final VoidCallback onSpeedTapped;

  const AyahWidget({
    super.key,
    required this.ayah,
    required this.languageCode,
    required this.translationLanguageCode,
    required this.arabicFontSize,
    required this.densityLevel,
    required this.grammarColorsEnabled,
    required this.tajweedColorsEnabled,
    required this.isPlaying,
    required this.onWordTapped,
    required this.onPlayTapped,
    required this.onReciteTapped,
    required this.onContextStoryTapped,
    required this.onShareTapped,
    required this.onSpeedTapped,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // NOTE: Do NOT wrap this in `.animate(target: isPlaying ? 1 : 0).fadeIn()`.
    // `fadeIn` begins at opacity 0, so any ayah that is *not* playing (i.e.
    // essentially all of them) would be rendered invisible — leaving the
    // reader showing only the header/settings bar with a blank ayah list.
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPlaying
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
        border: Border.all(
          color: isPlaying
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Ayah Number Badge ──────────────────────────────────────
          _AyahHeader(ayah: ayah, isPlaying: isPlaying, theme: theme),

          const SizedBox(height: 12),

          // ─── Arabic Word-by-Word Display ────────────────────────────
          _buildArabicWords(theme),

          // ─── Transliteration (density >= 1) ─────────────────────────
          if (densityLevel >= 1 && ayah.transliteration != null) ...[
            const SizedBox(height: 8),
            _buildTransliteration(theme),
          ],

          // ─── Word-by-word meanings (density >= 2) ───────────────────
          if (densityLevel >= 2 && ayah.words.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildWordMeanings(theme),
          ],

          // ─── Full Translation (density >= 3) ────────────────────────
          if (densityLevel >= 3) ...[
            const SizedBox(height: 8),
            _buildTranslation(theme),
          ],

          const SizedBox(height: 12),

          // ─── Action Row ─────────────────────────────────────────────
          _AyahActionRow(
            isPlaying: isPlaying,
            onPlay: onPlayTapped,
            onRecite: onReciteTapped,
            onContextStory: onContextStoryTapped,
            onShare: onShareTapped,
            onSpeed: onSpeedTapped,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildArabicWords(ThemeData theme) {
    if (ayah.words.isEmpty) {
      // Fallback: show full ayah text without word tap targets
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Text(
          ayah.ayahText,
          style: AppTheme.arabicTextStyle(
            fontSize: arabicFontSize,
            color: theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.start,
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 8,
        children: ayah.words.map((word) {
          return _WordTapTarget(
            word: word,
            fontSize: arabicFontSize,
            grammarColorsEnabled: grammarColorsEnabled,
            tajweedColorsEnabled: tajweedColorsEnabled,
            onTap: () => onWordTapped(word),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTransliteration(ThemeData theme) {
    return Text(
      ayah.transliteration!,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildWordMeanings(ThemeData theme) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4,
        runSpacing: 4,
        children: ayah.words.map((word) {
          final meaning = word.translationFor(languageCode) ?? '';
          if (meaning.isEmpty) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              meaning,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textDirection: TextDirection.ltr,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTranslation(ThemeData theme) {
    final translation = ayah.translationFor(translationLanguageCode);
    if (translation == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        translation,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        textAlign: TextAlign.start,
        textDirection: ArabicTextUtils.getDirection(translation),
      ),
    );
  }
}

/// Ayah header with number badge.
class _AyahHeader extends StatelessWidget {
  final AyahModel ayah;
  final bool isPlaying;
  final ThemeData theme;

  const _AyahHeader({required this.ayah, required this.isPlaying, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Ayah number in decorative circle
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              ArabicTextUtils.toWesternNumerals(ayah.ayahNumber.toString()),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (ayah.sajda)
          Icon(Icons.arrow_downward_rounded, size: 18, color: theme.colorScheme.secondary),
        const Spacer(),
        if (isPlaying)
          Icon(Icons.volume_up_rounded, size: 18, color: theme.colorScheme.primary)
              .animate(onComplete: (c) => c.repeat())
              .fadeIn(duration: 500.ms)
              .then()
              .fadeOut(duration: 500.ms),
      ],
    );
  }
}

/// Ayah action row — play, recite, context story, share.
class _AyahActionRow extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onRecite;
  final VoidCallback onContextStory;
  final VoidCallback onShare;
  final VoidCallback onSpeed;
  final ThemeData theme;

  const _AyahActionRow({
    required this.isPlaying,
    required this.onPlay,
    required this.onRecite,
    required this.onContextStory,
    required this.onShare,
    required this.onSpeed,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ActionButton(
          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: isPlaying ? 'Pause' : 'Play',
          color: theme.colorScheme.primary,
          onTap: onPlay,
        ),
        _ActionButton(
          icon: Icons.speed_rounded,
          label: 'Speed',
          onTap: onSpeed,
        ),
        _ActionButton(
          icon: Icons.mic_rounded,
          label: 'Recite',
          color: theme.colorScheme.secondary,
          onTap: onRecite,
        ),
        _ActionButton(
          icon: Icons.menu_book_rounded,
          label: 'Context',
          onTap: onContextStory,
        ),
        _ActionButton(
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: onShare,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: c),
            ),
          ],
        ),
      ),
    );
  }
}

/// Individual word tap target with grammar/tajweed color-coding.
class _WordTapTarget extends StatelessWidget {
  final WordModel word;
  final double fontSize;
  final bool grammarColorsEnabled;
  final bool tajweedColorsEnabled;
  final VoidCallback onTap;

  const _WordTapTarget({
    required this.word,
    required this.fontSize,
    required this.grammarColorsEnabled,
    required this.tajweedColorsEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    // Tajweed: colour each letter range by its rule span (per-character),
    // so e.g. only the noon of ikhfa or the madd letter turns the rule colour
    // while the rest of the word stays the default ink colour.
    if (tajweedColorsEnabled &&
        word.tajweedSpans != null &&
        word.tajweedSpans!.isNotEmpty) {
      return GestureDetector(
        onTap: () async {
          await Haptics.vibrate(HapticsType.selection);
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text.rich(
            _buildTajweedTextSpan(brightness),
            style: AppTheme.arabicTextStyle(fontSize: fontSize),
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }

    Color? textColor;
    TextDecoration decoration = TextDecoration.none;
    Color? decorationColor;
    TextDecorationStyle decorationStyle = TextDecorationStyle.solid;

    if (grammarColorsEnabled) {
      final config = AppTheme.getGrammarConfig(word.posGroup ?? 'default');
      textColor = AppTheme.ensureContrast(config.color, brightness);
      decoration = AppTheme.toTextDecoration(config.underlineStyle);
      decorationColor = textColor;
      decorationStyle = config.underlineStyle == UnderlineStyle.dotted
          ? TextDecorationStyle.dotted
          : TextDecorationStyle.solid;
    }

    return GestureDetector(
      onTap: () async {
        await Haptics.vibrate(HapticsType.selection);
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text(
          word.text,
          style: AppTheme.arabicTextStyle(
            fontSize: fontSize,
            color: textColor,
            decoration: decoration,
            decorationColor: decorationColor,
            decorationStyle: decorationStyle,
          ),
        ),
      ),
    );
  }

  /// Builds a [TextSpan] tree that paints the word with each tajweed rule's
  /// colour on exactly the letters it covers (offsets are word-relative).
  TextSpan _buildTajweedTextSpan(Brightness brightness) {
    final text = word.text;
    final spans = word.tajweedSpans!;

    // Resolve the active rule for every character index of the word.
    final ruleAt = List<String?>.filled(text.length, null);
    for (final span in spans) {
      final start = span.start.clamp(0, text.length);
      final end = span.end.clamp(0, text.length);
      for (int i = start; i < end && i < text.length; i++) {
        ruleAt[i] = span.rule;
      }
    }

    // Group consecutive characters sharing the same rule into one span.
    final children = <TextSpan>[];
    int i = 0;
    while (i < text.length) {
      final rule = ruleAt[i];
      int j = i + 1;
      while (j < text.length && ruleAt[j] == rule) {
        j++;
      }
      final color = rule == null
          ? null
          : AppTheme.ensureContrast(AppTheme.getTajweedColor(rule), brightness);
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
