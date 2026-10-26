/// One alarm handed to the OS, so it rings while the app is closed or the
/// phone is asleep. Built by `BuildAlarmSchedule`.
class ScheduledAlarm {
  const ScheduledAlarm({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
  });

  /// Position in the schedule, counted from 1; the OS keys alarms by it.
  final int id;

  /// When it rings.
  final DateTime at;

  /// Title of the notification: the reminder's title.
  final String title;

  /// Text under the title, from `AlarmBodyFormatter`.
  final String body;

  /// Lets the app rebuild the alert when the alarm opens it; see
  /// `AlarmPayload`.
  final String payload;

  @override
  bool operator ==(Object other) =>
      other is ScheduledAlarm &&
      other.id == id &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.payload == payload;

  @override
  int get hashCode => Object.hash(id, at, title, body, payload);

  @override
  String toString() => 'ScheduledAlarm($id, at: $at, payload: $payload)';
}
