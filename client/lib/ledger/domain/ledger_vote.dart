/// The direction of a Ledger post vote (Task 7.5 Voting System).
///
/// `none` is the un-voted state — the model always knows whether the local
/// device has voted on a post and in which direction, so the UI can render
/// the active state and the repository can toggle deterministically.
enum LedgerVoteDirection {
  /// The post has been upvoted.
  up,

  /// The post has been downvoted.
  down,

  /// No vote recorded for this device.
  none;

  /// Stable wire identifier (server contract, never rendered).
  String get wireName => switch (this) {
        LedgerVoteDirection.up => 'up',
        LedgerVoteDirection.down => 'down',
        LedgerVoteDirection.none => 'none',
      };

  /// Parses a wire name, throwing [ArgumentError] for unknown values
  /// (strict bounds — a server can never smuggle an unknown direction in).
  static LedgerVoteDirection fromWireName(String name) => switch (name) {
        'up' => LedgerVoteDirection.up,
        'down' => LedgerVoteDirection.down,
        'none' => LedgerVoteDirection.none,
        _ => throw ArgumentError('Unknown ledger vote direction: $name'),
      };

  /// The vote delta this direction applies to a post's net count when cast
  /// from the un-voted state (+1 up / -1 down / 0 none).
  int get delta => switch (this) {
        LedgerVoteDirection.up => 1,
        LedgerVoteDirection.down => -1,
        LedgerVoteDirection.none => 0,
      };
}

/// A single vote cast by the local device on a Ledger post (Task 7.5).
///
/// SECURITY CONTRACT: carries ONLY the public post id + an aggregate
/// direction — NO voter identity, NO PII, NO blind hash. The sync transport
/// attributes the vote to the authenticated device server-side (the same
/// contract as the post envelope: identity never rides in the payload).
class LedgerVote {
  final String postId;
  final LedgerVoteDirection direction;

  const LedgerVote({required this.postId, required this.direction});
}
