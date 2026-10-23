import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/core/platform/android_alarm_channel.dart';
import 'package:event_notice/features/reminders/data/android_alarm_scheduler.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/entities/scheduled_alarm.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/domain/usecases/build_alarm_schedule.dart';
import 'package:event_notice/features/reminders/domain/usecases/schedule_alarms.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';

/// Thursday morning.
final _now = DateTime(2026, 10, 22, 8);

/// The two wordings of the old `AndroidAlarmService._body`, so the expected
/// bodies below read as they did on the phone.
class _OldBodyFormatter implements AlarmBodyFormatter {
  @override
  String body(Reminder reminder, DateTime eventAt, {required bool isLead}) {
    String two(int n) => n.toString().padLeft(2, '0');
    final at = '${two(eventAt.hour)}:${two(eventAt.minute)}';
    if (isLead) {
      return 'Còn ${reminder.leadMinutes} phút nữa — bắt đầu lúc $at';
    }
    final note = reminder.note.trim();
    return 'Đến giờ rồi — $at${note.isEmpty ? '' : ' · $note'}';
  }
}

int _ms(DateTime t) => t.millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  /// Answers every call on the alarm channel with [answer] and records it.
  void answer(Object? Function(MethodCall call) answer) {
    messenger.setMockMethodCallHandler(AndroidAlarmChannel.channel, (
      call,
    ) async {
      calls.add(call);
      return answer(call);
    });
  }

  setUp(() {
    calls = [];
    answer((_) => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidAlarmChannel.channel, null);
  });

  test('kênh tên event_notice/alarm', () {
    expect(AndroidAlarmChannel.channel.name, 'event_notice/alarm');
  });

  test('mỗi hàm gọi đúng tên method cũ', () async {
    const scheduler = AndroidAlarmScheduler();
    await scheduler.requestPermissions();
    await scheduler.canScheduleExactAlarms();
    await scheduler.ringingPayload();
    await scheduler.launchPayload();
    await scheduler.testRing();
    await scheduler.canDrawOverlays();
    await scheduler.requestOverlayPermission();
    await scheduler.stopRinging();
    await scheduler.scheduleAll(const []);

    expect(calls.map((c) => c.method), [
      'requestPermissions',
      'canScheduleExact',
      'ringingPayload',
      'launchPayload',
      'testRing',
      'canDrawOverlays',
      'requestOverlayPermission',
      'stopRinging',
      'scheduleAll',
    ]);
    expect(calls.last.arguments, {'alarms': <Object>[]});
    expect(scheduler.ringsNatively, isTrue);
  });

  test('trả lời của Android đi thẳng ra ngoài', () async {
    answer(
      (call) => switch (call.method) {
        'canScheduleExact' => true,
        'canDrawOverlays' => true,
        'ringingPayload' => 'r1|1761094800000|0',
        'launchPayload' => 'r2|1761094800000|1',
        _ => null,
      },
    );
    const scheduler = AndroidAlarmScheduler();
    expect(await scheduler.canScheduleExactAlarms(), const Ok(true));
    expect(await scheduler.canDrawOverlays(), const Ok(true));
    expect(
      await scheduler.ringingPayload(),
      const Ok<String?>('r1|1761094800000|0'),
    );
    expect(
      await scheduler.launchPayload(),
      const Ok<String?>('r2|1761094800000|1'),
    );
  });

  test('Android trả null thì các câu hỏi quyền là false', () async {
    const scheduler = AndroidAlarmScheduler();
    expect(await scheduler.canScheduleExactAlarms(), const Ok(false));
    expect(await scheduler.canDrawOverlays(), const Ok(false));
    expect(await scheduler.ringingPayload(), const Ok<String?>(null));
  });

  test('PlatformException thành Err, không ném', () async {
    answer((_) => throw PlatformException(code: 'boom'));
    const scheduler = AndroidAlarmScheduler();
    final result = await scheduler.scheduleAll(const []);
    expect(result.failureOrNull, isA<UnexpectedFailure>());
    expect(result.failureOrNull!.cause, isA<PlatformException>());
    expect((await scheduler.ringingPayload()).isErr, isTrue);
    expect((await scheduler.stopRinging()).isErr, isTrue);
  });

  test('không có phía native thì cũng thành Err', () async {
    messenger.setMockMethodCallHandler(AndroidAlarmChannel.channel, null);
    final result = await const AndroidAlarmScheduler().testRing();
    expect(result.failureOrNull?.cause, isA<MissingPluginException>());
  });

  test(
    'scheduleAll gửi mỗi báo thức thành {id, at, title, body, payload}',
    () async {
      final at = DateTime(2026, 10, 22, 9, 30);
      await const AndroidAlarmScheduler().scheduleAll([
        ScheduledAlarm(
          id: 1,
          at: at,
          title: 'Họp',
          body: 'Đến giờ rồi — 09:30',
          payload: 'r1|${_ms(at)}|0',
        ),
      ]);
      expect(calls.single.arguments, {
        'alarms': [
          {
            'id': 1,
            'at': _ms(at),
            'title': 'Họp',
            'body': 'Đến giờ rồi — 09:30',
            'payload': 'r1|${_ms(at)}|0',
          },
        ],
      });
    },
  );

  test(
    'ScheduleAlarms với giờ cố định gửi đúng danh sách như bản cũ',
    () async {
      final clock = FakeClock(_now);
      final repo = InMemoryReminderRepository([
        Reminder(
          id: 'hop',
          title: 'Họp khách hàng',
          note: ' phòng 3 ',
          date: DateTime(2026, 10, 22),
          time: TimeOfDay(hour: 9, minute: 30),
          leadMinutes: 15,
          createdAt: _now,
        ),
        Reminder(
          id: 'nuoc',
          title: 'Uống nước',
          repeat: RepeatRule.daily,
          date: DateTime(2026, 10, 1),
          time: TimeOfDay(hour: 8, minute: 30),
          createdAt: _now,
        ),
        Reminder(
          id: 'tat',
          title: 'Đang tắt',
          enabled: false,
          repeat: RepeatRule.daily,
          date: DateTime(2026, 10, 1),
          time: TimeOfDay(hour: 8, minute: 45),
          createdAt: _now,
        ),
        // Đã qua: không còn lần báo nào.
        Reminder(
          id: 'qua',
          title: 'Hôm qua',
          date: DateTime(2026, 10, 21),
          time: TimeOfDay(hour: 9, minute: 0),
          createdAt: _now,
        ),
      ]);
      final schedule = ScheduleAlarms(
        repo,
        const AndroidAlarmScheduler(),
        BuildAlarmSchedule(_OldBodyFormatter(), clock),
        clock,
      );

      expect(await schedule(const NoParams()), const Ok<void>(null));

      Map<String, Object> water(int id, int day) {
        final at = DateTime(2026, 10, day, 8, 30);
        return {
          'id': id,
          'at': _ms(at),
          'title': 'Uống nước',
          'body': 'Đến giờ rồi — 08:30',
          'payload': 'nuoc|${_ms(at)}|0',
        };
      }

      final lead = DateTime(2026, 10, 22, 9, 15);
      final meeting = DateTime(2026, 10, 22, 9, 30);
      expect(calls.single.method, 'scheduleAll');
      expect(calls.single.arguments, {
        'alarms': [
          water(1, 22),
          {
            'id': 2,
            'at': _ms(lead),
            'title': 'Họp khách hàng',
            'body': 'Còn 15 phút nữa — bắt đầu lúc 09:30',
            'payload': 'hop|${_ms(lead)}|1',
          },
          {
            'id': 3,
            'at': _ms(meeting),
            'title': 'Họp khách hàng',
            'body': 'Đến giờ rồi — 09:30 · phòng 3',
            'payload': 'hop|${_ms(meeting)}|0',
          },
          // Mỗi nhắc nhở tối đa 8 lần báo.
          for (var day = 23; day <= 29; day++) water(day - 19, day),
        ],
      });
      await repo.dispose();
    },
  );

  test('ScheduleAlarms cắt ở 48 báo thức, id từ 1 liên tục', () async {
    final clock = FakeClock(_now);
    final repo = InMemoryReminderRepository([
      for (var i = 0; i < 7; i++)
        Reminder(
          id: 'r$i',
          title: 'Nhắc $i',
          repeat: RepeatRule.daily,
          date: DateTime(2026, 10, 1),
          time: TimeOfDay(hour: 9, minute: i),
          createdAt: _now,
        ),
    ]);
    await ScheduleAlarms(
      repo,
      const AndroidAlarmScheduler(),
      BuildAlarmSchedule(_OldBodyFormatter(), clock),
      clock,
    )(const NoParams());

    final alarms = (calls.single.arguments as Map)['alarms'] as List;
    expect(alarms, hasLength(48));
    expect(
      [for (final a in alarms) (a as Map)['id']],
      [for (var i = 1; i <= 48; i++) i],
    );
    final times = [for (final a in alarms) (a as Map)['at'] as int];
    expect(times, [...times]..sort());
    await repo.dispose();
  });
}
