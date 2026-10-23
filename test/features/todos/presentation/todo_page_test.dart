import 'package:event_notice/core/domain/time_of_day.dart' as core;
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/presentation/pages/todo_page.dart';
import 'package:event_notice/features/todos/presentation/todos_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// The tab as the home page shows it, with a "Thêm việc" button that goes
/// through [addTodo] like the real floating button.
Widget _harness(TodosController controller, FakeTodoReminderEditor editor) =>
    ChangeNotifierProvider<TodosController>.value(
      value: controller,
      child: MaterialApp(
        home: Scaffold(
          body: TodoListView(reminderEditor: editor),
          floatingActionButton: Builder(
            builder: (context) => FloatingActionButton.extended(
              onPressed: () => addTodo(context),
              icon: const Icon(Icons.add_task),
              label: const Text('Thêm việc'),
            ),
          ),
        ),
      ),
    );

/// The card showing [title].
Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

/// Opens the "..." menu of the card showing [title] and picks [item].
Future<void> _menu(WidgetTester tester, String title, String item) async {
  await tester.tap(
    find.descendant(
      of: _card(title),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// The [i]-th text field of the open editor dialog.
Finder _field(int i) => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .at(i);

void main() {
  late FakeClock clock;
  late InMemoryTodoRepository repo;
  late FakeLinkedReminderRepository links;
  late FakeTodoReminderEditor editor;
  late TodosController controller;

  Future<void> pumpTab(
    WidgetTester tester, {
    List<Todo> todos = const [],
    List<LinkedReminder> reminders = const [],
  }) async {
    repo = InMemoryTodoRepository(todos);
    links = FakeLinkedReminderRepository(reminders);
    editor = FakeTodoReminderEditor();
    controller = controllerFor(repo, links, clock: clock);
    await controller.init();
    await tester.pumpWidget(_harness(controller, editor));
  }

  setUp(() => clock = FakeClock(t0));

  tearDown(() async {
    controller.dispose();
    await repo.dispose();
    await links.dispose();
  });

  testWidgets('chưa có việc thì hiện trạng thái trống', (tester) async {
    await pumpTab(tester);

    expect(find.text('Chưa có việc nào'), findsOneWidget);
    expect(
      find.text(
        'Gõ vào ô trên để thêm nhanh, hoặc bấm "Thêm việc" để đặt '
        'mức ưu tiên và hạn hoàn thành.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Còn '), findsNothing);
  });

  testWidgets('thêm nhanh bằng Enter, ô nhập được xoá và giữ con trỏ', (
    tester,
  ) async {
    await pumpTab(tester);

    await tester.enterText(find.byType(TextField), '  Mua sữa  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(repo['id-1']!.title, 'Mua sữa');
    expect(find.text('Mua sữa'), findsOneWidget);
    expect(find.text('Còn 1 việc · đã xong 0'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byTooltip('Thêm'));
    await tester.pumpAndSettle();
    expect(repo.length, 1);
  });

  testWidgets('chip ưu tiên, hạn và nhắc nhở hiện như cũ', (tester) async {
    await pumpTab(
      tester,
      todos: [
        todo(
          'a',
          title: 'Báo cáo',
          priority: TodoPriority.high,
          due: DateTime(2026, 10, 22, 8),
          reminderId: 'r1',
        ),
        todo(
          'b',
          title: 'Đọc sách',
          priority: TodoPriority.low,
          due: DateTime(2026, 10, 22),
          createdMin: 1,
        ),
        todo(
          'c',
          title: 'Xong rồi',
          done: true,
          completedAt: at(1),
          priority: TodoPriority.high,
          due: DateTime(2026, 10, 21),
        ),
      ],
      reminders: [linked('r1', next: at(120))],
    );

    expect(find.text('Quan trọng'), findsOneWidget); // not on the done item
    expect(find.text('Quá hạn 22/10/2026 08:00'), findsOneWidget);
    expect(find.text('Nhắc · còn 2 giờ'), findsOneWidget);
    expect(find.text('Thấp'), findsOneWidget);
    expect(find.text('Hôm nay'), findsOneWidget);
    expect(find.text('Còn 2 việc · đã xong 1'), findsOneWidget);
    expect(find.text('Đã xong'), findsOneWidget);
  });

  testWidgets('đếm ngược chạy theo nhịp của nhắc nhở', (tester) async {
    await pumpTab(
      tester,
      todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
      reminders: [linked('r1', isDeadline: true, next: at(120))],
    );
    expect(find.text('Deadline · còn 2 giờ'), findsOneWidget);

    clock.current = at(90);
    links.changesController.add(null);
    await tester.pumpAndSettle();

    expect(find.text('Deadline · còn 30 phút'), findsOneWidget);
  });

  group('chuyển thành nhắc nhở/deadline', () {
    testWidgets('nhắc nhở: draft đúng, liên kết và snackbar nguyên văn', (
      tester,
    ) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Gọi khách', note: 'số cũ')],
      );

      await _menu(tester, 'Gọi khách', 'Chuyển thành nhắc nhở');

      expect(editor.drafts, [
        ReminderDraft(
          title: 'Gọi khách',
          note: 'số cũ',
          date: DateTime(2026, 10, 23),
          time: core.TimeOfDay(hour: 8, minute: 0),
        ),
      ]);
      expect(repo['a']!.reminderId, 'r-new-1');
      expect(
        find.text('Đã tạo nhắc nhở cho "Gọi khách" — xem ở tab Nhắc nhở.'),
        findsOneWidget,
      );
    });

    testWidgets('deadline: giờ lấy từ hạn, báo trước 60 phút', (tester) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Nộp thuế', due: DateTime(2026, 10, 30, 17))],
      );

      await _menu(tester, 'Nộp thuế', 'Chuyển thành deadline');

      expect(editor.drafts, [
        ReminderDraft(
          title: 'Nộp thuế',
          date: DateTime(2026, 10, 30),
          time: core.TimeOfDay(hour: 17, minute: 0),
          leadMinutes: 60,
          isDeadline: true,
        ),
      ]);
      expect(repo['a']!.reminderId, 'r-new-1');
      expect(
        find.text('Đã tạo deadline cho "Nộp thuế" — xem ở tab Deadline.'),
        findsOneWidget,
      );
    });

    testWidgets('huỷ form thì không liên kết, không snackbar', (tester) async {
      await pumpTab(tester, todos: [todo('a', title: 'Gọi khách')]);
      editor.cancel = true;

      await _menu(tester, 'Gọi khách', 'Chuyển thành nhắc nhở');

      expect(editor.drafts, hasLength(1));
      expect(repo['a']!.reminderId, isNull);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('nhắc nhở đã liên kết', () {
    testWidgets('mở qua menu hoặc bấm chip', (tester) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
        reminders: [linked('r1', next: at(60))],
      );

      await _menu(tester, 'Báo cáo', 'Mở nhắc nhở đã tạo');
      expect(editor.opened, ['r1']);

      await tester.tap(find.text('Nhắc · còn 1 giờ'));
      await tester.pumpAndSettle();
      expect(editor.opened, ['r1', 'r1']);
    });

    testWidgets('menu của deadline dùng chữ "deadline"', (tester) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
        reminders: [linked('r1', isDeadline: true, next: at(60))],
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();

      expect(find.text('Mở deadline đã tạo'), findsOneWidget);
      expect(find.text('Bỏ deadline'), findsOneWidget);
      expect(find.text('Chuyển thành nhắc nhở'), findsNothing);
    });

    testWidgets('bỏ nhắc nhở: hỏi lại, xoá nhắc nhở rồi gỡ liên kết', (
      tester,
    ) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
        reminders: [linked('r1', title: 'Báo cáo quý', next: at(60))],
      );

      await _menu(tester, 'Báo cáo', 'Bỏ nhắc nhở');
      expect(find.text('Bỏ nhắc nhở?'), findsOneWidget);
      expect(
        find.text(
          '"Báo cáo quý" sẽ không báo nữa, việc vẫn còn trong danh sách.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Bỏ'));
      await tester.pumpAndSettle();

      expect(links.removed, ['r1']);
      expect(repo['a']!.reminderId, isNull);
      expect(find.text('Báo cáo'), findsOneWidget);
      expect(find.textContaining('Nhắc ·'), findsNothing);
    });

    testWidgets('bỏ deadline rồi huỷ thì không đổi gì', (tester) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
        reminders: [linked('r1', isDeadline: true, next: at(60))],
      );

      await _menu(tester, 'Báo cáo', 'Bỏ deadline');
      expect(find.text('Bỏ deadline?'), findsOneWidget);
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(links.removed, isEmpty);
      expect(repo['a']!.reminderId, 'r1');
    });

    testWidgets('nhắc nhở đã bị xoá ở nơi khác thì chỉ gỡ liên kết', (
      tester,
    ) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
        reminders: [linked('r1', next: at(60))],
      );

      // Deleted while the menu is open, before anything reloaded.
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await links.remove('r1');
      links.removed.clear();
      await tester.tap(find.text('Bỏ nhắc nhở'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(links.removed, isEmpty);
      expect(repo['a']!.reminderId, isNull);
    });

    testWidgets('liên kết tới nhắc nhở đã xoá thì thẻ coi như chưa chuyển', (
      tester,
    ) async {
      await pumpTab(
        tester,
        todos: [todo('a', title: 'Báo cáo', reminderId: 'gone')],
      );

      expect(find.textContaining('Nhắc ·'), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Chuyển thành nhắc nhở'), findsOneWidget);
      expect(find.text('Bỏ nhắc nhở'), findsNothing);
    });
  });

  testWidgets('tick xong thì tắt nhắc nhở liên kết, bỏ tick thì bật lại', (
    tester,
  ) async {
    await pumpTab(
      tester,
      todos: [todo('a', title: 'Báo cáo', reminderId: 'r1')],
      reminders: [linked('r1', next: at(60))],
    );

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(repo['a']!.done, isTrue);
    expect(links.enabledCalls, [('r1', false)]);
    expect(find.text('Còn 0 việc · đã xong 1'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(repo['a']!.done, isFalse);
    expect(links.enabledCalls, [('r1', false), ('r1', true)]);
    expect(find.text('Nhắc · còn 1 giờ'), findsOneWidget);
  });

  testWidgets('xoá việc hỏi lại trước', (tester) async {
    await pumpTab(tester, todos: [todo('a', title: 'Báo cáo')]);

    await _menu(tester, 'Báo cáo', 'Xoá');
    expect(find.text('Xoá việc này?'), findsOneWidget);
    expect(find.text('"Báo cáo" sẽ bị xoá khỏi danh sách.'), findsOneWidget);
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(repo['a'], isNotNull);

    await _menu(tester, 'Báo cáo', 'Xoá');
    await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
    await tester.pumpAndSettle();
    expect(repo['a'], isNull);
    expect(find.text('Chưa có việc nào'), findsOneWidget);
  });

  testWidgets('dọn việc đã xong hiện số việc đã xoá', (tester) async {
    await pumpTab(
      tester,
      todos: [
        todo('a', title: 'Một', done: true, completedAt: at(1)),
        todo('b', title: 'Hai', done: true, completedAt: at(2)),
        todo('c', title: 'Ba'),
      ],
    );

    await tester.tap(find.text('Dọn việc đã xong'));
    await tester.pumpAndSettle();

    expect(find.text('Đã xoá 2 việc đã xong.'), findsOneWidget);
    expect(repo.length, 1);
    expect(find.text('Dọn việc đã xong'), findsNothing);
  });

  group('editor', () {
    testWidgets('thêm việc: tiêu đề trống báo lỗi, lưu với id và giờ mới', (
      tester,
    ) async {
      await pumpTab(tester);

      await tester.tap(find.text('Thêm việc'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm việc cần làm'), findsOneWidget);

      await tester.tap(find.text('Lưu'));
      await tester.pump();
      expect(find.text('Hãy nhập việc cần làm.'), findsOneWidget);

      clock.current = at(5);
      await tester.enterText(_field(0), '  Gửi báo giá ');
      await tester.enterText(_field(1), ' gấp ');
      await tester.tap(find.text('Quan trọng'));
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['id-1']!;
      expect(saved.title, 'Gửi báo giá');
      expect(saved.note, 'gấp');
      expect(saved.priority, TodoPriority.high);
      expect(saved.dueDate, isNull);
      expect(saved.createdAt, at(5));
      expect(saved.updatedAt, at(5));
    });

    testWidgets('huỷ thì không lưu gì', (tester) async {
      await pumpTab(tester);

      await tester.tap(find.text('Thêm việc'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'Không lưu');
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(repo.writes, 0);
    });

    testWidgets(
      'sửa giữ trạng thái, liên kết và ngày tạo; bỏ hạn thì xoá hạn',
      (tester) async {
        await pumpTab(
          tester,
          todos: [
            todo(
              'a',
              title: 'Báo cáo',
              due: DateTime(2026, 10, 25, 14, 30),
              reminderId: 'r1',
              createdMin: -60,
            ),
          ],
        );

        await tester.tap(find.text('Báo cáo'));
        await tester.pumpAndSettle();
        expect(find.text('Sửa việc cần làm'), findsOneWidget);
        expect(find.text('25/10/2026'), findsOneWidget);
        expect(find.text('14:30'), findsOneWidget);

        await tester.tap(find.text('Bỏ giờ'));
        await tester.pump();
        expect(find.text('Cả ngày'), findsOneWidget);

        await tester.tap(find.byTooltip('Bỏ hạn'));
        await tester.pump();
        expect(find.text('Không đặt hạn'), findsOneWidget);

        clock.current = at(10);
        await tester.enterText(_field(0), 'Báo cáo quý');
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final saved = repo['a']!;
        expect(saved.title, 'Báo cáo quý');
        expect(saved.dueDate, isNull);
        expect(saved.reminderId, 'r1');
        expect(saved.createdAt, at(-60));
        expect(saved.updatedAt, at(10));
        expect(repo.length, 1);
      },
    );
  });
}
