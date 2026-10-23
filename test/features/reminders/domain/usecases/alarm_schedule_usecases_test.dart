import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/entities/scheduled_alarm.dart';
import 'package:event_notice/features/reminders/domain/usecases/build_alarm_schedule.dart';
import 'package:event_notice/features/reminders/domain/usecases/can_draw_overlays.dart';
import 'package:event_notice/features/reminders/domain/usecases/can_schedule_exact_alarms.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_launch_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_ringing_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/request_alarm_permissions.dart';
import 'package:event_notice/features/reminders/domain/usecases/request_overlay_permission.dart';
import 'package:event_notice/features/reminders/domain/usecases/schedule_alarms.dart';
import 'package:event_notice/features/reminders/domain/usecases/start_alarm_sound.dart';
import 'package:event_notice/features/reminders/domain/usecases/stop_alarm_sound.dart';
import 'package:event_notice/features/reminders/domain/usecases/stop_ringing.dart';
import 'package:event_notice/features/reminders/domain/usecases/test_alarm_ring.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _disk = StorageFailure('disk');

final _now = DateTime(2026, 9, 14, 12);

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime(2026, 9, day, hour, minute);

String _payload(String id, DateTime at, bool lead) =>
    '$id|${at.millisecondsSinceEpoch}|${lead ? 1 : 0}';

Reminder _r(
  String id, {
  RepeatRule repeat = RepeatRule.once,
  int day = 14,
  int hour = 14,
  int leadMinutes = 0,
  int repeatEveryMinutes = 0,
  TimeOfDay? endTime,
  bool enabled = true,
  DateTime? snoozedUntil,
}) => Reminder(
  id: id,
  title: 'Tiêu đề $id',
  repeat: repeat,
  enabled: enabled,
  date: DateTime(2026, 9, day),
  time: TimeOfDay(hour: hour, minute: 0),
  leadMinutes: leadMinutes,
  repeatEveryMinutes: repeatEveryMinutes,
  endTime: endTime,
  snoozedUntil: snoozedUntil,
  createdAt: DateTime(2026, 9, 1),
);

void main() {
  late FakeClock clock;
  late BuildAlarmSchedule build;

  setUp(() {
    clock = FakeClock(_now);
    build = BuildAlarmSchedule(FakeAlarmBodyFormatter(), clock);
  });

  Future<List<ScheduledAlarm>> schedule(List<Reminder> reminders) async =>
      (await build(reminders)).valueOrNull!;

  group('BuildAlarmSchedule', () {
    test('đúng danh sách {id, at, title, body, payload}', () async {
      final alarms = await schedule([
        _r('b', day: 15, hour: 9),
        _r('a', hour: 14, leadMinutes: 10),
        _r('off', hour: 13, enabled: false),
        _r('past', hour: 9),
      ]);

      expect(alarms, [
        ScheduledAlarm(
          id: 1,
          at: _at(14, 13, 50),
          title: 'Tiêu đề a',
          body: 'lead a@14:00',
          payload: _payload('a', _at(14, 13, 50), true),
        ),
        ScheduledAlarm(
          id: 2,
          at: _at(14, 14),
          title: 'Tiêu đề a',
          body: 'a@14:00',
          payload: _payload('a', _at(14, 14), false),
        ),
        ScheduledAlarm(
          id: 3,
          at: _at(15, 9),
          title: 'Tiêu đề b',
          body: 'b@09:00',
          payload: _payload('b', _at(15, 9), false),
        ),
      ]);
    });

    test('payload có dạng reminderId|epochMillis|0 hoặc 1', () async {
      final alarms = await schedule([_r('a', leadMinutes: 10)]);
      expect(alarms.map((a) => a.payload), [
        'a|${_at(14, 13, 50).millisecondsSinceEpoch}|1',
        'a|${_at(14, 14).millisecondsSinceEpoch}|0',
      ]);
    });

    test('mỗi nhắc nhở tối đa 8 lần báo', () async {
      // Mỗi 30 phút từ 12:30 tới 23:30: còn rất nhiều mốc trong ngày.
      final alarms = await schedule([
        _r(
          'busy',
          repeat: RepeatRule.daily,
          hour: 12,
          repeatEveryMinutes: 30,
          endTime: TimeOfDay(hour: 23, minute: 30),
        ),
      ]);

      expect(BuildAlarmSchedule.perReminderLimit, 8);
      expect(alarms, hasLength(8));
      expect(alarms.first.at, _at(14, 12, 30));
      expect(alarms.last.at, _at(14, 16));
    });

    test('tối đa 48 mục, xếp theo thời gian, id đánh từ 1', () async {
      // 7 nhắc hàng ngày lệch nhau 1 phút: 56 lần báo, giữ 48 lần sớm nhất.
      final alarms = await schedule([
        for (var i = 6; i >= 0; i--)
          _r(
            'r$i',
            repeat: RepeatRule.daily,
            hour: 13,
          ).copyWith(time: TimeOfDay(hour: 13, minute: i)),
      ]);

      expect(BuildAlarmSchedule.scheduleLimit, 48);
      expect(alarms, hasLength(48));
      expect([for (final a in alarms) a.id], [for (var i = 1; i <= 48; i++) i]);
      for (var i = 1; i < alarms.length; i++) {
        expect(alarms[i].at.isBefore(alarms[i - 1].at), isFalse);
      }
      expect(alarms.first.at, _at(14, 13, 0));
      // 48 = 6 ngày đủ 7 nhắc, rồi 6 nhắc đầu của ngày thứ 7.
      expect(alarms.last.at, _at(20, 13, 5));
    });

    test('lần báo lại đi đầu, sự kiện của nó tính từ bây giờ', () async {
      final alarms = await schedule([
        _r(
          'a',
          repeat: RepeatRule.daily,
          hour: 9,
          snoozedUntil: _at(14, 12, 5),
        ),
      ]);

      expect(alarms.first.at, _at(14, 12, 5));
      expect(alarms.first.body, 'a@09:00');
      expect(alarms.first.payload, _payload('a', _at(14, 12, 5), false));
      expect(alarms[1].at, _at(15, 9));
    });

    test('không có gì để báo thì danh sách rỗng', () async {
      expect(await schedule([]), isEmpty);
      expect(await schedule([_r('past', hour: 9)]), isEmpty);
    });
  });

  group('ScheduleAlarms', () {
    test('gửi đúng danh sách đã dựng cho scheduler', () async {
      final repo = InMemoryReminderRepository([
        _r('b', day: 15, hour: 9),
        _r('a', hour: 14),
      ]);
      final scheduler = FakeAlarmScheduler();

      final result = await ScheduleAlarms(repo, scheduler, build, clock)(
        const NoParams(),
      );

      expect(result, const Ok<void>(null));
      expect(scheduler.scheduled, [
        await schedule([_r('a', hour: 14), _r('b', day: 15, hour: 9)]),
      ]);
    });

    test('nơi OS không tự kêu thì không làm gì', () async {
      final repo = InMemoryReminderRepository()..failure = _disk;
      final scheduler = FakeAlarmScheduler(ringsNatively: false);

      final result = await ScheduleAlarms(repo, scheduler, build, clock)(
        const NoParams(),
      );

      expect(result, const Ok<void>(null));
      expect(scheduler.calls, isEmpty);
    });

    test('lỗi đọc hoặc lỗi scheduler được trả lại', () async {
      final scheduler = FakeAlarmScheduler();
      final broken = InMemoryReminderRepository()..failure = _disk;
      expect(
        await ScheduleAlarms(broken, scheduler, build, clock)(const NoParams()),
        const Err<void>(_disk),
      );
      expect(scheduler.calls, isEmpty);

      const channel = UnexpectedFailure('channel');
      scheduler.failure = channel;
      expect(
        await ScheduleAlarms(
          InMemoryReminderRepository(),
          scheduler,
          build,
          clock,
        )(const NoParams()),
        const Err<void>(channel),
      );
    });
  });

  group('use case bọc AlarmScheduler', () {
    test('chuyển thẳng lời gọi và kết quả', () async {
      final s = FakeAlarmScheduler()
        ..ringing = 'r1|1|0'
        ..launch = 'r2|2|1'
        ..exact = false
        ..overlays = true;
      const p = NoParams();

      expect(await StopRinging(s)(p), const Ok<void>(null));
      expect(await GetRingingPayload(s)(p), const Ok<String?>('r1|1|0'));
      expect(await GetLaunchPayload(s)(p), const Ok<String?>('r2|2|1'));
      expect(await RequestAlarmPermissions(s)(p), const Ok<void>(null));
      expect(await CanScheduleExactAlarms(s)(p), const Ok(false));
      expect(await CanDrawOverlays(s)(p), const Ok(true));
      expect(await RequestOverlayPermission(s)(p), const Ok<void>(null));
      expect(await TestAlarmRing(s)(p), const Ok<void>(null));
      expect(s.calls, [
        'stopRinging',
        'ringingPayload',
        'launchPayload',
        'requestPermissions',
        'canScheduleExactAlarms',
        'canDrawOverlays',
        'requestOverlayPermission',
        'testRing',
      ]);
    });

    test('lỗi của scheduler được trả lại', () async {
      const channel = UnexpectedFailure('channel');
      final s = FakeAlarmScheduler()..failure = channel;
      expect(
        await GetRingingPayload(s)(const NoParams()),
        const Err<String?>(channel),
      );
    });
  });

  test('StartAlarmSound và StopAlarmSound điều khiển chuông', () async {
    final ringer = FakeAlarmRinger();
    await StartAlarmSound(ringer)(const NoParams());
    await StopAlarmSound(ringer)(const NoParams());
    expect(ringer.calls, ['start', 'stop']);
  });
}
