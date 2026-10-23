import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/alarm_payload.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/entities/scheduled_alarm.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// Two seconds before 10:00 on 22/10/2026, so the first ticks cross 10:00.
final _start = DateTime(2026, 10, 22, 9, 59, 58);

/// A controller over fakes, run in fake time. [tick] moves the [clock] and
/// the timers together, one second at a time.
class _Harness {
  _Harness(
    this.async, {
    bool native = false,
    List<Reminder> reminders = const [],
    DateTime? start,
  }) : clock = FakeClock(start ?? _start),
       repo = InMemoryReminderRepository(reminders),
       scheduler = FakeAlarmScheduler(ringsNatively: native) {
    controller = controllerFor(
      repo,
      clock: clock,
      scheduler: scheduler,
      ringer: ringer,
    );
    controller.onAlertShown = () => shown++;
    controller.onAlertsCleared = () => cleared++;
    controller.addListener(() => notified++);
  }

  final FakeAsync async;
  final FakeClock clock;
  final InMemoryReminderRepository repo;
  final FakeAlarmScheduler scheduler;
  final FakeAlarmRinger ringer = FakeAlarmRinger();
  late final RemindersController controller;

  int shown = 0;
  int cleared = 0;
  int notified = 0;

  void init() => settle(controller.init());

  /// Lets [action] and everything it started run to the end.
  void settle(Future<Object?> action) {
    action.ignore();
    async.flushMicrotasks();
  }

  void tick([int seconds = 1]) {
    for (var i = 0; i < seconds; i++) {
      clock.advance(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
    }
  }

  int callsOf(String name) => scheduler.calls.where((c) => c == name).length;

  String? get currentId => controller.currentAlert?.reminder.id;
}

/// Runs [body] in fake time, then disposes the controller.
void _run(
  void Function(_Harness h) body, {
  bool native = false,
  List<Reminder> reminders = const [],
  DateTime? start,
}) {
  fakeAsync((async) {
    final h = _Harness(
      async,
      native: native,
      reminders: reminders,
      start: start,
    );
    body(h);
    h.controller.dispose();
    async.flushMicrotasks();
  });
}

/// The payload an OS alarm carries for the event of [id] at 10:00.
String _payload(String id, {int hour = 10, bool isLead = false}) =>
    AlarmPayload(
      reminderId: id,
      at: DateTime(2026, 10, 22, hour),
      isLead: isLead,
    ).encode();

void main() {
  group('desktop: app tự canh giờ', () {
    test('tick mỗi giây làm mới màn hình, trừ khi uiActive tắt', () {
      _run((h) {
        h.init();
        h.notified = 0;
        h.tick(3);
        expect(h.notified, 3);

        h.controller.uiActive = false;
        h.tick(3);
        expect(h.notified, 3);
      });
    });

    test('lần báo tới hạn vào hàng đợi đúng một lần, chuông bắt đầu ở lần '
        'báo đầu tiên', () {
      _run(
        (h) {
          h.init();
          h.tick();
          expect(h.controller.currentAlert, isNull);
          expect(h.ringer.calls, isEmpty);

          h.tick(); // 10:00:00
          expect(h.currentId, isNotNull);
          expect(h.ringer.calls, ['start']);
          expect(h.shown, 1);
          expect(h.repo['a']!.firedUpTo, DateTime(2026, 10, 22, 10));
          expect(h.repo['b']!.firedUpTo, DateTime(2026, 10, 22, 10));

          h.tick(5);
          expect(h.ringer.calls, ['start']);
          expect(h.shown, 1);
          expect(h.callsOf('ringingPayload'), 0);
        },
        reminders: [
          reminder('a', firedUpTo: _start),
          reminder('b', firedUpTo: _start),
        ],
      );
    });

    test('tắt từng lần báo; chuông chỉ dừng khi hàng đợi rỗng', () {
      _run(
        (h) {
          h.init();
          h.tick(2);
          final first = h.currentId!;

          h.settle(h.controller.dismissCurrent());
          expect(h.currentId, isNot(first));
          expect(h.ringer.calls, ['start']);
          expect(h.cleared, 0);

          h.settle(h.controller.dismissCurrent());
          expect(h.controller.currentAlert, isNull);
          expect(h.ringer.calls, ['start', 'stop']);
          expect(h.cleared, 1);
          // One-off reminders are done once their event is turned off.
          expect(h.repo['a']!.enabled, isFalse);
          expect(h.repo['b']!.enabled, isFalse);
          expect(h.callsOf('stopRinging'), 2);
          // The app rings itself here: nothing goes to the OS schedule.
          expect(h.scheduler.scheduled, isEmpty);
          expect(h.controller.reminders.map((r) => r.enabled), [false, false]);
        },
        reminders: [
          reminder('a', firedUpTo: _start),
          reminder('b', firedUpTo: _start),
        ],
      );
    });

    test('báo lại thì kêu lại sau snoozeMinutes', () {
      _run(
        (h) {
          h.init();
          h.tick(2);
          final now = h.clock.now();

          h.settle(h.controller.snoozeCurrent());
          expect(h.controller.currentAlert, isNull);
          expect(
            h.repo['a']!.snoozedUntil,
            now.add(const Duration(minutes: 3)),
          );
          expect(h.repo['a']!.enabled, isTrue);
          expect(h.ringer.calls, ['start', 'stop']);

          h.tick(3 * 60 - 1);
          expect(h.controller.currentAlert, isNull);
          h.tick();
          expect(h.currentId, 'a');
          expect(h.ringer.calls, ['start', 'stop', 'start']);
          expect(h.shown, 2);
        },
        reminders: [
          reminder('a', snooze: 3, repeat: RepeatRule.daily, firedUpTo: _start),
        ],
      );
    });

    test('tắt lần báo trước giờ thì nhắc vẫn bật', () {
      _run((h) {
        h.init();
        h.tick(2);
        expect(h.controller.currentAlert!.isLead, isTrue);
        expect(
          h.controller.currentAlert!.eventAt,
          DateTime(2026, 10, 22, 10, 10),
        );

        h.settle(h.controller.dismissCurrent());
        expect(h.repo['a']!.enabled, isTrue);
      }, reminders: [reminder('a', minute: 10, lead: 10, firedUpTo: _start)]);
    });

    test('lần báo trễ quá 30 phút không kêu nhưng mốc vẫn tiến', () {
      _run(
        (h) {
          h.init();
          h.tick();
          expect(h.controller.currentAlert, isNull);
          expect(h.ringer.calls, isEmpty);
          expect(h.repo['a']!.firedUpTo, DateTime(2026, 10, 22, 9));
        },
        reminders: [
          reminder('a', hour: 9, firedUpTo: DateTime(2026, 10, 22, 8)),
        ],
      );
    });

    test('xoá nhắc nhở bỏ lần báo của nó; hàng đợi rỗng thì tắt chuông', () {
      _run((h) {
        h.init();
        h.tick(2);
        expect(h.currentId, 'a');

        h.settle(h.controller.remove('a'));
        expect(h.controller.currentAlert, isNull);
        expect(h.ringer.calls, ['start', 'stop']);
        expect(h.cleared, 1);
        expect(h.repo.length, 0);
        expect(h.controller.reminders, isEmpty);
      }, reminders: [reminder('a', firedUpTo: _start)]);
    });

    test('dismissAll tắt mọi lần báo, trả cửa sổ một lần', () {
      _run(
        (h) {
          h.init();
          h.tick(2);

          h.settle(h.controller.dismissAll());
          expect(h.controller.currentAlert, isNull);
          expect(h.ringer.calls, ['start', 'stop']);
          expect(h.cleared, 1);
        },
        reminders: [
          reminder('a', firedUpTo: _start),
          reminder('b', firedUpTo: _start),
          reminder('c', firedUpTo: _start),
        ],
      );
    });

    test('lưu, sửa và bật tắt coi mọi mốc trước giờ là đã xử lý', () {
      _run((h) {
        h.init();
        String? id;
        h.controller.newId().then((v) => id = v);
        h.async.flushMicrotasks();
        expect(id, 'id-1');

        // 09:00 has already passed today: saving must not ring for it.
        h.settle(
          h.controller.save(reminder(id!, hour: 9, repeat: RepeatRule.daily)),
        );
        expect(h.repo[id!]!.firedUpTo, _start);
        expect(h.controller.reminders.map((r) => r.id), [id]);
        h.tick(5);
        expect(h.controller.currentAlert, isNull);

        h.settle(h.controller.setEnabled(id!, false));
        expect(h.controller.reminders.single.enabled, isFalse);
        expect(h.repo[id!]!.firedUpTo, h.clock.now());
      });
    });

    test('lỗi đọc danh sách được giữ trong failure', () {
      _run((h) {
        h.repo.failure = const StorageFailure('disk');
        h.init();
        expect(h.controller.failure, const StorageFailure('disk'));
      });
    });
  });

  group('android: hệ điều hành giữ chuông', () {
    test('cứ 2 tick hỏi chuông native một lần, không tự tính lần báo', () {
      _run(
        (h) {
          h.init();
          h.tick(4);
          expect(h.callsOf('ringingPayload'), 2);
          expect(h.repo.saveAllCalls, isEmpty);
          expect(h.controller.currentAlert, isNull);
        },
        native: true,
        reminders: [reminder('a', firedUpTo: _start)],
      );
    });

    test('chuông native kêu thì hiện lần báo; bị tắt ngoài app thì đóng', () {
      _run(
        (h) {
          h.init();
          h.scheduler.ringing = _payload('a');
          h.tick(2);
          expect(h.currentId, 'a');
          expect(h.shown, 1);
          // The OS plays the tone, not the app.
          expect(h.ringer.calls, isEmpty);

          // Silenced with a volume key: the screen follows.
          h.scheduler.ringing = null;
          h.tick(2);
          expect(h.controller.currentAlert, isNull);
          expect(h.cleared, 1);
          expect(h.repo['a']!.enabled, isFalse);
          expect(h.callsOf('stopRinging'), 1);
        },
        native: true,
        reminders: [reminder('a', firedUpTo: _start)],
      );
    });

    test('tắt trong app thì khoảng im lặng sau đó không đóng lần báo kế', () {
      _run(
        (h) {
          h.init();
          h.scheduler.ringing = _payload('a');
          h.tick(2);
          h.settle(h.controller.showAlertFromPayload(_payload('b')));
          expect(h.currentId, 'a');

          h.settle(h.controller.dismissCurrent());
          expect(h.currentId, 'b');
          h.scheduler.ringing = null;
          h.tick(4);
          expect(h.currentId, 'b');
        },
        native: true,
        reminders: [reminder('a'), reminder('b')],
      );
    });

    test('mở từ thông báo thì hiện đúng lần báo; không có thì lấy chuông đang '
        'kêu', () {
      _run(
        (h) {
          h.scheduler.launch = _payload('a', isLead: true);
          h.settle(h.controller.showLaunchAlert());
          expect(h.currentId, 'a');
          expect(h.controller.currentAlert!.isLead, isTrue);
          expect(
            h.controller.currentAlert!.eventAt,
            DateTime(2026, 10, 22, 10, 15),
          );
        },
        native: true,
        reminders: [reminder('a', minute: 15, lead: 15)],
      );
      _run(
        (h) {
          h.scheduler.ringing = _payload('b');
          h.settle(h.controller.showLaunchAlert());
          expect(h.scheduler.calls, ['launchPayload', 'ringingPayload']);
          expect(h.currentId, 'b');
        },
        native: true,
        reminders: [reminder('b')],
      );
    });

    test('lưu thì nạp lại lịch báo OS với đúng tiêu đề, nội dung, payload', () {
      _run(
        (h) {
          h.init();
          h.settle(
            h.controller.save(
              reminder('a', title: 'Họp', note: ' phòng 3 ', lead: 5),
            ),
          );
          final ring = DateTime(2026, 10, 22, 10);
          final lead = DateTime(2026, 10, 22, 9, 55);
          expect(h.scheduler.scheduled.last, [
            ScheduledAlarm(
              id: 1,
              at: lead,
              title: 'Họp',
              body: 'Còn 5 phút nữa — bắt đầu lúc 10:00',
              payload: 'a|${lead.millisecondsSinceEpoch}|1',
            ),
            ScheduledAlarm(
              id: 2,
              at: ring,
              title: 'Họp',
              body: 'Đến giờ rồi — 10:00 · phòng 3',
              payload: 'a|${ring.millisecondsSinceEpoch}|0',
            ),
          ]);
        },
        start: t0,
        native: true,
      );
    });

    test('resync hỏi chuông đang kêu rồi nạp lại lịch', () {
      _run(
        (h) {
          h.init();
          h.scheduler.calls.clear();
          h.scheduler.ringing = _payload('a');
          h.settle(h.controller.resync());
          expect(h.scheduler.calls, ['ringingPayload', 'scheduleAll']);
          expect(h.currentId, 'a');
        },
        native: true,
        reminders: [reminder('a')],
      );
    });

    test('quyền và chuông thử đi qua scheduler; lỗi thì trả false', () {
      _run((h) {
        bool? exact;
        h.controller.canScheduleExactAlarms().then((v) => exact = v);
        h.settle(h.controller.requestPermissions());
        h.settle(h.controller.testRing());
        expect(exact, isTrue);
        expect(h.scheduler.calls, [
          'canScheduleExactAlarms',
          'requestPermissions',
          'testRing',
        ]);

        h.scheduler.failure = const UnexpectedFailure('channel');
        bool? overlays;
        h.controller.canDrawOverlays().then((v) => overlays = v);
        h.async.flushMicrotasks();
        expect(overlays, isFalse);
        expect(h.controller.failure, const UnexpectedFailure('channel'));
      }, native: true);
    });
  });

  group('danh sách và câu tóm tắt', () {
    test(
      'tách nhắc nhở với deadline; deadline gần nhất trước, quá hạn cuối',
      () {
        _run(
          (h) {
            h.init();
            expect(h.controller.plainReminders.map((r) => r.id), ['r']);
            expect(h.controller.deadlines.map((r) => r.id), [
              'soon',
              'later',
              'past',
            ]);
          },
          reminders: [
            reminder('later', isDeadline: true, date: DateTime(2026, 10, 30)),
            reminder('past', isDeadline: true, hour: 8),
            reminder('r'),
            reminder('soon', isDeadline: true, date: DateTime(2026, 10, 23)),
          ],
        );
      },
    );

    test('lần báo kế tiếp', () {
      _run((h) {
        h.init();
        expect(
          h.controller.nextAlertSummary(),
          'Chưa có nhắc nhở nào đang bật',
        );
        h.settle(h.controller.save(reminder('a', hour: 14, minute: 5)));
        expect(
          h.controller.nextAlertSummary(),
          'Lần báo kế tiếp: 22/10/2026 14:05',
        );
      });
    });

    test('deadline gần nhất còn hạn', () {
      _run(
        (h) {
          h.init();
          expect(
            h.controller.nearestDeadlineSummary(),
            'Nộp báo cáo: còn 2 ngày 03:00:00',
          );
        },
        start: t0,
        reminders: [
          reminder('past', isDeadline: true, hour: 8),
          reminder(
            'd',
            title: 'Nộp báo cáo',
            isDeadline: true,
            date: DateTime(2026, 10, 24),
            hour: 12,
            minute: 30,
          ),
        ],
      );
      _run((h) {
        h.init();
        expect(h.controller.nearestDeadlineSummary(), isNull);
      }, reminders: [reminder('past', isDeadline: true, hour: 8)]);
    });

    test('reminderById', () {
      _run((h) {
        h.init();
        expect(
          h.controller.reminderById('a')?.time,
          TimeOfDay(hour: 10, minute: 0),
        );
        expect(h.controller.reminderById('x'), isNull);
      }, reminders: [reminder('a')]);
    });
  });
}
