import 'dart:convert';
import 'dart:io';

import 'package:event_notice/app/di/bridges/linked_reminder_bridge.dart';
import 'package:event_notice/app/di/bridges/todo_reminder_editor_bridge.dart';
import 'package:event_notice/app/di/injection.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/time_of_day.dart' as core;
import 'package:event_notice/features/reminders/data/alarm_sound_ringer.dart';
import 'package:event_notice/features/reminders/data/android_alarm_scheduler.dart';
import 'package:event_notice/features/reminders/data/datasources/reminder_local_data_source.dart';
import 'package:event_notice/features/reminders/data/noop_alarm_scheduler.dart';
import 'package:event_notice/features/reminders/data/repositories/reminder_repository_impl.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_ringer.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_scheduler.dart';
import 'package:event_notice/features/reminders/domain/repositories/reminder_repository.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_due_alerts.dart';
import 'package:event_notice/features/reminders/domain/usecases/save_reminder.dart';
import 'package:event_notice/features/reminders/presentation/reminder_alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/presentation/reminders_controller.dart';
import 'package:event_notice/features/reminders/reminders_injection.dart';
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/repositories/linked_reminder_repository.dart';
import 'package:event_notice/features/todos/presentation/todo_reminder_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'domain/fakes.dart';
import 'presentation/fixture.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  group('configureDependencies', () {
    test('đăng ký đủ reminders; cửa sổ chính và hai cầu nối dùng chung một '
        'controller', () {
      configureDependencies(sl);
      final controller = sl<RemindersController>();

      expect(controller, same(sl<RemindersController>()));
      expect(sl<ReminderRepository>(), same(sl<ReminderRepositoryImpl>()));
      expect(sl<AlarmBodyFormatter>(), isA<ReminderAlarmBodyFormatter>());
      expect(sl<AlarmRinger>(), isA<AlarmSoundRinger>());
      expect(sl<LinkedReminderRepository>(), isA<LinkedReminderBridge>());
      expect(sl<TodoReminderEditor>(), isA<TodoReminderEditorBridge>());
    });

    test('chỉ Android giao lịch cho hệ điều hành; nơi khác app tự kêu', () {
      configureDependencies(sl);

      expect(
        sl<AlarmScheduler>(),
        Platform.isAndroid
            ? isA<AndroidAlarmScheduler>()
            : isA<NoopAlarmScheduler>(),
      );
      expect(sl<RemindersController>().ringsNatively, Platform.isAndroid);
    });
  });

  group('registerReminders', () {
    late FakeClock clock;
    late FakeAlarmScheduler scheduler;
    late FakeAlarmRinger ringer;
    late String path;

    setUp(() async {
      clock = FakeClock(t0);
      scheduler = FakeAlarmScheduler(ringsNatively: false);
      ringer = FakeAlarmRinger();
      final dir = await Directory.systemTemp.createTemp('reminders_injection');
      addTearDown(() => dir.delete(recursive: true));
      path = '${dir.path}/reminders.json';

      sl
        ..registerSingleton<Clock>(clock)
        ..registerSingleton<IdGenerator>(SequentialIdGenerator());
      registerReminders(sl);
      // Trỏ file vào thư mục tạm và thay phần chạm hệ điều hành bằng bản giả;
      // phần còn lại giữ như đăng ký.
      sl
        ..unregister<ReminderLocalDataSource>()
        ..registerLazySingleton(() => ReminderLocalDataSource(sl(), path: path))
        ..unregister<AlarmScheduler>()
        ..registerSingleton<AlarmScheduler>(scheduler)
        ..unregister<AlarmRinger>()
        ..registerSingleton<AlarmRinger>(ringer);
    });

    /// The registered controller, started, and disposed after the test.
    Future<RemindersController> started() async {
      final controller = sl<RemindersController>();
      addTearDown(controller.dispose);
      await controller.init();
      return controller;
    }

    List<Map<String, dynamic>> saved() =>
        (jsonDecode(File(path).readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();

    test('use case dùng chung một repository và một bộ hẹn giờ', () {
      expect(sl<SaveReminder>(), same(sl<SaveReminder>()));
      expect(sl<GetDueAlerts>(), same(sl<GetDueAlerts>()));
      expect(sl<ReminderRepository>(), same(sl<ReminderRepositoryImpl>()));
      expect(sl<RemindersController>().ringsNatively, isFalse);
    });

    test(
      'lưu qua controller thì ghi reminders.json và đặt lại lịch OS',
      () async {
        scheduler.ringsNatively = true; // như trên Android
        final controller = await started();

        final stored = await controller.save(reminder('r1', title: 'Họp'));

        expect(controller.ringsNatively, isTrue);
        expect(controller.failure, isNull);
        expect(stored?.firedUpTo, t0);
        expect(saved().single['id'], 'r1');
        expect(saved().single['title'], 'Họp');
        final at = DateTime(2026, 10, 22, 10);
        expect(
          scheduler.scheduled.last.single.payload,
          'r1|${at.millisecondsSinceEpoch}|0',
        );
      },
    );

    test('cầu nối thấy nhắc nhở đã lưu, lần tới tính theo Clock', () async {
      final controller = await started();
      await controller.save(reminder('r1', title: 'Họp', hour: 10));
      final bridge = LinkedReminderBridge(controller);

      final found = await bridge.find('r1');

      expect(
        found.valueOrNull,
        LinkedReminder(
          id: 'r1',
          title: 'Họp',
          isDeadline: false,
          enabled: true,
          nextOccurrence: DateTime(2026, 10, 22, 10),
        ),
      );
    });

    test('tắt qua cầu nối thì lưu xuống file và rút khỏi lịch OS', () async {
      scheduler.ringsNatively = true; // như trên Android
      final controller = await started();
      await controller.save(reminder('r1'));
      expect(scheduler.scheduled.last, hasLength(1));
      final bridge = LinkedReminderBridge(controller);

      final result = await bridge.setEnabled('r1', false);

      expect(result.isOk, isTrue);
      expect(controller.reminderById('r1')?.enabled, isFalse);
      expect(saved().single['enabled'], isFalse);
      expect(scheduler.scheduled.last, isEmpty);
    });

    test(
      'xoá qua cầu nối thì bỏ luôn lần báo đang hiện và tắt chuông',
      () async {
        final controller = await started();
        await controller.save(reminder('r1'));
        final at = DateTime(2026, 10, 22, 10).millisecondsSinceEpoch;
        await controller.showAlertFromPayload('r1|$at|0');
        expect(controller.currentAlert?.reminder.id, 'r1');
        final bridge = LinkedReminderBridge(controller);

        final result = await bridge.remove('r1');

        expect(result.isOk, isTrue);
        expect(controller.currentAlert, isNull);
        expect(controller.reminders, isEmpty);
        expect(saved(), isEmpty);
        expect(ringer.calls, contains('stop'));
      },
    );
  });

  group('LinkedReminderBridge', () {
    test('ghi lỗi thì trả Err với lỗi controller ghi lại', () async {
      final repo = InMemoryReminderRepository([reminder('r1')]);
      final controller = controllerFor(
        repo,
        clock: FakeClock(t0),
        scheduler: FakeAlarmScheduler(ringsNatively: false),
      );
      addTearDown(controller.dispose);
      const failure = StorageFailure('disk full');
      repo.writeFailure = failure;
      final bridge = LinkedReminderBridge(controller);

      final result = await bridge.setEnabled('r1', false);

      expect(result.failureOrNull, same(failure));
    });
  });

  group('TodoReminderEditorBridge', () {
    testWidgets('lưu form điền sẵn từ draft thì tạo deadline qua controller', (
      tester,
    ) async {
      final repo = InMemoryReminderRepository();
      final controller = controllerFor(
        repo,
        clock: FakeClock(t0),
        scheduler: FakeAlarmScheduler(ringsNatively: false),
      );
      addTearDown(controller.dispose);
      final bridge = TodoReminderEditorBridge(controller);
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
          date: DateTime(2026, 10, 23),
          time: core.TimeOfDay(hour: 9, minute: 15),
          leadMinutes: 60,
          isDeadline: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(
        await result,
        LinkedReminder(
          id: 'id-1',
          title: 'Gửi báo giá',
          isDeadline: true,
          enabled: true,
          nextOccurrence: DateTime(2026, 10, 23, 9, 15),
        ),
      );
      final stored = repo['id-1']!;
      expect(stored.isDeadline, isTrue);
      expect(stored.leadMinutes, 60);
      expect(stored.createdAt, t0);
      expect(stored.firedUpTo, t0);
      expect(controller.reminderById('id-1'), isNotNull);
    });

    testWidgets('mở nhắc nhở có sẵn rồi lưu thì ghi qua controller', (
      tester,
    ) async {
      final repo = InMemoryReminderRepository([reminder('r1', title: 'Họp')]);
      final controller = controllerFor(
        repo,
        clock: FakeClock(t0),
        scheduler: FakeAlarmScheduler(ringsNatively: false),
      );
      // Giờ đứng yên nên tick chỉ vẽ lại; tắt cho yên.
      controller.uiActive = false;
      await controller.init();
      final bridge = TodoReminderEditorBridge(controller);
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

      final done = bridge.open(context, 'r1');
      await tester.pumpAndSettle();
      expect(find.text('Sửa nhắc nhở'), findsOneWidget);
      // Ô đầu tiên của form là tên sự kiện.
      await tester.enterText(find.byType(TextField).first, 'Họp lại');
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      await done;

      expect(repo['r1']?.title, 'Họp lại');
      expect(repo.length, 1);

      // Dừng ticker trước khi test kết thúc để không còn timer treo.
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  });
}
