import 'package:event_notice/features/reminders/domain/entities/alarm_payload.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/presentation/pages/alarm_screen.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

void main() {
  late FakeClock clock;
  late InMemoryReminderRepository repo;
  late FakeAlarmScheduler scheduler;
  late RemindersController controller;

  /// Shows the alarm screen for the alert of [r] at its time (or before it,
  /// when [isLead]). The controller is never started, so no ticker runs; the
  /// alert comes in the way an OS alarm brings it.
  Future<void> pumpAlarm(
    WidgetTester tester,
    Reminder r, {
    bool native = false,
    bool isLead = false,
  }) async {
    clock = FakeClock(DateTime(2026, 10, 22, 10, 0, 7));
    repo = InMemoryReminderRepository([r]);
    scheduler = FakeAlarmScheduler(ringsNatively: native);
    controller = controllerFor(repo, clock: clock, scheduler: scheduler);
    addTearDown(controller.dispose);
    final at = isLead
        ? r.deadlineAt.subtract(Duration(minutes: r.leadMinutes))
        : r.deadlineAt;
    await controller.showAlertFromPayload(
      AlarmPayload(reminderId: r.id, at: at, isLead: isLead).encode(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final alert = controller.currentAlert;
            return alert == null
                ? const Text('Không còn chuông')
                : AlarmScreen(alert: alert, controller: controller);
          },
        ),
      ),
    );
  }

  testWidgets('đúng giờ: đồng hồ, tiêu đề, giờ sự kiện, ghi chú', (
    tester,
  ) async {
    await pumpAlarm(
      tester,
      reminder('a', title: 'Họp khách hàng', note: 'phòng 3', snooze: 10),
    );
    expect(find.text('ĐẾN GIỜ RỒI!'), findsOneWidget);
    expect(find.text('10:00:07'), findsOneWidget);
    expect(find.text('22/10/2026'), findsOneWidget);
    expect(find.text('Họp khách hàng'), findsOneWidget);
    expect(find.text('Sự kiện lúc 10:00 · 22/10/2026'), findsOneWidget);
    expect(find.text('phòng 3'), findsOneWidget);
    expect(find.text('Báo lại 10 phút'), findsOneWidget);
    expect(find.text('Tắt chuông'), findsOneWidget);
    expect(find.text('Đóng cửa sổ (X) cũng tắt chuông'), findsOneWidget);

    // The shell rebuilds the screen on every tick: the clock follows.
    clock.advance(const Duration(seconds: 2));
    await tester.pumpWidget(
      MaterialApp(
        home: AlarmScreen(
          alert: controller.currentAlert!,
          controller: controller,
        ),
      ),
    );
    expect(find.text('10:00:09'), findsOneWidget);
  });

  testWidgets('trước giờ: còn N phút, giờ sự kiện là giờ của nhắc', (
    tester,
  ) async {
    await pumpAlarm(
      tester,
      reminder('a', hour: 10, minute: 15, lead: 15),
      isLead: true,
    );
    expect(find.text('SẮP TỚI GIỜ — CÒN 15 PHÚT'), findsOneWidget);
    expect(find.text('Sự kiện lúc 10:15 · 22/10/2026'), findsOneWidget);
  });

  testWidgets('android: nhắc tắt bằng phím âm lượng hoặc phím nguồn', (
    tester,
  ) async {
    await pumpAlarm(tester, reminder('a'), native: true);
    expect(
      find.text(
        'Tắt chuông bằng nút trên màn hình, phím âm lượng hoặc phím nguồn',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Tắt chuông đóng màn hình và đánh dấu nhắc một lần là xong', (
    tester,
  ) async {
    await pumpAlarm(tester, reminder('a'));
    await tester.tap(find.text('Tắt chuông'));
    await tester.pump();
    expect(find.text('Không còn chuông'), findsOneWidget);
    expect(repo['a']!.enabled, isFalse);
    expect(scheduler.calls, contains('stopRinging'));
  });

  testWidgets('Báo lại đóng màn hình và hẹn kêu lại', (tester) async {
    await pumpAlarm(tester, reminder('a', snooze: 10));
    await tester.tap(find.text('Báo lại 10 phút'));
    await tester.pump();
    expect(find.text('Không còn chuông'), findsOneWidget);
    expect(repo['a']!.enabled, isTrue);
    expect(
      repo['a']!.snoozedUntil,
      clock.now().add(const Duration(minutes: 10)),
    );
  });
}
