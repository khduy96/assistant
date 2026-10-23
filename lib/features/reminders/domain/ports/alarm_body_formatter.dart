import '../entities/reminder.dart';

/// Writes the text under the title of an OS alarm notification. The wording
/// is user-facing, so it is implemented in presentation.
abstract interface class AlarmBodyFormatter {
  /// The body for an alert of [reminder] whose event happens at [eventAt];
  /// [isLead] is true for the alert that rings before the event.
  String body(Reminder reminder, DateTime eventAt, {required bool isLead});
}
