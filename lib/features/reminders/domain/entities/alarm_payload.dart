/// What an OS alarm carries so the app can rebuild its alert: written as
/// `reminderId|epochMillis|isLead`, with isLead as `1` or `0`.
class AlarmPayload {
  const AlarmPayload({
    required this.reminderId,
    required this.at,
    required this.isLead,
  });

  final String reminderId;

  /// When the alert rings, to the millisecond.
  final DateTime at;

  /// True for the alert that rings before the event.
  final bool isLead;

  /// The payload string handed to the OS.
  String encode() =>
      '$reminderId|${at.millisecondsSinceEpoch}|${isLead ? 1 : 0}';

  @override
  bool operator ==(Object other) =>
      other is AlarmPayload &&
      other.reminderId == reminderId &&
      other.at == at &&
      other.isLead == isLead;

  @override
  int get hashCode => Object.hash(reminderId, at, isLead);

  @override
  String toString() => 'AlarmPayload(${encode()})';
}

/// Reads a payload written by [AlarmPayload.encode]; null when [raw] does not
/// have three `|`-separated parts or the time is not a whole number. Any
/// third part other than `1` reads as not a lead alert.
AlarmPayload? parseAlarmPayload(String raw) {
  final parts = raw.split('|');
  if (parts.length != 3) return null;
  final millis = int.tryParse(parts[1]);
  if (millis == null) return null;
  return AlarmPayload(
    reminderId: parts[0],
    at: DateTime.fromMillisecondsSinceEpoch(millis),
    isLead: parts[2] == '1',
  );
}
