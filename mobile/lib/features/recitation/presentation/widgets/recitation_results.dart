import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/recitation_model.dart';

/// Recitation results widget — shows score header, word-by-word display
/// with green/red tinting, and feedback. Red words are tappable.
class RecitationResults extends StatelessWidget {
  final RecitationResult result;
  final List<String> ayahWords;
  final void Function(WordVerdict verdict) onWordTapped;
  final VoidCallback onRetry;
  final ThemeData theme;

  const RecitationResults({
    super.key,
    required this.result,
    this.ayahWords = const [],
    required this.onWordTapped,
    required this.onRetry,
    required this.theme,
  });

  bool get _isNoSpeech =>
      result.wordVerdicts.length == 1 &&
      result.wordVerdicts.first.errorType == 'no_speech';

  @override
  Widget build(BuildContext context) {
    if (_isNoSpeech) {
      return _NoSpeechResult(
        result: result,
        onRetry: onRetry,
        theme: theme,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ScoreHeader(result: result, theme: theme)
              .animate()
              .fadeIn(duration: 400.ms)
              .slideY(begin: 0.05, end: 0),
          const SizedBox(height: 20),
          _SubScores(result: result, theme: theme)
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms),
          const SizedBox(height: 24),
          Text(
            'Word by Word',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _WordByWordDisplay(
            result: result,
            ayahWords: ayahWords,
            onWordTapped: onWordTapped,
            theme: theme,
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
          const SizedBox(height: 20),
          if (result.feedback != null)
            _FeedbackCard(
              feedback: result.feedback!,
              theme: theme,
            ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Try Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ],
          ).animate().fadeIn(delay: 800.ms, duration: 400.ms),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _NoSpeechResult extends StatelessWidget {
  final RecitationResult result;
  final VoidCallback onRetry;
  final ThemeData theme;

  const _NoSpeechResult({
    required this.result,
    required this.onRetry,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 52),
          Icon(
            Icons.mic_off_rounded,
            size: 88,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'No Recitation Detected',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            result.feedback ??
                'Move closer to the microphone and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Recorded duration: ${result.durationSeconds}s',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 36),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms);
  }
}

class _ScoreHeader extends StatelessWidget {
  final RecitationResult result;
  final ThemeData theme;

  const _ScoreHeader({required this.result, required this.theme});

  @override
  Widget build(BuildContext context) {
    final scoreColor = _scoreColor(result.overallScore);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scoreColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scoreColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: result.overallScore,
                  strokeWidth: 8,
                  backgroundColor: scoreColor.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(scoreColor),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${(result.overallScore * 100).toInt()}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scoreColor,
                      ),
                    ),
                    Text(
                      '/ 100',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.gradeLabel,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scoreColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${result.correctCount} of ${result.wordVerdicts.length} words correct',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration: ${result.durationSeconds}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 0.9) return Colors.green;
    if (score >= 0.75) return Colors.lightGreen;
    if (score >= 0.6) return Colors.orange;
    return Colors.red;
  }
}

class _SubScores extends StatelessWidget {
  final RecitationResult result;
  final ThemeData theme;

  const _SubScores({required this.result, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SubScoreCard(
            label: 'Pronunciation',
            score: result.pronunciationScore,
            theme: theme,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SubScoreCard(
            label: 'Tajweed',
            score: result.tajweedScore,
            theme: theme,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SubScoreCard(
            label: 'Fluency',
            score: result.fluencyScore,
            theme: theme,
          ),
        ),
      ],
    );
  }
}

class _SubScoreCard extends StatelessWidget {
  final String label;
  final double score;
  final ThemeData theme;

  const _SubScoreCard({
    required this.label,
    required this.score,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '${(score * 100).toInt()}%',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean, continuous Mushaf flow for the results screen.
///
/// Deliberately NOT a grid of red/green cards: the reciter reads their result as
/// ordinary Mushaf text, and only words with a VERIFIED mistake carry a red
/// underline. Correct words are plain book ink — no green wash — so the page
/// still looks like a Mushaf rather than a dashboard.
class _WordByWordDisplay extends StatelessWidget {
  final RecitationResult result;
  final List<String> ayahWords;
  final void Function(WordVerdict verdict) onWordTapped;
  final ThemeData theme;

  const _WordByWordDisplay({
    required this.result,
    required this.ayahWords,
    required this.onWordTapped,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Index the verdicts by their word position so the flow can look up "is
    // this word wrong?" without assuming the two lists are the same length.
    final mistakes = <int, WordVerdict>{};
    for (final v in result.wordVerdicts) {
      if (!v.isCorrect && v.wordIndex >= 0) mistakes[v.wordIndex] = v;
    }

    // Prefer the canonical Quranic text (which carries full tashkeel) over the
    // verdict's own `word` field, which may be the normalized ASR key.
    final words = ayahWords.isNotEmpty
        ? ayahWords
        : result.wordVerdicts.map((v) => v.displayWord(ayahWords)).toList();

    final mistakeColor = theme.colorScheme.error;
    final ink = theme.brightness == Brightness.dark
        ? const Color(0xFFE8E2D4)
        : const Color(0xFF1A1A1A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Wrap(
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 12,
          children: [
            for (var i = 0; i < words.length; i++)
              _ResultWord(
                text: words[i],
                mistake: mistakes[i],
                ink: ink,
                mistakeColor: mistakeColor,
                fontSize: 26,
                onTap: mistakes[i] == null
                    ? null
                    : () async {
                        await Haptics.vibrate(HapticsType.medium);
                        onWordTapped(mistakes[i]!);
                      },
              ),
          ],
        ),
      ),
    );
  }
}

/// One word in the results flow. Mistaken words get a red underline and stay
/// tappable so the user can open the per-word audio breakdown; everything else
/// is plain book ink.
class _ResultWord extends StatelessWidget {
  final String text;
  final WordVerdict? mistake;
  final Color ink;
  final Color mistakeColor;
  final double fontSize;
  final VoidCallback? onTap;

  const _ResultWord({
    required this.text,
    required this.mistake,
    required this.ink,
    required this.mistakeColor,
    required this.fontSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMistake = mistake != null;
    final word = Text(
      text,
      style: AppTheme.arabicTextStyle(
        fontSize: fontSize,
        color: isMistake ? mistakeColor : ink,
        // A clean red underline reads as a correction mark; a squiggle would
        // look like a spell-checker error in a book of scripture.
        decoration: isMistake ? TextDecoration.underline : TextDecoration.none,
        decorationColor: mistakeColor,
        decorationThickness: 2,
      ),
    );

    final content =
        Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: word);
    if (!isMistake) return content;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          color: mistakeColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String feedback;
  final ThemeData theme;

  const _FeedbackCard({required this.feedback, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_rounded, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Feedback',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feedback,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}