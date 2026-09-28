import '../../../data/models/recitation_model.dart';
import '../../../data/models/recitation_stream_event.dart';

/// The post-recitation review, scored ONLY over the words the reciter reached.
///
/// Stopping early is not a mistake. The server's `final` payload re-scores the
/// whole target, so if the reciter stops after a few words every remaining word
/// comes back `is_correct: false` — trusting that as-is painted the rest of the
/// surah red and produced a 0% score. [buildRecitationReview] cuts the target at
/// [reach]; everything at or beyond it is "not reached" and never penalised.
class RecitationReview {
  /// Per-word review status, 1:1 with the target words. Words at or beyond
  /// [reach] are always [LiveWordStatus.pending].
  final List<LiveWordStatus> statuses;

  /// Number of target words the reciter got to (exclusive end index).
  final int reach;

  /// Result restricted to the reached words, with the score recomputed over
  /// them. Safe to persist and to feed the word-comparison sheet.
  final RecitationResult result;

  const RecitationReview({
    required this.statuses,
    required this.reach,
    required this.result,
  });

  int get correctCount =>
      statuses.where((s) => s == LiveWordStatus.matched).length;

  int get mistakeCount => statuses
      .where((s) => s == LiveWordStatus.error || s == LiveWordStatus.skipped)
      .length;

  int get unreachedCount => statuses.length - reach;

  /// The verdict for target word [index], or null if it was not evaluated.
  WordVerdict? verdictAt(int index) {
    for (final v in result.wordVerdicts) {
      if (v.wordIndex == index) return v;
    }
    return null;
  }
}

/// Builds the review from the live session state plus the server's `final`.
///
/// * [liveCursor] — the live cursor at stop time (index of the next expected
///   word, so words `< liveCursor` were recited).
/// * [liveStatuses] — the live per-word verdicts, 1:1 with [words].
/// * [serverResult] — the authoritative `final` payload, if it arrived.
///
/// Reach is the furthest point the reciter demonstrably got to: the live cursor,
/// or just past the last word either the live stream or the server matched. A
/// server `false` verdict alone never extends reach — that is exactly the
/// "every unrecited word is error_skipped" signal this guards against.
RecitationReview buildRecitationReview({
  required List<String> words,
  required int liveCursor,
  required List<LiveWordStatus> liveStatuses,
  RecitationResult? serverResult,
  int surahNumber = 1,
  int ayahNumber = 1,
}) {
  final n = words.length;
  final server = <int, WordVerdict>{
    for (final v in serverResult?.wordVerdicts ?? const <WordVerdict>[])
      if (v.wordIndex >= 0 && v.wordIndex < n) v.wordIndex: v,
  };

  var reach = liveCursor;
  for (var i = 0; i < n && i < liveStatuses.length; i++) {
    if (liveStatuses[i] == LiveWordStatus.matched && i + 1 > reach) {
      reach = i + 1;
    }
  }
  for (final v in server.values) {
    if (v.isCorrect && v.wordIndex + 1 > reach) reach = v.wordIndex + 1;
  }
  reach = reach.clamp(0, n);

  final statuses = List<LiveWordStatus>.filled(n, LiveWordStatus.pending);
  final verdicts = <WordVerdict>[];
  for (var i = 0; i < reach; i++) {
    final sv = server[i];
    final live = i < liveStatuses.length ? liveStatuses[i] : LiveWordStatus.pending;
    // The server's final pass is authoritative behind the reach line; the live
    // verdict is the fallback when the final payload is missing that word.
    final LiveWordStatus status;
    if (sv != null) {
      status = sv.isCorrect ? LiveWordStatus.matched : LiveWordStatus.error;
    } else {
      status = live;
    }
    statuses[i] = status;
    if (status == LiveWordStatus.pending) continue; // no evidence either way
    final correct = status == LiveWordStatus.matched;
    verdicts.add(sv ??
        WordVerdict(
          word: words[i],
          wordIndex: i,
          isCorrect: correct,
          expectedText: words[i],
          errorType: correct ? null : status.name,
        ));
  }

  final correctCount = verdicts.where((v) => v.isCorrect).length;
  final score = verdicts.isEmpty ? 0.0 : correctCount / verdicts.length;
  final base = serverResult ??
      RecitationResult(
        sessionId: 'local',
        surahNumber: surahNumber,
        ayahNumber: ayahNumber,
        overallScore: score,
        createdAt: DateTime.now(),
        feedback: 'Live session complete.',
      );
  final result = base.copyWith(
    wordVerdicts: verdicts,
    overallScore: score,
    accuracyScore: score,
  );
  return RecitationReview(statuses: statuses, reach: reach, result: result);
}
