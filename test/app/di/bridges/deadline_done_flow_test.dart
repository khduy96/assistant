import 'package:event_notice/app/di/bridges/linked_reminder_bridge.dart';
import 'package:event_notice/app/di/bridges/linked_todos_bridge.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/usecases/complete_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/find_open_todos_linked_to.dart';
import 'package:event_notice/features/todos/domain/usecases/set_todo_done.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../features/reminders/domain/fakes.dart' as rf;
import '../../../features/reminders/presentation/fixture.dart' as rfx;
import '../../../features/todos/domain/fakes.dart' as tf;
import '../../../features/todos/presentation/fixture.dart' as tfx;

/// When the deadline is marked done, a day after both fixtures' `t0`.
final _t1 = rfx.t0.add(const Duration(days: 1, hours: 2));

/// A deadline on 24/10/2026 at 12:30, two days after `t0`.
Reminder _deadline(String id, {String? title}) => rfx.reminder(
  id,
  title: title,
  isDeadline: true,
  date: DateTime(2026, 10, 24),
  hour: 12,
  minute: 30,
);

/// Lets the streams and the reloads they start run to the end: every store
/// here answers in microtasks, so one turn of the event loop drains them.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Both features as the app wires them: the reminders' controller ticks the
/// todos off through [LinkedTodosBridge], the todos' controller reaches the
/// deadlines through [LinkedReminderBridge], and both see the same
/// [todoRepo].
class _World {
  _World({required List<Reminder> reminders, required List<Todo> todos})
    : reminderRepo = rf.InMemoryReminderRepository(reminders),
      todoRepo = tf.InMemoryTodoRepository(todos) {
    final findOpen = FindOpenTodosLinkedTo(todoRepo);
    remindersController = rfx.controllerFor(
      reminderRepo,
      clock: clock,
      scheduler: scheduler,
      linkedTodos: LinkedTodosBridge(
        findOpen,
        CompleteTodosLinkedTo(
          findOpen,
          SetTodoDone(todoRepo, clock),
          todoRepo,
          clock,
        ),
      ),
    );
    todosController = tfx.controllerFor(
      todoRepo,
      LinkedReminderBridge(remindersController),
      clock: clock,
    );
  }

  final rf.FakeClock clock = rf.FakeClock(rfx.t0);
  final rf.FakeAlarmScheduler scheduler = rf.FakeAlarmScheduler(
    ringsNatively: false,
  );
  final rf.InMemoryReminderRepository reminderRepo;
  final tf.InMemoryTodoRepository todoRepo;
  late final RemindersController remindersController;
  late final TodosController todosController;

  Future<void> init() async {
    await remindersController.init();
    await todosController.init();
    await _settle();
  }

  Future<void> dispose() async {
    todosController.dispose();
    remindersController.dispose();
    await _settle();
    await todoRepo.dispose();
    await reminderRepo.dispose();
  }
}

void main() {
  late _World world;

  RemindersController reminders() => world.remindersController;
  TodosController todos() => world.todosController;

  /// Builds both features over [reminders] and [todos] and loads them.
  Future<void> start({
    List<Reminder> reminders = const [],
    List<Todo> todos = const [],
  }) async {
    world = _World(reminders: reminders, todos: todos);
    addTearDown(world.dispose);
    await world.init();
  }

  group('Đã thực hiện trên deadline', () {
    test('việc liên kết thành đã xong, deadline bị gỡ, tab Việc cần làm cập '
        'nhật (AC6)', () async {
      await start(
        reminders: [_deadline('d', title: 'Nộp báo cáo')],
        todos: [
          tfx.todo('a', title: 'Nộp báo cáo', reminderId: 'd'),
          tfx.todo('b', title: 'Việc khác'),
        ],
      );
      expect(todos().remaining, 2);
      expect(todos().done, isEmpty);
      expect(todos().linkedOf(todos().todoById('a')!)?.isDeadline, isTrue);
      world.clock.current = _t1;

      expect(await reminders().markDone('d'), MarkDoneResult.done);
      await _settle();

      final a = world.todoRepo['a']!;
      expect(a.done, isTrue);
      expect(a.completedAt, _t1);
      expect(a.updatedAt, _t1);
      expect(world.todoRepo['b']!.done, isFalse);
      expect(world.reminderRepo['d'], isNull);
      expect(reminders().deadlines, isEmpty);
      expect(reminders().failure, isNull);
      expect(todos().done.map((t) => t.id), ['a']);
      expect(todos().remaining, 1);
      expect(todos().failure, isNull);
    });

    test('việc liên kết đã xong từ trước thì giữ nguyên, deadline vẫn bị gỡ '
        '(AC8)', () async {
      final before = tfx.todo(
        'a',
        done: true,
        completedAt: tfx.at(-60),
        reminderId: 'd',
      );
      await start(reminders: [_deadline('d')], todos: [before]);
      final writes = world.todoRepo.writes;
      world.clock.current = _t1;

      expect(await reminders().markDone('d'), MarkDoneResult.done);
      await _settle();

      expect(world.todoRepo['a'], before);
      expect(world.todoRepo.writes, writes);
      expect(world.reminderRepo['d'], isNull);
      expect(reminders().deadlines, isEmpty);
      expect(reminders().failure, isNull);
    });

    test(
      'việc liên kết đã bị xoá thì vẫn gỡ deadline, không lỗi (AC9)',
      () async {
        await start(
          reminders: [_deadline('d')],
          todos: [tfx.todo('a', reminderId: 'd')],
        );
        await todos().remove('a');
        expect(world.todoRepo['a'], isNull);

        expect(await reminders().markDone('d'), MarkDoneResult.done);
        await _settle();

        expect(world.reminderRepo['d'], isNull);
        expect(reminders().deadlines, isEmpty);
        expect(reminders().failure, isNull);
        expect(todos().failure, isNull);
      },
    );

    test('không có việc nào trỏ tới deadline thì vẫn gỡ, không lỗi, không '
        'đụng việc khác (AC9)', () async {
      final other = tfx.todo('a', title: 'Không liên kết');
      await start(reminders: [_deadline('d')], todos: [other]);
      final writes = world.todoRepo.writes;

      expect(await reminders().markDone('d'), MarkDoneResult.done);
      await _settle();

      expect(world.reminderRepo['d'], isNull);
      expect(reminders().failure, isNull);
      expect(world.todoRepo['a'], other);
      expect(world.todoRepo.writes, writes);
    });

    test('bỏ tick việc sau khi đã thực hiện thì không lỗi, không còn liên kết, '
        'không tạo lại deadline (AC10)', () async {
      await start(
        reminders: [_deadline('d')],
        todos: [tfx.todo('a', reminderId: 'd')],
      );
      world.clock.current = _t1;
      expect(await reminders().markDone('d'), MarkDoneResult.done);
      await _settle();
      final remindersLeft = world.reminderRepo.length;
      expect(remindersLeft, 0);

      await todos().setDone(todos().todoById('a')!, false);
      await _settle();

      final a = todos().todoById('a')!;
      expect(todos().failure, isNull);
      expect(reminders().failure, isNull);
      expect(a.done, isFalse);
      expect(todos().linkedOf(a), isNull);
      expect(world.reminderRepo.length, remindersLeft);
      expect(reminders().reminders, isEmpty);
    });

    test(
      'không lưu được việc liên kết thì deadline còn nguyên (AC11)',
      () async {
        await start(
          reminders: [_deadline('d')],
          todos: [tfx.todo('a', reminderId: 'd')],
        );
        world.todoRepo.failure = const StorageFailure(
          'không ghi được todos.json',
        );
        final reminderWrites = world.reminderRepo.writes;

        expect(await reminders().markDone('d'), MarkDoneResult.todosNotTicked);
        await _settle();

        expect(reminders().failure, isA<StorageFailure>());
        expect(world.reminderRepo.writes, reminderWrites);
        expect(world.reminderRepo['d'], isNotNull);
        expect(reminders().deadlines.single.id, 'd');
        expect(world.todoRepo['a']!.done, isFalse);
      },
    );
  });

  group('tab Việc cần làm không đổi (AC14)', () {
    test('tick tay chỉ tắt deadline liên kết, deadline vẫn trong danh '
        'sách', () async {
      await start(
        reminders: [_deadline('d')],
        todos: [tfx.todo('a', reminderId: 'd')],
      );

      await todos().setDone(todos().todoById('a')!, true);
      await _settle();

      expect(todos().failure, isNull);
      expect(world.todoRepo['a']!.done, isTrue);
      expect(world.reminderRepo['d']?.enabled, isFalse);
      expect(reminders().deadlines.single.id, 'd');
      expect(reminders().deadlines.single.enabled, isFalse);
    });

    test('"Bỏ deadline" chỉ gỡ deadline, việc vẫn chưa xong', () async {
      await start(
        reminders: [_deadline('d')],
        todos: [tfx.todo('a', reminderId: 'd')],
      );

      await todos().removeReminder(todos().todoById('a')!, 'd');
      await _settle();

      expect(todos().failure, isNull);
      expect(world.reminderRepo['d'], isNull);
      final a = world.todoRepo['a']!;
      expect(a.done, isFalse);
      expect(a.reminderId, isNull);
    });
  });
}
