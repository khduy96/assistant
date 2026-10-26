import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/reminders/presentation/pages/reminders_tab.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

const _snack =
    'Không đánh dấu xong được việc liên kết nên deadline vẫn được giữ.';

/// The card showing [title].
Finder _card(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(Card));

/// Opens the "..." menu of the card showing [title].
Future<void> _openMenu(WidgetTester tester, String title) async {
  await tester.tap(
    find.descendant(
      of: _card(title),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the "..." menu of the card showing [title] and picks "Đã thực hiện".
Future<void> _pickDone(WidgetTester tester, String title) async {
  await _openMenu(tester, title);
  await tester.tap(find.text('Đã thực hiện'));
  await tester.pumpAndSettle();
}

/// The "Đã thực hiện" button of the open confirmation dialog.
Finder get _confirm => find.widgetWithText(FilledButton, 'Đã thực hiện');

void main() {
  late InMemoryReminderRepository repo;
  late FakeLinkedTodos todos;
  late RemindersController controller;

  final deadline = reminder(
    'd',
    title: 'Nộp báo cáo',
    isDeadline: true,
    date: DateTime(2026, 10, 23),
    hour: 12,
  );

  Future<void> pumpTab(
    WidgetTester tester, {
    Map<String, List<String>> open = const {},
  }) async {
    repo = InMemoryReminderRepository([deadline]);
    todos = FakeLinkedTodos(open);
    controller = controllerFor(
      repo,
      clock: FakeClock(t0),
      scheduler: FakeAlarmScheduler(ringsNatively: false),
      linkedTodos: todos,
    );
    // The clock is pinned, so the ticks only repaint: keep them quiet.
    controller.uiActive = false;
    await controller.init();
    await tester.pumpWidget(
      ChangeNotifierProvider<RemindersController>.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: DeadlinesTab())),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A widget test that takes the tree down and stops the controller's
  /// ticker before the test ends, so no timer is left pending.
  void testTab(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testTab('menu chỉ có "Sửa" và "Đã thực hiện", không có "Xoá"', (
    tester,
  ) async {
    await pumpTab(tester);
    await _openMenu(tester, 'Nộp báo cáo');
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('Đã thực hiện'), findsOneWidget);
    expect(find.text('Xoá'), findsNothing);
  });

  testTab('hộp thoại nói rõ deadline sẽ được gỡ; không có việc liên kết', (
    tester,
  ) async {
    await pumpTab(tester);
    await _pickDone(tester, 'Nộp báo cáo');
    expect(find.text('Đánh dấu đã thực hiện?'), findsOneWidget);
    expect(
      find.text('"Nộp báo cáo" sẽ được gỡ khỏi danh sách deadline.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Huỷ'), findsOneWidget);
    expect(_confirm, findsOneWidget);
    expect(find.textContaining('sẽ được đánh dấu đã xong.'), findsNothing);
  });

  testTab('có việc liên kết đang mở thì hộp thoại kể tên từng việc', (
    tester,
  ) async {
    await pumpTab(
      tester,
      open: {
        'd': ['Viết báo cáo', 'Gửi chị Lan'],
        'other': ['Không liên quan'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');
    expect(
      find.text('Việc "Viết báo cáo" sẽ được đánh dấu đã xong.'),
      findsOneWidget,
    );
    expect(
      find.text('Việc "Gửi chị Lan" sẽ được đánh dấu đã xong.'),
      findsOneWidget,
    );
    expect(find.textContaining('Không liên quan'), findsNothing);
  });

  testTab('"Huỷ" thì không đổi gì', (tester) async {
    await pumpTab(
      tester,
      open: {
        'd': ['Viết báo cáo'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();

    expect(find.text('Đánh dấu đã thực hiện?'), findsNothing);
    expect(repo['d'], deadline);
    expect(repo.writes, 0);
    expect(todos.completed, isEmpty);
    expect(_card('Nộp báo cáo'), findsOneWidget);
  });

  testTab('chạm ra ngoài hộp thoại thì không đổi gì', (tester) async {
    await pumpTab(tester);
    await _pickDone(tester, 'Nộp báo cáo');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Đánh dấu đã thực hiện?'), findsNothing);
    expect(repo['d'], deadline);
    expect(repo.writes, 0);
    expect(todos.completed, isEmpty);
    expect(_card('Nộp báo cáo'), findsOneWidget);
  });

  testTab('xác nhận thì đánh dấu xong việc liên kết rồi gỡ thẻ', (
    tester,
  ) async {
    await pumpTab(
      tester,
      open: {
        'd': ['Viết báo cáo'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    expect(todos.completed, ['d']);
    expect(repo['d'], isNull);
    expect(controller.deadlines, isEmpty);
    expect(find.text('Nộp báo cáo'), findsNothing);
    expect(find.text('Chưa có deadline nào'), findsOneWidget);
    expect(find.text(_snack), findsNothing);
  });

  testTab('không có việc liên kết thì xác nhận vẫn gỡ thẻ', (tester) async {
    await pumpTab(tester);
    await _pickDone(tester, 'Nộp báo cáo');
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    expect(todos.completed, ['d']);
    expect(repo['d'], isNull);
    expect(find.text('Chưa có deadline nào'), findsOneWidget);
    expect(find.text(_snack), findsNothing);
  });

  testTab('không đánh dấu xong được việc liên kết thì giữ thẻ và báo', (
    tester,
  ) async {
    await pumpTab(
      tester,
      open: {
        'd': ['Viết báo cáo'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');
    todos.failure = const StorageFailure('disk');
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    expect(todos.completed, ['d']);
    expect(repo['d'], deadline);
    expect(_card('Nộp báo cáo'), findsOneWidget);
    expect(find.text(_snack), findsOneWidget);
  });

  testTab('đánh dấu xong việc liên kết mà không xoá được deadline thì báo '
      'riêng', (tester) async {
    await pumpTab(
      tester,
      open: {
        'd': ['Viết báo cáo'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');
    repo.writeFailure = const StorageFailure('disk');
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    expect(todos.completed, ['d']);
    expect(repo['d'], deadline);
    expect(
      find.text(
        'Đã đánh dấu xong việc liên kết nhưng không lưu được việc gỡ deadline.',
      ),
      findsOneWidget,
    );
    expect(find.text(_snack), findsNothing);
  });

  testTab('không có việc liên kết mà không xoá được deadline thì báo lỗi '
      'xoá', (tester) async {
    await pumpTab(tester);
    await _pickDone(tester, 'Nộp báo cáo');
    repo.writeFailure = const StorageFailure('disk');
    await tester.tap(_confirm);
    await tester.pumpAndSettle();

    expect(repo['d'], deadline);
    expect(find.text('Không lưu được việc gỡ deadline.'), findsOneWidget);
    expect(find.text(_snack), findsNothing);
  });

  testTab('hộp thoại cuộn được khi có nhiều việc liên kết', (tester) async {
    await pumpTab(
      tester,
      open: {
        'd': [for (var i = 0; i < 40; i++) 'Việc số $i'],
      },
    );
    await _pickDone(tester, 'Nộp báo cáo');

    final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
    expect(dialog.scrollable, isTrue);
    await tester.scrollUntilVisible(
      find.text('Việc "Việc số 39" sẽ được đánh dấu đã xong.'),
      100,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(_confirm, findsOneWidget);
  });
}
