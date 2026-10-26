import 'package:event_notice/core/domain/time_of_day.dart' as core;
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/presentation/pages/reminders_tab.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// [tab] as the home page shows it, with buttons that go through
/// [addReminder] like the real floating buttons: "+R" for a reminder, "+D"
/// for a deadline, "+T" for a deadline drafted from [draft].
Widget _harness(
  RemindersController controller,
  Widget tab, {
  Reminder? draft,
  void Function(Reminder?)? onAdded,
}) {
  Widget button(String label, bool deadline, {Reminder? draft}) => Builder(
    builder: (context) => TextButton(
      onPressed: () async {
        final added = await addReminder(
          context,
          deadline: deadline,
          draft: draft,
        );
        onAdded?.call(added);
      },
      child: Text(label),
    ),
  );

  return ChangeNotifierProvider<RemindersController>.value(
    value: controller,
    child: MaterialApp(
      home: Scaffold(
        body: tab,
        floatingActionButton: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            button('+R', false),
            button('+D', true),
            button('+T', true, draft: draft),
          ],
        ),
      ),
    ),
  );
}

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
  late InMemoryReminderRepository repo;
  late RemindersController controller;

  Future<void> pumpTab(
    WidgetTester tester,
    Widget tab, {
    List<Reminder> reminders = const [],
    Reminder? draft,
    void Function(Reminder?)? onAdded,
  }) async {
    clock = FakeClock(t0);
    repo = InMemoryReminderRepository(reminders);
    controller = controllerFor(
      repo,
      clock: clock,
      scheduler: FakeAlarmScheduler(ringsNatively: false),
    );
    // The clock is pinned, so the ticks only repaint: keep them quiet.
    controller.uiActive = false;
    await controller.init();
    await tester.pumpWidget(
      _harness(controller, tab, draft: draft, onAdded: onAdded),
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

  group('tab nhắc nhở', () {
    testTab('chưa có gì thì hiện hướng dẫn', (tester) async {
      await pumpTab(tester, const RemindersTab());
      expect(find.text('Chưa có nhắc nhở nào'), findsOneWidget);
      expect(
        find.text('Bấm "Thêm nhắc nhở" để tạo lịch báo cho cuộc họp sắp tới.'),
        findsOneWidget,
      );
    });

    testTab('thẻ có giờ, lịch, đếm ngược và các nhãn; không có deadline', (
      tester,
    ) async {
      await pumpTab(
        tester,
        const RemindersTab(),
        reminders: [
          reminder('a', title: 'Họp', note: 'phòng 3', lead: 5),
          reminder('d', title: 'Nộp', isDeadline: true),
        ],
      );
      expect(find.text('10:00'), findsOneWidget);
      expect(find.text('Họp'), findsOneWidget);
      expect(find.text('22/10/2026 lúc 10:00'), findsOneWidget);
      expect(find.text('còn 30 phút'), findsOneWidget);
      expect(find.text('Nhắc trước 5 phút'), findsOneWidget);
      expect(find.text('phòng 3'), findsOneWidget);
      expect(find.text('Nộp'), findsNothing);
    });

    testTab('gạt công tắc thì tắt nhắc nhở', (tester) async {
      await pumpTab(tester, const RemindersTab(), reminders: [reminder('a')]);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repo['a']!.enabled, isFalse);
      expect(find.text('Đang tắt'), findsOneWidget);
    });

    testTab('xoá phải xác nhận', (tester) async {
      await pumpTab(
        tester,
        const RemindersTab(),
        reminders: [reminder('a', title: 'Họp')],
      );
      await _menu(tester, 'Họp', 'Xoá');
      expect(find.text('Xoá nhắc nhở?'), findsOneWidget);
      expect(find.text('"Họp" sẽ bị xoá khỏi danh sách.'), findsOneWidget);

      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();
      expect(repo.length, 1);

      await _menu(tester, 'Họp', 'Xoá');
      await tester.tap(find.widgetWithText(FilledButton, 'Xoá'));
      await tester.pumpAndSettle();
      expect(repo.length, 0);
      expect(find.text('Chưa có nhắc nhở nào'), findsOneWidget);
    });

    testTab('sửa giữ id và ngày tạo, đổi giờ dừng về TimeOfDay của core', (
      tester,
    ) async {
      final created = DateTime(2026, 1, 2);
      await pumpTab(
        tester,
        const RemindersTab(),
        reminders: [
          reminder(
            'a',
            title: 'Uống nước',
            repeat: RepeatRule.daily,
            every: 120,
            end: core.TimeOfDay(hour: 22, minute: 0),
            createdAt: created,
          ),
        ],
      );
      await tester.tap(find.text('Uống nước'));
      await tester.pumpAndSettle();
      expect(find.text('Sửa nhắc nhở'), findsOneWidget);
      expect(find.text('22:00'), findsOneWidget);

      await tester.enterText(_field(0), 'Uống nước ấm');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['a']!;
      expect(saved.title, 'Uống nước ấm');
      expect(saved.time, core.TimeOfDay(hour: 10, minute: 0));
      expect(saved.endTime, core.TimeOfDay(hour: 22, minute: 0));
      expect(saved.repeatEveryMinutes, 120);
      expect(saved.createdAt, created);
      expect(saved.firedUpTo, t0);
    });
  });

  group('thêm nhắc nhở', () {
    testTab('form mới: giờ là một tiếng sau, lưu với id mới', (tester) async {
      Reminder? added;
      await pumpTab(tester, const RemindersTab(), onAdded: (r) => added = r);
      await tester.tap(find.text('+R'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm nhắc nhở'), findsOneWidget);
      expect(find.text('10:30'), findsOneWidget);
      expect(find.text('22/10/2026'), findsOneWidget);

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Hãy nhập tên sự kiện.'), findsOneWidget);

      await tester.enterText(_field(0), '  Họp khách  ');
      await tester.enterText(_field(1), ' link Zoom ');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['id-1']!;
      expect(added, saved);
      expect(saved.title, 'Họp khách');
      expect(saved.note, 'link Zoom');
      expect(saved.repeat, RepeatRule.once);
      expect(saved.date, DateTime(2026, 10, 22));
      expect(saved.time, core.TimeOfDay(hour: 10, minute: 30));
      expect(saved.endTime, isNull);
      expect(saved.leadMinutes, 0);
      expect(saved.snoozeMinutes, 5);
      expect(saved.isDeadline, isFalse);
      expect(saved.createdAt, t0);
      expect(saved.firedUpTo, t0);
      expect(find.text('Họp khách'), findsOneWidget);
    });

    testTab('hàng tuần phải chọn ít nhất một thứ', (tester) async {
      await pumpTab(tester, const RemindersTab());
      await tester.tap(find.text('+R'));
      await tester.pumpAndSettle();
      await tester.enterText(_field(0), 'Họp tuần');
      await tester.tap(find.text('Hàng tuần'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Hãy chọn ít nhất một thứ trong tuần.'), findsOneWidget);

      await tester.tap(find.text('T6'));
      await tester.tap(find.text('T2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(repo['id-1']!.weekdays, {DateTime.monday, DateTime.friday});
      expect(repo['id-1']!.repeat, RepeatRule.weekly);
    });

    testTab('deadline mới báo trước 1 giờ', (tester) async {
      await pumpTab(tester, const DeadlinesTab());
      await tester.tap(find.text('+D'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm deadline'), findsOneWidget);
      expect(find.text('Hạn chót'), findsOneWidget);
      await tester.enterText(_field(0), 'Nộp báo cáo');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['id-1']!;
      expect(saved.isDeadline, isTrue);
      expect(saved.leadMinutes, 60);
      expect(find.text('Nộp báo cáo'), findsOneWidget);
    });

    testTab('bản nháp điền sẵn form nhưng vẫn là thêm mới', (tester) async {
      final draft = reminder(
        'unused',
        title: 'Từ việc cần làm',
        note: 'ghi chú',
        isDeadline: true,
        date: DateTime(2026, 10, 25),
        hour: 8,
        lead: 60,
      );
      await pumpTab(tester, const DeadlinesTab(), draft: draft);
      await tester.tap(find.text('+T'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm deadline'), findsOneWidget);
      expect(find.text('25/10/2026'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repo['id-1']!;
      expect(saved.title, 'Từ việc cần làm');
      expect(saved.note, 'ghi chú');
      expect(saved.time, core.TimeOfDay(hour: 8, minute: 0));
      expect(saved.createdAt, t0);
      expect(repo['unused'], isNull);
    });
  });

  group('tab deadline', () {
    testTab('chưa có gì thì hiện hướng dẫn', (tester) async {
      await pumpTab(tester, const DeadlinesTab());
      expect(find.text('Chưa có deadline nào'), findsOneWidget);
    });

    testTab('đếm ngược, hạn chót, báo trước; quá hạn ở cuối', (tester) async {
      await pumpTab(
        tester,
        const DeadlinesTab(),
        reminders: [
          reminder('past', title: 'Đã trễ', isDeadline: true, hour: 8),
          reminder(
            'd',
            title: 'Nộp báo cáo',
            note: 'gửi chị Lan',
            isDeadline: true,
            date: DateTime(2026, 10, 23),
            hour: 12,
            minute: 30,
            lead: 60,
          ),
          reminder('r', title: 'Nhắc thường'),
        ],
      );
      expect(find.text('1 ngày 03:00:00'), findsOneWidget);
      expect(find.text('Hạn chót 23/10/2026 12:30'), findsOneWidget);
      expect(find.text('Báo trước 1 giờ'), findsOneWidget);
      expect(find.text('gửi chị Lan'), findsOneWidget);
      expect(find.text('QUÁ HẠN 01:30:00'), findsOneWidget);
      expect(find.text('Nhắc thường'), findsNothing);
      expect(
        tester.getTopLeft(_card('Nộp báo cáo')).dy,
        lessThan(tester.getTopLeft(_card('Đã trễ')).dy),
      );
    });
  });
}
