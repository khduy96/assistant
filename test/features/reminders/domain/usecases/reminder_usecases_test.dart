import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_reminders.dart';
import 'package:event_notice/features/reminders/domain/usecases/new_reminder_id.dart';
import 'package:event_notice/features/reminders/domain/usecases/save_reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/watch_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

Reminder _r(String id, {int hour = 14, bool enabled = true}) => Reminder(
  id: id,
  title: id,
  enabled: enabled,
  date: DateTime(2026, 9, 14),
  time: TimeOfDay(hour: hour, minute: 0),
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  const disk = StorageFailure('disk');
  late FakeClock clock;

  setUp(() => clock = FakeClock(DateTime(2026, 9, 14, 12)));

  group('GetReminders', () {
    test('sắp theo thứ tự hiển thị tại Clock.now()', () async {
      final repo = InMemoryReminderRepository([
        _r('off', enabled: false, hour: 13),
        _r('later', hour: 18),
        _r('soon', hour: 13),
      ]);

      final result = await GetReminders(repo, clock)(const NoParams());
      expect(
        [for (final r in result.valueOrNull!) r.id],
        ['soon', 'later', 'off'],
      );

      // Sau 13:00, 'soon' đã hết lịch nên xuống sau 'later'.
      clock.current = DateTime(2026, 9, 14, 13, 30);
      final later = await GetReminders(repo, clock)(const NoParams());
      expect(
        [for (final r in later.valueOrNull!) r.id],
        ['later', 'soon', 'off'],
      );
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryReminderRepository()..failure = disk;
      expect(
        await GetReminders(repo, clock)(const NoParams()),
        const Err<List<Reminder>>(disk),
      );
    });
  });

  test('WatchReminders bắn khi dữ liệu đổi', () async {
    final repo = InMemoryReminderRepository();
    addTearDown(repo.dispose);
    final stream = (await WatchReminders(repo)(const NoParams())).valueOrNull!;
    var fired = 0;
    final sub = stream.listen((_) => fired++);
    addTearDown(sub.cancel);

    await SaveReminder(repo, clock)(_r('a'));
    await repo.delete('a');

    expect(fired, 2);
  });

  test('NewReminderId lấy id từ IdGenerator', () async {
    final use = NewReminderId(SequentialIdGenerator());
    expect(await use(const NoParams()), const Ok('id-1'));
    expect(await use(const NoParams()), const Ok('id-2'));
  });
}
