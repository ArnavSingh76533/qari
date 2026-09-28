import '../../../data/models/recitation_stream_event.dart';

/// How a single word must be RENDERED in the live Mushaf canvas.
///
/// This is deliberately separate from [LiveWordStatus] (the wire contract).
/// The wire can say "this word was skipped", but the UI is only allowed to paint
/// that red under one condition — see [resolveWordViewState].
enum LiveWordViewState {
  /// Not said yet: faint ghost ink (readable guidance, visibly not
  /// "recognised"). Never red, never a squiggle.
  unspoken,

  /// The listening cursor — the word expected right now.
  active,

  /// Confirmed match (wire `status == "match"`).
  correct,

  /// Confirmed mistake (wire `status == "error_skipped"`).
  mismatch,
}

/// Resolves how ONE word should render.
///
/// THE HARD RULE: a word AHEAD of the recitation cursor is [unspoken], full stop.
/// The server can still emit a `error_skipped` event for a word the reciter has
/// demonstrably not reached yet (a stale/overlapping window, or a mis-stitched
/// hypothesis). Rendering that red is what produced the reported "the whole page
/// turns red from ayah 2 down to الضالين" — a client that trusts the wire
/// blindly will always be one bad window away from a red wall.
///
/// Precedence (highest first):
///   1. index > cursor            -> unspoken   (never red ahead of the cursor)
///   2. index == cursor           -> active     (listening highlight)
///   3. wire says match           -> correct
///   4. wire says error_skipped   -> mismatch   (only reachable behind the cursor)
///   5. anything else             -> unspoken
LiveWordViewState resolveWordViewState({
  required LiveWordStatus serverStatus,
  required int index,
  required int cursor,
}) {
  // Rule 1 — the guard that prevents the red wall.
  if (index > cursor) return LiveWordViewState.unspoken;
  // Rule 2 — the listening cursor always wins over any wire status.
  if (index == cursor) return LiveWordViewState.active;
  switch (serverStatus) {
    case LiveWordStatus.matched:
      return LiveWordViewState.correct;
    case LiveWordStatus.error:
    case LiveWordStatus.skipped:
      return LiveWordViewState.mismatch;
    case LiveWordStatus.pending:
      return LiveWordViewState.unspoken;
  }
}

/// Resolves the render state for a whole revealed run, 1:1 with [statuses].
///
/// [cursor] is the index of the word the reciter is expected to say next; every
/// word at or before it may carry a verdict, everything after it is neutral.
List<LiveWordViewState> resolveWordViewStates({
  required List<LiveWordStatus> statuses,
  required int cursor,
}) {
  return <LiveWordViewState>[
    for (var i = 0; i < statuses.length; i++)
      resolveWordViewState(
        serverStatus: statuses[i],
        index: i,
        cursor: cursor,
      ),
  ];
}

/// Resolves how ONE word renders on the post-recitation REVIEW page.
///
/// [reach] is the number of words the reciter actually got to (exclusive end).
/// There is no listening cursor after stopping, so nothing is [active]:
///   1. index >= reach            -> unspoken  (never reached: never red)
///   2. wire says match           -> correct
///   3. wire says error_skipped   -> mismatch
///   4. still pending             -> unspoken
LiveWordViewState resolveReviewWordViewState({
  required LiveWordStatus serverStatus,
  required int index,
  required int reach,
}) {
  if (index >= reach) return LiveWordViewState.unspoken;
  switch (serverStatus) {
    case LiveWordStatus.matched:
      return LiveWordViewState.correct;
    case LiveWordStatus.error:
    case LiveWordStatus.skipped:
      return LiveWordViewState.mismatch;
    case LiveWordStatus.pending:
      return LiveWordViewState.unspoken;
  }
}

/// True when [viewState] is allowed to carry an error colour.
bool isErrorStyle(LiveWordViewState viewState) =>
    viewState == LiveWordViewState.mismatch;
