import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/reminders/domain/entities/alarm_payload.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// A deadline on 24/10/2026 at 12:30, two days after [t0].
Reminder _deadline(String id, {String? title}) => reminder(
  id,
  title: title,
  isDeadline: true,
  date: DateTime(2026, 10, 24),
  hour: 12,
  minute: 30,
);

/// A controller over fakes, run in fake time that never moves on its own, so
/// the ticker stays out of the way.
class _Harness {
  _Harness(
    this.async, {
    required bool native,
    required List<Reminder> reminders,
    Map<String, List<String>> open = const {},
  }) : repo = InMemoryReminderRepository(reminders),
       scheduler = FakeAlarmScheduler(ringsNatively: native),
       todos = FakeLinkedTodos(open) {
    controller = controllerFor(
      repo,
      clock: FakeClock(t0),
      scheduler: scheduler,
      ringer: ringer,
      linkedTodos: todos,
    );
  }

  final FakeAsync async;
  final InMemoryReminderRepository repo;
  final FakeAlarmScheduler scheduler;
  final FakeAlarmRinger ringer = FakeAlarmRinger();
  final FakeLinkedTodos todos;
  late final RemindersController controller;

  /// Runs [action] and everything it started to the end, and returns what it
  /// gave back.
  T settle<T>(Future<T> action) {
    late T value;
    action.then((v) => value = v);
    async.flushMicrotasks();
    return value;
  }

  /// Reminder ids in the last schedule handed to the OS.
  List<String> get scheduledIds => [
    for (final a in scheduler.scheduled.last)
      parseAlarmPayload(a.payload)!.reminderId,
  ];
}

/// Runs [body] in fake time, then disposes the controller.
void _run(
  void Function(_Harness h) body, {
  bool native = false,
  List<Reminder> reminders = const [],
  Map<String, List<String>> open = const {},
}) {
  fakeAsync((async) {
    final h = _Harness(async, native: native, reminders: reminders, open: open);
    h.settle(h.controller.init());
    body(h);
    h.controller.dispose();
    async.flushMicrotasks();
  });
}

void main() {
  group('openLinkedTodoTitles', () {
    test('trả tên các việc chưa xong trỏ tới deadline', () {
      _run(
        (h) {
          expect(h.settle(h.controller.openLinkedTodoTitles('d')), [
            'Viết báo cáo',
            'Gửi mail',
          ]);
          expect(h.settle(h.controller.openLinkedTodoTitles('x')), isEmpty);
          expect(h.controller.failure, isNull);
        },
        reminders: [_deadline('d')],
        open: {
          'd': ['Viết báo cáo', 'Gửi mail'],
        },
      );
    });

    test('đọc lỗi thì trả rỗng và ghi lỗi', () {
      _run(
        (h) {
          const failure = StorageFailure('todos.json hỏng');
          h.todos.failure = failure;

          expect(h.settle(h.controller.openLinkedTodoTitles('d')), isEmpty);
          expect(h.controller.failure, same(failure));
        },
        reminders: [_deadline('d')],
        open: {
          'd': ['Viết báo cáo'],
        },
      );
    });
  });

  group('markDone', () {
    test('không có việc liên kết: gỡ deadline khỏi repo và danh sách, đặt '
        'lại lịch OS, tooltip không còn nhắc tới nó (AC4)', () {
      _run(
        (h) {
          expect(h.scheduledIds, containsAll(['d', 'r']));
          expect(
            h.controller.nearestDeadlineSummary(),
            startsWith('Nộp báo cáo: còn'),
          );
          final schedules = h.scheduler.scheduled.length;

          expect(h.settle(h.controller.markDone('d')), MarkDoneResult.done);

          expect(h.todos.completed, ['d']);
          expect(h.repo['d'], isNull);
          expect(h.repo['r'], isNotNull);
          expect(h.controller.deadlines, isEmpty);
          expect(h.controller.reminderById('d'), isNull);
          expect(h.scheduler.scheduled.length, greaterThan(schedules));
          expect(h.scheduledIds, ['r']);
          expect(h.controller.nearestDeadlineSummary(), isNull);
          expect(h.controller.failure, isNull);
        },
        native: true,
        reminders: [
          _deadline('d', title: 'Nộp báo cáo'),
          reminder('r', hour: 14),
        ],
      );
    });

    test('có việc liên kết: tick việc trước rồi gỡ deadline', () {
      _run(
        (h) {
          expect(h.settle(h.controller.markDone('d')), MarkDoneResult.done);

          expect(h.todos.completed, ['d']);
          expect(h.todos.open, isEmpty);
          expect(h.repo['d'], isNull);
          expect(h.controller.deadlines, isEmpty);
        },
        reminders: [_deadline('d')],
        open: {
          'd': ['Viết báo cáo'],
        },
      );
    });

    test('deadline đang có lần báo trong hàng đợi: bỏ lần báo, tắt chuông '
        '(AC12)', () {
      _run((h) {
        h.settle(
          h.controller.showAlertFromPayload(
            AlarmPayload(
              reminderId: 'd',
              at: DateTime(2026, 10, 24, 12, 30),
              isLead: false,
            ).encode(),
          ),
        );
        expect(h.controller.currentAlert?.reminder.id, 'd');

        expect(h.settle(h.controller.markDone('d')), MarkDoneResult.done);

        expect(h.controller.currentAlert, isNull);
        expect(h.ringer.calls, contains('stop'));
        expect(h.repo['d'], isNull);
      }, reminders: [_deadline('d')]);
    });

    test('tick việc lỗi: báo todosNotTicked, deadline còn nguyên, không xoá '
        'gì (AC11)', () {
      _run(
        (h) {
          const failure = StorageFailure('không ghi được todos.json');
          h.todos.failure = failure;
          final writes = h.repo.writes;
          final schedules = h.scheduler.scheduled.length;

          expect(
            h.settle(h.controller.markDone('d')),
            MarkDoneResult.todosNotTicked,
          );

          expect(h.todos.completed, ['d']);
          expect(h.repo.writes, writes);
          expect(h.repo['d'], isNotNull);
          expect(h.controller.reminderById('d'), isNotNull);
          expect(h.controller.deadlines.single.id, 'd');
          expect(h.scheduler.scheduled.length, schedules);
          expect(h.controller.failure, same(failure));
        },
        native: true,
        reminders: [_deadline('d')],
        open: {
          'd': ['Viết báo cáo'],
        },
      );
    });

    test('tick việc xong mà xoá deadline lỗi: không báo thành công, ghi '
        'lỗi, không đặt lại lịch OS', () {
      _run(
        (h) {
          const failure = StorageFailure('không ghi được reminders.json');
          h.repo.writeFailure = failure;
          final schedules = h.scheduler.scheduled.length;

          expect(
            h.settle(h.controller.markDone('d')),
            MarkDoneResult.deadlineNotRemoved,
          );

          expect(h.todos.completed, ['d']);
          expect(h.todos.open, isEmpty);
          expect(h.repo['d'], isNotNull);
          expect(h.scheduler.scheduled.length, schedules);
          expect(h.controller.failure, same(failure));
        },
        native: true,
        reminders: [_deadline('d')],
        open: {
          'd': ['Viết báo cáo'],
        },
      );
    });
  });

  group('remove', () {
    test('trả true khi xoá được, false khi không lưu được', () {
      _run((h) {
        expect(h.settle(h.controller.remove('a')), isTrue);
        expect(h.repo['a'], isNull);

        h.repo.writeFailure = const StorageFailure('disk');
        expect(h.settle(h.controller.remove('b')), isFalse);
        expect(h.repo['b'], isNotNull);
      }, reminders: [reminder('a', hour: 9), reminder('b', hour: 10)]);
    });
  });
}
