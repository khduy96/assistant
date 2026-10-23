import 'dart:io';

import 'package:event_notice/app/di/bridges/linked_reminder_bridge.dart';
import 'package:event_notice/app/di/bridges/todo_reminder_editor_bridge.dart';
import 'package:event_notice/app/di/injection.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/time_of_day.dart' as core;
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:event_notice/features/todos/data/datasources/todo_local_data_source.dart';
import 'package:event_notice/features/todos/data/repositories/todo_repository_impl.dart';
import 'package:event_notice/features/todos/data/sync/todo_sync_collection.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/repositories/linked_reminder_repository.dart';
import 'package:event_notice/features/todos/domain/repositories/todo_repository.dart';
import 'package:event_notice/features/todos/domain/usecases/add_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/find_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/get_todos.dart';
import 'package:event_notice/features/todos/domain/usecases/save_todo.dart';
import 'package:event_notice/features/todos/presentation/todo_reminder_editor.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:event_notice/features/todos/todos_injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import '../reminders/domain/fakes.dart' as reminders;
import '../reminders/presentation/fixture.dart' show controllerFor;
import 'domain/fakes.dart';

/// A reminders controller over an empty in-memory list, ringing in the app
/// as on desktop. Disposed after the test.
RemindersController remindersController() {
  final controller = controllerFor(
    reminders.InMemoryReminderRepository(),
    clock: reminders.FakeClock(DateTime(2026, 10, 22, 9, 30)),
    scheduler: reminders.FakeAlarmScheduler(ringsNatively: false),
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  group('configureDependencies', () {
    test('đăng ký đủ todos', () {
      configureDependencies(sl);
      final controller = sl<TodosController>();
      addTearDown(controller.dispose);

      expect(controller, isA<TodosController>());
      expect(sl<TodoSyncCollection>().className, 'TodoItem');
    });

    test('hai cầu nối nhắc nhở dùng chung một RemindersController', () {
      configureDependencies(sl);

      expect(sl<LinkedReminderRepository>(), isA<LinkedReminderBridge>());
      expect(sl<TodoReminderEditor>(), isA<TodoReminderEditorBridge>());
      expect(sl<RemindersController>(), same(sl<RemindersController>()));
    });
  });

  group('registerTodos', () {
    late FakeLinkedReminderRepository links;

    setUp(() {
      links = FakeLinkedReminderRepository();
      sl
        ..registerSingleton<Clock>(FakeClock(DateTime(2026, 10, 22, 9, 30)))
        ..registerSingleton<IdGenerator>(SequentialIdGenerator())
        ..registerSingleton<LinkedReminderRepository>(links);
      registerTodos(sl);
    });

    test('một repository duy nhất, thấy dưới cả hai kiểu', () {
      expect(sl<TodoRepository>(), same(sl<TodoRepositoryImpl>()));
    });

    test('use case và collection là singleton', () {
      expect(sl<GetTodos>(), same(sl<GetTodos>()));
      expect(sl<AddTodo>(), same(sl<AddTodo>()));
      expect(sl<SaveTodo>(), same(sl<SaveTodo>()));
      expect(sl<FindLinkedReminder>(), same(sl<FindLinkedReminder>()));
      expect(sl<TodoSyncCollection>(), same(sl<TodoSyncCollection>()));
    });

    test('mỗi lần lấy controller là một controller mới', () {
      final a = sl<TodosController>();
      final b = sl<TodosController>();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a, isNot(same(b)));
    });

    test('thêm việc qua controller thì collection thấy bản cần đẩy và báo '
        'thay đổi local', () async {
      final dir = await Directory.systemTemp.createTemp('todos_injection');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/todos.json';
      // Trỏ file việc cần làm vào thư mục tạm, phần còn lại giữ như đăng ký.
      sl
        ..unregister<TodoLocalDataSource>()
        ..registerLazySingleton(() => TodoLocalDataSource(sl(), path: path));

      final repo = sl<TodoRepositoryImpl>();
      final collection = sl<TodoSyncCollection>();
      final controller = sl<TodosController>();
      addTearDown(controller.dispose);
      await repo.init();
      await controller.init();

      var localChanges = 0;
      final sub = collection.localChanges.listen((_) => localChanges++);
      addTearDown(sub.cancel);

      await controller.add('  mua sữa  ');

      expect(controller.failure, isNull);
      expect(controller.todos.single.title, 'mua sữa');
      expect((await collection.dirtyRecords()).single.localId, 'id-1');
      expect(localChanges, 1);
      expect(await File(path).readAsString(), contains('"mua sữa"'));
    });

    test('controller tra nhắc nhở liên kết qua port đã đăng ký', () async {
      final dir = await Directory.systemTemp.createTemp('todos_injection');
      addTearDown(() => dir.delete(recursive: true));
      sl
        ..unregister<TodoLocalDataSource>()
        ..registerLazySingleton(
          () => TodoLocalDataSource(sl(), path: '${dir.path}/todos.json'),
        );
      final controller = sl<TodosController>();
      addTearDown(controller.dispose);
      await sl<TodoRepositoryImpl>().init();
      await controller.init();
      await controller.add('gọi khách');

      final todo = controller.todos.single;
      await controller.removeReminder(todo, 'r1');

      expect(links.removed, ['r1']);
    });
  });

  group('LinkedReminderBridge', () {
    test('id không có thì trả Ok(null), bật tắt không lỗi', () async {
      final bridge = LinkedReminderBridge(remindersController());

      final found = await bridge.find('r404');
      expect(found.isOk, isTrue);
      expect(found.valueOrNull, isNull);
      expect((await bridge.setEnabled('r404', false)).isOk, isTrue);
    });

    test('changes báo theo RemindersController và thôi nghe khi huỷ', () async {
      final store = remindersController();
      final bridge = LinkedReminderBridge(store);

      var events = 0;
      final sub = bridge.changes.listen((_) => events++);
      await store.resync();
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);

      await sub.cancel();
      await store.resync();
      await Future<void>.delayed(Duration.zero);
      expect(events, 1);
    });
  });

  group('TodoReminderEditorBridge', () {
    testWidgets('mở form nhắc nhở điền sẵn từ draft, huỷ thì không lưu gì', (
      tester,
    ) async {
      final store = remindersController();
      final bridge = TodoReminderEditorBridge(store);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = bridge.createFromDraft(
        context,
        ReminderDraft(
          title: 'Gửi báo giá',
          note: 'kèm bảng chiết khấu',
          date: DateTime(2026, 10, 23),
          time: core.TimeOfDay(hour: 9, minute: 15),
          leadMinutes: 60,
          isDeadline: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thêm deadline'), findsOneWidget);
      expect(find.text('Gửi báo giá'), findsOneWidget);
      expect(find.text('kèm bảng chiết khấu'), findsOneWidget);
      expect(find.text('09:15'), findsOneWidget);

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(store.reminders, isEmpty);
    });

    testWidgets('mở nhắc nhở không còn thì không hiện gì', (tester) async {
      final bridge = TodoReminderEditorBridge(remindersController());
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );

      await bridge.open(context, 'r404');
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });
  });
}
