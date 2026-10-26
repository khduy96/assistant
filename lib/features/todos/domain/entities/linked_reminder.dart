/// What the todo list needs to know about the reminder (or deadline) an item
/// was turned into: enough to label the tile and to ask before removing it.
///
/// A snapshot taken when it was looked up; the reminders feature owns the
/// real thing, reached through `LinkedReminderRepository`.
class LinkedReminder {
  const LinkedReminder({
    required this.id,
    required this.title,
    required this.isDeadline,
    required this.enabled,
    this.nextOccurrence,
  });

  final String id;
  final String title;

  /// True for a deadline, false for a plain reminder.
  final bool isDeadline;

  /// False while the alarm is switched off, e.g. after the item was ticked.
  final bool enabled;

  /// The next time the event itself happens (lead alerts not counted), as of
  /// the lookup; null when it has no occurrence left.
  final DateTime? nextOccurrence;

  @override
  bool operator ==(Object other) =>
      other is LinkedReminder &&
      other.id == id &&
      other.title == title &&
      other.isDeadline == isDeadline &&
      other.enabled == enabled &&
      other.nextOccurrence == nextOccurrence;

  @override
  int get hashCode =>
      Object.hash(id, title, isDeadline, enabled, nextOccurrence);

  @override
  String toString() =>
      'LinkedReminder($id, deadline: $isDeadline, enabled: $enabled, '
      'next: $nextOccurrence)';
}
