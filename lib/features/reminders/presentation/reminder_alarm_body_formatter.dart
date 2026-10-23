import '../../../core/presentation/format.dart';
import '../domain/entities/reminder.dart';
import '../domain/ports/alarm_body_formatter.dart';

/// The text under the title of an Android alarm notification: "Còn N phút
/// nữa — bắt đầu lúc HH:mm" before the event, "Đến giờ rồi — HH:mm" at it,
/// followed by `" · <ghi chú>"` when the reminder has a note.
class ReminderAlarmBodyFormatter implements AlarmBodyFormatter {
  const ReminderAlarmBodyFormatter();

  @override
  String body(Reminder reminder, DateTime eventAt, {required bool isLead}) {
    final at = '${two(eventAt.hour)}:${two(eventAt.minute)}';
    if (isLead) {
      return 'Còn ${reminder.leadMinutes} phút nữa — bắt đầu lúc $at';
    }
    final note = reminder.note.trim();
    return 'Đến giờ rồi — $at${note.isEmpty ? '' : ' · $note'}';
  }
}
