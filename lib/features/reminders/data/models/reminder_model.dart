import '../../../../core/domain/time_of_day.dart';
import '../../domain/entities/reminder.dart';

/// A reminder as it is stored in `reminders.json`.
///
/// The only place that knows the file's layout. It may not change: files
/// written by older builds still have to load, and reminders are not synced,
/// so there is no sync state to carry.
class ReminderModel {
  ReminderModel({
    required this.id,
    this.title = '',
    this.note = '',
    this.enabled = true,
    this.repeat = RepeatRule.once,
    required this.date,
    required this.time,
    this.weekdays = const {},
    this.repeatEveryMinutes = 0,
    this.endTime,
    this.leadMinutes = 0,
    this.snoozeMinutes = 5,
    this.snoozedUntil,
    this.firedUpTo,
    this.isDeadline = false,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String note;
  final bool enabled;
  final RepeatRule repeat;
  final DateTime date;
  final TimeOfDay time;
  final Set<int> weekdays;
  final int repeatEveryMinutes;
  final TimeOfDay? endTime;
  final int leadMinutes;
  final int snoozeMinutes;
  final DateTime? snoozedUntil;
  final DateTime? firedUpTo;
  final bool isDeadline;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'enabled': enabled,
    'repeat': repeat.name,
    'date': date.toIso8601String(),
    'hour': time.hour,
    'minute': time.minute,
    'weekdays': weekdays.toList()..sort(),
    'repeatEveryMinutes': repeatEveryMinutes,
    'endHour': endTime?.hour,
    'endMinute': endTime?.minute,
    'leadMinutes': leadMinutes,
    'snoozeMinutes': snoozeMinutes,
    'snoozedUntil': snoozedUntil?.toIso8601String(),
    'firedUpTo': firedUpTo?.toIso8601String(),
    'isDeadline': isDeadline,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Reads one entry of `reminders.json`. [now] stands in for a missing or
  /// unreadable `createdAt`. Throws when `id` or `date` is missing, or a
  /// stored time cannot be read.
  factory ReminderModel.fromJson(
    Map<String, dynamic> j, {
    required DateTime now,
  }) {
    DateTime? at(String key) =>
        j[key] == null ? null : DateTime.parse(j[key] as String);

    final endHour = j['endHour'] as int?;
    return ReminderModel(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      note: j['note'] as String? ?? '',
      enabled: j['enabled'] as bool? ?? true,
      // Stored by name; a missing or unknown one reads as once.
      repeat: RepeatRule.values.firstWhere(
        (m) => m.name == j['repeat'],
        orElse: () => RepeatRule.once,
      ),
      date: DateTime.parse(j['date'] as String),
      time: TimeOfDay(
        hour: j['hour'] as int? ?? 8,
        minute: j['minute'] as int? ?? 0,
      ),
      weekdays: {
        for (final e in (j['weekdays'] as List?) ?? const []) e as int,
      },
      repeatEveryMinutes: j['repeatEveryMinutes'] as int? ?? 0,
      // No end hour means no in-day stop time.
      endTime: endHour == null
          ? null
          : TimeOfDay(hour: endHour, minute: j['endMinute'] as int? ?? 0),
      leadMinutes: j['leadMinutes'] as int? ?? 0,
      snoozeMinutes: j['snoozeMinutes'] as int? ?? 5,
      snoozedUntil: at('snoozedUntil'),
      firedUpTo: at('firedUpTo'),
      isDeadline: j['isDeadline'] as bool? ?? false,
      createdAt: j['createdAt'] == null
          ? now
          : DateTime.tryParse(j['createdAt'] as String) ?? now,
    );
  }
}
