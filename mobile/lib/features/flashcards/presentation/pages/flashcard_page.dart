import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/flashcard_model.dart';
import '../../../../data/services/audio_service.dart';
import '../../../../data/repositories/flashcard_repository.dart';

/// S9: Flashcards — full-screen card Arabic front -> tap -> meaning+translit+
/// audio+source ayah, grade buttons (Bhool gaya/Mushkil/Aasaan = SM-2 grades
/// 1/3/5), session cap 20, end screen with next-due summary.
class FlashcardPage extends ConsumerStatefulWidget {
  const FlashcardPage({super.key});

  @override
  ConsumerState<FlashcardPage> createState() => _FlashcardPageState();
}

class _FlashcardPageState extends ConsumerState<FlashcardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFlipped = false;

  final List<FlashcardModel> _cards = _sampleCards;
  int _currentIndex = 0;
  int _againCount = 0;
  int _hardCount = 0;
  int _easyCount = 0;
  bool _sessionComplete = false;
  final AudioService _audioService = AudioService();
  final FlashcardRepository _repo = FlashcardRepository();

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    _audioService.dispose();
    super.dispose();
  }

  void _flipCard() async {
    await Haptics.vibrate(HapticsType.medium);
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  Future<void> _gradeCard(int grade) async {
    await Haptics.vibrate(HapticsType.medium);

    // Record grade
    switch (grade) {
      case AppConstants.sm2GradeBhoolGaya:
        _againCount++;
        break;
      case AppConstants.sm2GradeMushkil:
        _hardCount++;
        break;
      case AppConstants.sm2GradeAasaan:
        _easyCount++;
        break;
    }

    // Submit to API (non-blocking)
    _repo.reviewCard(cardId: _cards[_currentIndex].cardId, grade: grade).catchError((_) {});

    // Next card
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
      });
      _flipController.reset();
    } else {
      setState(() => _sessionComplete = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_sessionComplete) {
      return _SessionCompleteScreen(
        total: _cards.length,
        again: _againCount,
        hard: _hardCount,
        easy: _easyCount,
        onDone: () => Navigator.of(context).pop(),
        theme: theme,
      );
    }

    final card = _cards[_currentIndex];
    final progress = (_currentIndex + 1) / _cards.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ─── Progress Header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentIndex + 1} / ${_cards.length}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // ─── Flashcard ────────────────────────────────────────────
            Expanded(
              child: GestureDetector(
                onTap: _flipCard,
                child: AnimatedBuilder(
                  animation: _flipAnimation,
                  builder: (context, child) {
                    final angle = _flipAnimation.value * math.pi;
                    final showFront = _flipAnimation.value < 0.5;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      child: showFront
                          ? _FlashcardFront(card: card, theme: theme)
                          : Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()..rotateY(math.pi),
                              child: _FlashcardBack(
                                card: card,
                                theme: theme,
                                audioService: _audioService,
                              ),
                            ),
                    );
                  },
                ),
              ),
            ),

            // ─── Grade Buttons (only when flipped) ────────────────────
            if (_isFlipped)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _GradeButton(
                        label: 'Bhool gaya',
                        sublabel: 'Again',
                        color: Colors.red,
                        onTap: () => _gradeCard(AppConstants.sm2GradeBhoolGaya),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GradeButton(
                        label: 'Mushkil',
                        sublabel: 'Hard',
                        color: Colors.orange,
                        onTap: () => _gradeCard(AppConstants.sm2GradeMushkil),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GradeButton(
                        label: 'Aasaan',
                        sublabel: 'Easy',
                        color: Colors.green,
                        onTap: () => _gradeCard(AppConstants.sm2GradeAasaan),
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .slideY(begin: 0.1, end: 0),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Tap card to reveal',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                )
                    .animate(onComplete: (c) => c.repeat())
                    .fadeIn(duration: 800.ms)
                    .then()
                    .fadeOut(duration: 800.ms),
              ),
          ],
        ),
      ),
    );
  }
}

/// Flashcard front — Arabic word only.
class _FlashcardFront extends StatelessWidget {
  final FlashcardModel card;
  final ThemeData theme;

  const _FlashcardFront({required this.card, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // POS badge
            if (card.posGroup != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.getGrammarColor(card.posGroup!).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  AppTheme.getGrammarConfig(card.posGroup!).label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getGrammarColor(card.posGroup!),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            // Arabic word
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                card.wordText,
                style: AppTheme.arabicTextStyle(
                  fontSize: 40,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Root (if available)
            if (card.rootArabic != null)
              Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'Root: ${card.rootArabic}',
                  style: AppTheme.arabicTextStyle(
                    fontSize: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Flashcard back — meaning, transliteration, audio, source ayah.
class _FlashcardBack extends StatelessWidget {
  final FlashcardModel card;
  final ThemeData theme;
  final AudioService audioService;

  const _FlashcardBack({
    required this.card,
    required this.theme,
    required this.audioService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Arabic word (smaller)
          Center(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                card.wordText,
                style: AppTheme.arabicTextStyle(
                  fontSize: 28,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Transliteration
          if (card.transliteration != null)
            _BackRow(label: 'Transliteration', value: card.transliteration!, theme: theme),
          const SizedBox(height: 12),

          // Meaning
          _BackRow(
            label: 'Meaning',
            value: card.meaningEn ?? '—',
            theme: theme,
          ),
          const SizedBox(height: 12),

          // Source ayah
          if (card.ayahText != null) ...[
            _BackRow(
              label: 'Source',
              value: 'Surah ${card.surahNumber}:${card.ayahNumber}',
              theme: theme,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  card.ayahText!,
                  style: AppTheme.arabicTextStyle(
                    fontSize: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Audio button
          if (card.audioUrl != null)
            Center(
              child: IconButton.filled(
                onPressed: () => audioService.playUrl(card.audioUrl!),
                icon: const Icon(Icons.volume_up_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _BackRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _BackRow({required this.label, required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Grade button.
class _GradeButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const _GradeButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Session complete screen.
class _SessionCompleteScreen extends StatelessWidget {
  final int total;
  final int again;
  final int hard;
  final int easy;
  final VoidCallback onDone;
  final ThemeData theme;

  const _SessionCompleteScreen({
    required this.total,
    required this.again,
    required this.hard,
    required this.easy,
    required this.onDone,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, size: 80, color: theme.colorScheme.primary)
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 24),
            Text(
              'Session Complete!',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            )
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              'You reviewed $total cards',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 32),
            // Grade breakdown
            _GradeBreakdown(again: again, hard: hard, easy: easy, theme: theme)
                .animate()
                .fadeIn(delay: 500.ms, duration: 400.ms),
            const SizedBox(height: 32),
            // Next due summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.schedule_rounded, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Next review: Tomorrow',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .fadeIn(delay: 700.ms, duration: 400.ms),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Done'),
            )
                .animate()
                .fadeIn(delay: 900.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

class _GradeBreakdown extends StatelessWidget {
  final int again;
  final int hard;
  final int easy;
  final ThemeData theme;

  const _GradeBreakdown({
    required this.again,
    required this.hard,
    required this.easy,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _StatColumn(label: 'Again', count: again, color: Colors.red, theme: theme),
        _StatColumn(label: 'Hard', count: hard, color: Colors.orange, theme: theme),
        _StatColumn(label: 'Easy', count: easy, color: Colors.green, theme: theme),
      ],
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final ThemeData theme;

  const _StatColumn({
    required this.label,
    required this.count,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

// ─── Sample Flashcards ─────────────────────────────────────────────────────

final _sampleCards = <FlashcardModel>[
  FlashcardModel(
    cardId: 1,
    wordId: 1,
    surahNumber: 1,
    ayahNumber: 1,
    wordText: 'بِسْمِ',
    transliteration: 'bismi',
    meaningEn: 'In the name',
    meaningUr: 'نام کے ساتھ',
    rootArabic: 'سم',
    posGroup: 'harf_jarr',
    ayahText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    ayahTranslation: 'In the name of Allah, the Most Gracious, the Most Merciful',
    nextReview: DateTime.now().add(const Duration(days: 1)),
    createdAt: DateTime.now(),
  ),
  FlashcardModel(
    cardId: 2,
    wordId: 2,
    surahNumber: 1,
    ayahNumber: 1,
    wordText: 'ٱللَّهِ',
    transliteration: 'Allāhi',
    meaningEn: 'of Allah',
    meaningUr: 'اللہ',
    rootArabic: 'اله',
    posGroup: 'ism',
    ayahText: 'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
    ayahTranslation: 'In the name of Allah, the Most Gracious, the Most Merciful',
    nextReview: DateTime.now().add(const Duration(days: 1)),
    createdAt: DateTime.now(),
  ),
  FlashcardModel(
    cardId: 3,
    wordId: 15,
    surahNumber: 1,
    ayahNumber: 5,
    wordText: 'نَعْبُدُ',
    transliteration: 'naʿbudu',
    meaningEn: 'we worship',
    meaningUr: 'ہم عبادت کرتے ہیں',
    rootArabic: 'عبد',
    posGroup: 'fiil_mudari',
    ayahText: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
    ayahTranslation: 'You alone we worship, and You alone we ask for help',
    nextReview: DateTime.now().add(const Duration(days: 1)),
    createdAt: DateTime.now(),
  ),
  FlashcardModel(
    cardId: 4,
    wordId: 11,
    surahNumber: 1,
    ayahNumber: 4,
    wordText: 'مَٰلِكِ',
    transliteration: 'māliki',
    meaningEn: 'Master/King',
    meaningUr: 'مالک',
    rootArabic: 'ملك',
    posGroup: 'ism',
    ayahText: 'مَٰلِكِ يَوْمِ ٱلدِّينِ',
    ayahTranslation: 'Master of the Day of Judgment',
    nextReview: DateTime.now().add(const Duration(days: 1)),
    createdAt: DateTime.now(),
  ),
  FlashcardModel(
    cardId: 5,
    wordId: 18,
    surahNumber: 1,
    ayahNumber: 5,
    wordText: 'نَسْتَعِينُ',
    transliteration: 'nastaʿīnu',
    meaningEn: 'we seek help',
    meaningUr: 'ہم مدد مانگتے ہیں',
    rootArabic: 'عون',
    posGroup: 'fiil_mudari',
    ayahText: 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ',
    ayahTranslation: 'You alone we worship, and You alone we ask for help',
    nextReview: DateTime.now().add(const Duration(days: 1)),
    createdAt: DateTime.now(),
  ),
];
