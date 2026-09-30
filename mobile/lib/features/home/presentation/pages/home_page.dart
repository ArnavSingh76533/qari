import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../data/services/local_storage_service.dart';
import '../../../../data/services/curriculum_service.dart';
import '../../../../data/repositories/user_repository.dart';
import '../../../../data/models/user_model.dart';
import '../../../../data/models/lesson_model.dart';
import '../../../quran_reader/presentation/pages/surah_list_page.dart';
import '../../../recitation/presentation/pages/live_recitation_page.dart';
import '../../../recitation/presentation/recitation_mode.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../lessons/presentation/pages/lesson_player_page.dart';
import '../../../lessons/presentation/pages/lesson_list_page.dart';
import '../widgets/streak_card.dart';
import '../widgets/continue_card.dart';
import '../widgets/daily_goal_ring.dart';
import '../widgets/learning_path_map.dart';
import '../../../flashcards/presentation/pages/flashcard_page.dart';
import '../../../tasbih/presentation/pages/tasbih_page.dart';
import '../../../../core/theme/serene_decorations.dart';

/// S3: Home screen with bottom nav (Home, Quran, Tilawat, Tasbih + the
/// centre Practice FAB). Tilawat pushes the full-screen Mushaf.
/// Home tab shows streak, XP, continue card, flashcards due, daily goal ring,
/// and a Duolingo-style vertical learning path map.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeTab(),
    SurahListPage(),
    TasbihPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(context),
      floatingActionButton: _buildPracticeFAB(context),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 0,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _navItem(Icons.home_rounded, 'Home', 0),
              _navItem(Icons.menu_book_rounded, 'Quran', 1),
              const SizedBox(width: 48), // Space for FAB
              // Tilawat opens the full-screen Mushaf (no bottom nav), so it
              // pushes a route instead of switching tabs.
              _navItem(Icons.auto_stories_rounded, 'Tilawat', -1,
                  onTap: _openTilawat),
              _navItem(Icons.auto_awesome_rounded, 'Tasbih', 2),
            ],
          ),
        ),
      ),
    );
  }

  void _openTilawat() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const LiveRecitationPage(initialMode: RecitationMode.tilawat),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index,
      {VoidCallback? onTap}) {
    final theme = Theme.of(context);
    final isSelected = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await Haptics.vibrate(HapticsType.selection);
          if (onTap != null) {
            onTap();
            return;
          }
          setState(() => _currentIndex = index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticeFAB(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () async {
        await Haptics.vibrate(HapticsType.medium);
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LiveRecitationPage(
            initialMode: RecitationMode.hifz,
          )),
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.mic_rounded,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}

/// The Home tab content — streak, XP, continue, flashcards, goal ring, path map.
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  String _selectedLanguage = 'en';
  String _displayName = '';
  HomeResponse? _home;
  List<PathNode>? _curriculumNodes;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
    _loadDisplayName();
    _loadCurriculumPath();
    _loadHome();
  }

  Future<void> _loadLanguage() async {
    final storage = LocalStorageService();
    final lang = await storage.getSelectedLanguage();
    if (mounted && lang != null) {
      setState(() => _selectedLanguage = lang);
    }
  }

  /// Local-first greeting name: cached display name, else the email
  /// local-part. Refreshed (and re-cached) whenever /me/home succeeds.
  Future<void> _loadDisplayName() async {
    final storage = LocalStorageService();
    final name = await storage.getDisplayName();
    final email = await storage.getUserEmail();
    if (mounted) {
      setState(() {
        _displayName = (name?.isNotEmpty == true)
            ? name!
            : (email?.split('@').first ?? '');
      });
    }
  }

  /// Fetches the home screen data. Any failure leaves [_home] null so the UI
  /// falls back to zero/empty defaults rather than stale or fake values.
  /// Bounded to 10s so a slow backend can't pin the loading state.
  Future<void> _loadHome() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final home = await UserRepository()
          .getHomeData()
          .timeout(const Duration(seconds: 10));
      if (mounted) setState(() => _home = home);
      final freshName = home.user.displayName;
      if (freshName != null && freshName.isNotEmpty) {
        await LocalStorageService().setDisplayName(freshName);
        if (mounted) setState(() => _displayName = freshName);
      }
    } catch (e) {
      debugPrint('HomeTab: failed to load home data: $e');
      if (mounted) setState(() => _home = null);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─── Derived progress values (default to zero / empty) ───────────────────
  int get _streak => _home?.streakCount ?? _home?.user.currentStreak ?? 0;
  int get _xpToday => _home?.xpToday ?? 0;
  int get _xpWeeklyGoal => _home?.xpWeeklyGoal ?? 100;
  LessonProgress? get _continueLesson => _home?.continueLesson;
  int get _flashcardsDue => _home?.flashcardsDue ?? 0;
  int get _dailyGoalProgress => _home?.dailyGoalProgress ?? 0;
  int get _dailyGoal => _home?.dailyGoal ?? 5;

  /// Server learning path when it has content, else the bundled curriculum
  /// path (offline-first — the old build showed a static 10-node sample).
  List<PathNode>? get _pathNodes {
    final server = _home?.learningPath;
    if (server != null && server.isNotEmpty) return server;
    return _curriculumNodes;
  }

  /// Builds the home path from the local curriculum with real completion
  /// state: foundation → grammar → vocabulary levels, trimmed a little past
  /// the learner's frontier so the map stays scannable.
  Future<void> _loadCurriculumPath() async {
    final svc = CurriculumService.instance;
    final all = await svc.allLessons();
    final done = await svc.completedIds();
    final nodes = <PathNode>[];
    var previousDone = true;
    for (final lesson in all) {
      final isDone = done.contains('${lesson.lessonId}');
      final locked = !previousDone && !isDone;
      nodes.add(PathNode(
        id: '${lesson.lessonId}',
        label: lesson.title,
        type: PathNodeType.lesson,
        isCompleted: isDone,
        isCurrent: !isDone && !locked,
        isLocked: locked,
        xpReward: lesson.xpReward,
        lessonId: lesson.lessonId,
      ));
      previousDone = isDone;
      if (nodes.length >= 14 && locked) break;
    }
    if (mounted) setState(() => _curriculumNodes = nodes);
  }

  /// Opens the lesson player for either the continue-lesson or a tapped path
  /// node. Curriculum nodes resolve to their REAL lesson (concepts +
  /// quizzes); server nodes fall back to a minimal model as before.
  Future<void> _openLesson({LessonProgress? lesson, PathNode? node}) async {
    if (lesson != null) {
      _navigateToLesson(LessonModel(
        lessonId: lesson.lessonId,
        moduleNumber: lesson.moduleNumber,
        lessonNumber: lesson.lessonNumber,
        title: lesson.title,
        description: '',
      ));
      return;
    }
    if (node != null) {
      final id = node.lessonId ?? int.tryParse(node.id);
      final curriculumLesson =
          await CurriculumService.instance.findLesson(id);
      if (curriculumLesson != null) {
        _navigateToLesson(curriculumLesson);
        return;
      }
      _navigateToLesson(LessonModel(
        lessonId: id ?? 1,
        moduleNumber: 1,
        lessonNumber: id ?? 1,
        title: node.label,
        description: '',
      ));
      return;
    }
    // No lesson or path node is available yet — open the lesson catalogue so
    // the "Start your journey" card still leads the user somewhere useful
    // instead of doing nothing.
    Haptics.vibrate(HapticsType.medium);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LessonListPage()),
    );
  }

  Future<void> _navigateToLesson(LessonModel model) async {
    Haptics.vibrate(HapticsType.medium);
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LessonPlayerPage(lesson: model)),
    );
    // Refresh the curriculum path (and server data) after a completion so
    // the next node unlocks immediately.
    if (completed == true) {
      _loadCurriculumPath();
      _loadHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrdu = _selectedLanguage == 'ur';

    return Scaffold(
      body: SereneBackground(
        child: SafeArea(
          child: RefreshIndicator(
          onRefresh: () async {
            await Haptics.vibrate(HapticsType.medium);
            await _loadHome();
          },
          child: CustomScrollView(
            slivers: [
              // ─── Header ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUrdu ? 'السلام علیکم' : 'Assalamu Alaikum',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              textDirection:
                                  isUrdu ? TextDirection.rtl : TextDirection.ltr,
                            ),
                            if (_displayName.isNotEmpty)
                              Text(
                                _displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProfilePage(),
                          ),
                        ),
                        icon: Icon(
                          Icons.person_rounded,
                          color: theme.colorScheme.primary,
                        ),
                        tooltip: 'Profile',
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_fire_department_rounded,
                              color: Colors.orange.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_streak',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── XP Bar ──────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: _XpBar(
                    currentXp: _xpToday,
                    weeklyGoal: _xpWeeklyGoal,
                  ),
                ),
              ),

              // ─── Continue Card ───────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: _continueLesson != null
                      ? ContinueCard(
                          lessonTitle: _continueLesson!.title,
                          moduleNumber: _continueLesson!.moduleNumber,
                          progressPercent: _continueLesson!.progressPercent,
                          onTap: () => _openLesson(lesson: _continueLesson),
                        )
                      : _StartLearningCard(
                          isUrdu: isUrdu,
                          onTap: () => _openLesson(
                            node: _pathNodes != null && _pathNodes!.isNotEmpty
                                ? _pathNodes!.first
                                : null,
                          ),
                        ),
                ),
              ),

              // ─── Flashcards Due + Daily Goal Ring ────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _FlashcardsDueCard(
                          dueCount: 12,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const FlashcardPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DailyGoalRing(
                          current: _dailyGoalProgress,
                          goal: _dailyGoal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ─── Learning Path Map ───────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    isUrdu ? 'سیکھنے کا راستہ' : 'Learning Path',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LearningPathMap(
                    nodes: _pathNodes,
                    onNodeTap: (node) => _openLesson(node: node),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Prompt shown when there is no in-progress lesson yet.
class _StartLearningCard extends StatelessWidget {
  final bool isUrdu;
  final VoidCallback onTap;

  const _StartLearningCard({required this.isUrdu, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUrdu ? 'اپنا سفر شروع کریں' : 'Start your journey',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUrdu
                          ? 'نیچے دیے گئے سبق پر ٹیپ کریں'
                          : 'Tap a lesson below to begin',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// XP progress bar widget.
class _XpBar extends StatelessWidget {
  final int currentXp;
  final int weeklyGoal;

  const _XpBar({required this.currentXp, required this.weeklyGoal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (currentXp / weeklyGoal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, color: Colors.amber.shade700, size: 18),
            const SizedBox(width: 6),
            Text(
              '$currentXp / $weeklyGoal XP',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'This week',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.amber.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(Colors.amber.shade700),
          ),
        ),
      ],
    );
  }
}

/// Flashcards due card.
class _FlashcardsDueCard extends StatelessWidget {
  final int dueCount;
  final VoidCallback onTap;

  const _FlashcardsDueCard({required this.dueCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppConstants.cardBorderRadius),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.style_rounded, color: theme.colorScheme.secondary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'Flashcards',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$dueCount',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.secondary,
                ),
              ),
              Text(
                'due today',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
