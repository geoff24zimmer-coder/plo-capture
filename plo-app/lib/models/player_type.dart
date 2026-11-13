/// A quick read on another player, set by long-pressing their seat while logging a hand (ai-hand-reviewer D35).
///
/// Saved in the hand history as that seat's `tags` (plo-hand-history.schema.json: "Quick reads"), so the AI coach
/// can say how the play changes against this kind of player instead of assuming a typical recreational one.
/// Optional, and per hand: the app keeps the button in one place and names seats by position, so a type can't follow
/// a real player from hand to hand.
enum PlayerType {
  station('station', 'Station', 'Calls too much'),
  nit('nit', 'Nit', 'Tight, plays few hands'),
  maniac('maniac', 'Maniac', 'Loose, raises a lot'),
  reg('reg', 'Reg', 'Solid regular');

  const PlayerType(this.tag, this.label, this.hint);

  /// What's saved in the hand history.
  final String tag;

  /// What the seat shows.
  final String label;

  /// One line under the label when choosing.
  final String hint;

  /// The type in a saved seat's `tags`, if any.
  static PlayerType? fromTags(Object? tags) {
    if (tags is! List) return null;
    for (final t in values) {
      if (tags.contains(t.tag)) return t;
    }
    return null;
  }
}
