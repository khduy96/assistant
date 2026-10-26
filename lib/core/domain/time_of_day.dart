/// A wall-clock time without a date, e.g. 08:00.
///
/// Stands in for Flutter's `TimeOfDay` so the domain stays plain Dart.
/// Compared by value; out-of-range hours or minutes are rejected.
final class TimeOfDay {
  TimeOfDay({required this.hour, required this.minute}) {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
  }

  /// 0–23.
  final int hour;

  /// 0–59.
  final int minute;

  @override
  bool operator ==(Object other) =>
      other is TimeOfDay && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
