import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/data/models/reminder_model.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 22, 8);

void main() {
  test('chỉ có id và date thì mọi khoá khác lấy mặc định như bản cũ', () {
    final m = ReminderModel.fromJson({
      'id': 'r1',
      'date': '2026-10-22T00:00:00.000',
    }, now: _now);

    expect(m.toJson(), {
      'id': 'r1',
      'title': '',
      'note': '',
      'enabled': true,
      'repeat': 'once',
      'date': '2026-10-22T00:00:00.000',
      'hour': 8,
      'minute': 0,
      'weekdays': <int>[],
      'repeatEveryMinutes': 0,
      'endHour': null,
      'endMinute': null,
      'leadMinutes': 0,
      'snoozeMinutes': 5,
      'snoozedUntil': null,
      'firedUpTo': null,
      'isDeadline': false,
      'createdAt': '2026-10-22T08:00:00.000',
    });
  });

  test('mọi giá trị repeat đọc theo tên', () {
    for (final rule in RepeatRule.values) {
      final m = ReminderModel.fromJson({
        'id': 'r',
        'date': '2026-10-22T00:00:00.000',
        'repeat': rule.name,
      }, now: _now);
      expect(m.repeat, rule);
      expect(m.toJson()['repeat'], rule.name);
    }
  });

  test('endMinute không có endHour thì bỏ qua', () {
    final m = ReminderModel.fromJson({
      'id': 'r',
      'date': '2026-10-22T00:00:00.000',
      'endMinute': 30,
    }, now: _now);
    expect(m.endTime, isNull);
    expect(m.toJson()['endMinute'], isNull);
  });

  test('toJson ghi giờ dừng và thứ trong tuần sắp tăng dần', () {
    final m = ReminderModel(
      id: 'r',
      date: DateTime(2026, 10, 22),
      time: TimeOfDay(hour: 7, minute: 5),
      weekdays: const {7, 2, 4},
      endTime: TimeOfDay(hour: 23, minute: 59),
      createdAt: _now,
    );
    final json = m.toJson();
    expect(json['hour'], 7);
    expect(json['minute'], 5);
    expect(json['weekdays'], [2, 4, 7]);
    expect(json['endHour'], 23);
    expect(json['endMinute'], 59);
  });

  test('id hoặc date sai kiểu thì ném lỗi', () {
    expect(
      () => ReminderModel.fromJson({'date': '2026-10-22'}, now: _now),
      throwsA(anything),
    );
    expect(
      () => ReminderModel.fromJson({'id': 'r', 'date': 'hôm nay'}, now: _now),
      throwsA(anything),
    );
  });
}
