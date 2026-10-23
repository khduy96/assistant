import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

void main() {
  late FakeClock clock;
  late InMemoryTodoRepository repo;
  late FakeLinkedReminderRepository links;
  late TodosController controller;

  Future<void> start({
    List<Todo> todos = const [],
    List<LinkedReminder> reminders = const [],
  }) async {
    repo = InMemoryTodoRepository(todos);
    links = FakeLinkedReminderRepository(reminders);
    controller = controllerFor(repo, links, clock: clock);
    await controller.init();
  }

  setUp(() => clock = FakeClock(t0));

  tearDown(() async {
    controller.dispose();
    await repo.dispose();
    await links.dispose();
  });

  test(
    'init tải danh sách theo thứ tự hiển thị và tách việc còn/xong',
    () async {
      await start(
        todos: [
          todo('done', done: true, completedAt: at(5)),
          todo('normal', createdMin: 1),
          todo('high', priority: TodoPriority.high, createdMin: 2),
        ],
      );

      expect(controller.todos.map((t) => t.id), ['high', 'normal', 'done']);
      expect(controller.open.map((t) => t.id), ['high', 'normal']);
      expect(controller.done.map((t) => t.id), ['done']);
      expect(controller.remaining, 2);
    },
  );

  test('linkedOf trả nhắc nhở còn tồn tại, null khi đã bị xoá', () async {
    await start(
      todos: [
        todo('a', reminderId: 'r1'),
        todo('b', reminderId: 'gone'),
        todo('c'),
      ],
      reminders: [linked('r1', next: at(60))],
    );

    expect(controller.linkedOf(controller.todoById('a')!)?.id, 'r1');
    expect(controller.linkedOf(controller.todoById('b')!), isNull);
    expect(controller.linkedOf(controller.todoById('c')!), isNull);
  });

  test('thay đổi từ repository (vd. sync) được tải lại', () async {
    await start();
    var notified = 0;
    controller.addListener(() => notified++);

    await repo.save(todo('x', title: 'Từ máy khác'));
    await pumpEventQueue();

    expect(controller.todos.single.title, 'Từ máy khác');
    expect(notified, greaterThan(0));
  });

  test('nhắc nhở đổi thì tra lại nhắc nhở liên kết và báo listener', () async {
    await start(
      todos: [todo('a', reminderId: 'r1')],
      reminders: [linked('r1', next: at(60))],
    );
    var notified = 0;
    controller.addListener(() => notified++);

    await links.setEnabled('r1', false);
    links.changesController.add(null);
    await pumpEventQueue();

    expect(controller.linkedOf(controller.todos.single)?.enabled, isFalse);
    expect(notified, greaterThan(0));
  });

  test(
    'nhắc nhở đổi mà không việc nào có liên kết thì không rebuild',
    () async {
      await start(todos: [todo('a')]);
      var notified = 0;
      controller.addListener(() => notified++);

      links.changesController.add(null);
      await pumpEventQueue();

      expect(notified, 0);
    },
  );

  test('now() lấy từ Clock', () async {
    await start();
    clock.current = at(30);
    expect(controller.now(), at(30));
  });

  test('add cắt khoảng trắng, bỏ qua tiêu đề rỗng', () async {
    await start();

    await controller.add('   ');
    expect(repo.writes, 0);

    await controller.add('  Gọi điện  ');
    expect(controller.todos.single.title, 'Gọi điện');
    expect(controller.todos.single.createdAt, t0);
  });

  test('save đóng dấu updatedAt theo Clock', () async {
    await start(todos: [todo('a')]);
    clock.current = at(10);

    await controller.save(controller.todos.single.copyWith(title: 'Mới'));

    expect(repo['a']!.title, 'Mới');
    expect(repo['a']!.updatedAt, at(10));
    expect(controller.todos.single.title, 'Mới');
  });

  group('setDone', () {
    test('tick xong thì tắt nhắc nhở liên kết, bỏ tick thì bật lại', () async {
      await start(
        todos: [todo('a', reminderId: 'r1')],
        reminders: [linked('r1', next: at(60))],
      );

      await controller.setDone(controller.todos.single, true);
      expect(repo['a']!.done, isTrue);
      expect(repo['a']!.completedAt, t0);
      expect(links.enabledCalls, [('r1', false)]);

      await controller.setDone(controller.todos.single, false);
      expect(repo['a']!.done, isFalse);
      expect(repo['a']!.completedAt, isNull);
      expect(links.enabledCalls, [('r1', false), ('r1', true)]);
    });

    test('nhắc nhở đã đúng trạng thái thì không gọi setEnabled', () async {
      await start(
        todos: [todo('a', reminderId: 'r1')],
        reminders: [linked('r1', enabled: false)],
      );

      await controller.setDone(controller.todos.single, true);

      expect(repo['a']!.done, isTrue);
      expect(links.enabledCalls, isEmpty);
    });

    test('dùng bản mới nhất của việc, không ghi đè bằng bản cũ', () async {
      await start(todos: [todo('a', title: 'Cũ')]);
      final stale = controller.todos.single;
      await repo.save(stale.copyWith(title: 'Sync đổi'));
      await pumpEventQueue();

      await controller.setDone(stale, true);

      expect(repo['a']!.title, 'Sync đổi');
      expect(repo['a']!.done, isTrue);
    });

    test('việc đã bị xoá thì không ghi lại', () async {
      await start(todos: [todo('a')]);
      final gone = controller.todos.single;
      await repo.delete('a');
      await pumpEventQueue();
      final writes = repo.writes;

      await controller.setDone(gone, true);

      expect(repo.writes, writes);
      expect(repo.length, 0);
    });
  });

  test('linkReminder ghi liên kết, null thì gỡ', () async {
    await start(todos: [todo('a')]);

    await controller.linkReminder(controller.todos.single, 'r9');
    expect(repo['a']!.reminderId, 'r9');

    await controller.linkReminder(controller.todos.single, null);
    expect(repo['a']!.reminderId, isNull);
  });

  test('removeReminder xoá nhắc nhở rồi gỡ liên kết, việc vẫn còn', () async {
    await start(
      todos: [todo('a', reminderId: 'r1')],
      reminders: [linked('r1')],
    );

    await controller.removeReminder(controller.todos.single, 'r1');

    expect(links.removed, ['r1']);
    expect(repo['a']!.reminderId, isNull);
    expect(controller.todos.single.id, 'a');
  });

  test('removeReminder lỗi thì giữ liên kết và ghi nhận failure', () async {
    await start(
      todos: [todo('a', reminderId: 'r1')],
      reminders: [linked('r1')],
    );
    links.failure = const StorageFailure('hỏng');

    await controller.removeReminder(controller.todos.single, 'r1');

    expect(repo['a']!.reminderId, 'r1');
    expect(controller.failure, const StorageFailure('hỏng'));
  });

  test('findLinked tra lại ngay, Ok(null) khi nhắc nhở đã bị xoá', () async {
    await start(
      todos: [todo('a', reminderId: 'r1')],
      reminders: [linked('r1')],
    );
    expect(
      (await controller.findLinked(controller.todos.single)).valueOrNull?.id,
      'r1',
    );

    await links.remove('r1');

    expect(
      await controller.findLinked(controller.todos.single),
      const Ok<LinkedReminder?>(null),
    );
  });

  test('clearDone trả số việc đã xoá, 0 khi không có', () async {
    await start(
      todos: [
        todo('a', done: true, completedAt: at(1)),
        todo('b', done: true, completedAt: at(2)),
        todo('c'),
      ],
    );

    expect(await controller.clearDone(), 2);
    expect(controller.todos.map((t) => t.id), ['c']);
    expect(await controller.clearDone(), 0);
  });

  test(
    'draftReminder: không có hạn thì 08:00 ngày mai, deadline báo trước 60',
    () async {
      await start(
        todos: [todo('a', title: 'Nộp hồ sơ', note: 'bản gốc')],
      );

      final draft = await controller.draftReminder(
        controller.todos.single,
        deadline: true,
      );

      expect(
        draft,
        ReminderDraft(
          title: 'Nộp hồ sơ',
          note: 'bản gốc',
          date: DateTime(2026, 10, 23),
          time: TimeOfDay(hour: 8, minute: 0),
          leadMinutes: 60,
          isDeadline: true,
        ),
      );
    },
  );

  test('newId lấy id từ use case', () async {
    await start();
    expect(await controller.newId(), 'id-1');
  });

  test('ghi lỗi thì giữ danh sách cũ và ghi nhận failure', () async {
    await start(todos: [todo('a')]);
    repo.failure = const StorageFailure('đọc lỗi');

    await controller.add('c');

    expect(controller.failure, const StorageFailure('đọc lỗi'));
    expect(controller.todos.map((t) => t.id), ['a']);
  });

  test('dispose rồi thì sự kiện không còn báo listener', () async {
    await start();
    var notified = 0;
    controller.addListener(() => notified++);
    controller.dispose();

    await repo.save(todo('x'));
    links.changesController.add(null);
    await pumpEventQueue();

    expect(notified, 0);
    // tearDown disposes again; a fresh one keeps that harmless.
    controller = controllerFor(repo, links, clock: clock);
  });

  group('repository phát sự kiện bất đồng bộ', () {
    late SlowTodoRepository slow;

    setUp(() async {
      repo = InMemoryTodoRepository();
      links = FakeLinkedReminderRepository();
      slow = SlowTodoRepository(repo);
      controller = controllerFor(slow, links, clock: clock);
      await controller.init();
    });

    tearDown(() => slow.dispose());

    test('add trả về khi danh sách đã cập nhật', () async {
      await controller.add('Một');
      expect(controller.todos.map((t) => t.title), ['Một']);

      await controller.add('Hai');
      expect(controller.todos.map((t) => t.title), ['Một', 'Hai']);
    });

    test('setDone và clearDone trả về khi danh sách đã cập nhật', () async {
      await controller.add('Một');
      await controller.setDone(controller.todos.single, true);
      expect(controller.done.single.title, 'Một');

      expect(await controller.clearDone(), 1);
      expect(controller.todos, isEmpty);
    });
  });
}
