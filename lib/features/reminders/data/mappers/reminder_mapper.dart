import '../../domain/entities/reminder.dart';
import '../models/reminder_model.dart';

/// Converts between the stored [ReminderModel] and the domain [Reminder].
abstract final class ReminderMapper {
  static Reminder toEntity(ReminderModel model) => Reminder(
    id: model.id,
    title: model.title,
    note: model.note,
    enabled: model.enabled,
    repeat: model.repeat,
    date: model.date,
    time: model.time,
    weekdays: model.weekdays,
    repeatEveryMinutes: model.repeatEveryMinutes,
    endTime: model.endTime,
    leadMinutes: model.leadMinutes,
    snoozeMinutes: model.snoozeMinutes,
    snoozedUntil: model.snoozedUntil,
    firedUpTo: model.firedUpTo,
    isDeadline: model.isDeadline,
    createdAt: model.createdAt,
  );

  static ReminderModel toModel(Reminder reminder) => ReminderModel(
    id: reminder.id,
    title: reminder.title,
    note: reminder.note,
    enabled: reminder.enabled,
    repeat: reminder.repeat,
    date: reminder.date,
    time: reminder.time,
    weekdays: reminder.weekdays,
    repeatEveryMinutes: reminder.repeatEveryMinutes,
    endTime: reminder.endTime,
    leadMinutes: reminder.leadMinutes,
    snoozeMinutes: reminder.snoozeMinutes,
    snoozedUntil: reminder.snoozedUntil,
    firedUpTo: reminder.firedUpTo,
    isDeadline: reminder.isDeadline,
    createdAt: reminder.createdAt,
  );
}
