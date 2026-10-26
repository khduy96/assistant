import 'reminder.dart';

/// An alert that is due and waiting to be shown.
class PendingAlert {
  const PendingAlert({
    required this.reminder,
    required this.at,
    required this.eventAt,
    required this.isLead,
  });

  /// The reminder as it was when the alert came due.
  final Reminder reminder;

  /// When the alert rang (or should have).
  final DateTime at;

  /// When the event itself happens; later than [at] for a lead alert.
  final DateTime eventAt;

  /// True for the "remind me N minutes before" alert, false for the event
  /// itself.
  final bool isLead;

  @override
  bool operator ==(Object other) =>
      other is PendingAlert &&
      other.reminder == reminder &&
      other.at == at &&
      other.eventAt == eventAt &&
      other.isLead == isLead;

  @override
  int get hashCode => Object.hash(reminder, at, eventAt, isLead);

  @override
  String toString() =>
      'PendingAlert(${reminder.id}, at: $at, event: $eventAt, lead: $isLead)';
}
