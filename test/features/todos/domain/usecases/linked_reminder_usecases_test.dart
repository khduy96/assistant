import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/todos/domain/entities/linked_reminder.dart';
import 'package:event_notice/features/todos/domain/entities/reminder_draft.dart';
import 'package:event_notice/features/todos/domain/entities/todo.dart';
import 'package:event_notice/features/todos/domain/usecases/draft_reminder_from_todo.dart';
import 'package:event_notice/features/todos/domain/usecases/find_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/remove_linked_reminder.dart';
import 'package:event_notice/features/todos/domain/usecases/set_linked_reminder_enabled.dart';
import 'package:event_notice/features/todos/domain/usecases/watch_linked_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// The fixed "now" of every test: 22/10/2026 14:30.
final _now = DateTime(2026, 10, 22, 14, 30);

Todo _todo({
  String title = 'Nộp báo cáo',
  String note = 'bản cuối',
  DateTime? due,
  String? reminderId,
}) => Todo(
  id: 't',
  title: title,
  note: note,
  dueDate: due,
  reminderId: reminderId,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
);

LinkedReminder _reminder(String id, {bool enabled = true}) => LinkedReminder(
  id: id,
  title: 'Nhắc $id',
  isDeadline: false,
  enabled: enabled,
  nextOccurrence: DateTime(2026, 10, 23, 8),
);

void main() {
  const failure = UnexpectedFailure('reminders');

  group('DraftReminderFromTodo', () {
    late DraftReminderFromTodo draft;

    setUp(() => draft = DraftReminderFromTodo(FakeClock(_now)));

    Future<ReminderDraft> run(Todo todo, {bool deadline = false}) async =>
        (await draft((todo: todo, deadline: deadline))).valueOrNull!;

    test('giữ tiêu đề và ghi chú', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 25, 17)));
      expect(d.title, 'Nộp báo cáo');
      expect(d.note, 'bản cuối');
    });

    test('hạn có giờ ở tương lai: đúng ngày, đúng giờ', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 25, 17, 45)));
      expect(d.date, DateTime(2026, 10, 25));
      expect(d.time, TimeOfDay(hour: 17, minute: 45));
      expect(d.at, DateTime(2026, 10, 25, 17, 45));
    });

    test('hạn chỉ có ngày: báo lúc 08:00 ngày đó', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 25)));
      expect(d.date, DateTime(2026, 10, 25));
      expect(d.time, TimeOfDay(hour: 8, minute: 0));
    });

    test('hôm nay, giờ còn tới: giữ hôm nay', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 22, 16)));
      expect(d.date, DateTime(2026, 10, 22));
      expect(d.time, TimeOfDay(hour: 16, minute: 0));
    });

    test('hôm nay không có giờ, 08:00 đã qua: dời sang mai 08:00', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 22)));
      expect(d.date, DateTime(2026, 10, 23));
      expect(d.time, TimeOfDay(hour: 8, minute: 0));
    });

    test('hạn đã qua: dời sang mai, giữ giờ của hạn', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 20, 9, 15)));
      expect(d.date, DateTime(2026, 10, 23));
      expect(d.time, TimeOfDay(hour: 9, minute: 15));
    });

    test('đúng phút hiện tại vẫn chưa qua: giữ hôm nay', () async {
      final d = await run(_todo(due: _now));
      expect(d.date, DateTime(2026, 10, 22));
      expect(d.time, TimeOfDay(hour: 14, minute: 30));
    });

    test('không có hạn: ngày mai 08:00', () async {
      final d = await run(_todo());
      expect(d.date, DateTime(2026, 10, 23));
      expect(d.time, TimeOfDay(hour: 8, minute: 0));
    });

    test('deadline báo trước 60 phút, nhắc nhở thì không', () async {
      final todo = _todo(due: DateTime(2026, 10, 25, 17));

      final deadline = await run(todo, deadline: true);
      expect(deadline.isDeadline, isTrue);
      expect(deadline.leadMinutes, 60);

      final reminder = await run(todo);
      expect(reminder.isDeadline, isFalse);
      expect(reminder.leadMinutes, 0);
    });

    test('date luôn là nửa đêm', () async {
      final d = await run(_todo(due: DateTime(2026, 10, 20, 9, 15)));
      expect(d.date.hour, 0);
      expect(d.date.minute, 0);
    });
  });

  group('FindLinkedReminder', () {
    test('việc chưa liên kết: null, không tra repository', () async {
      final repo = FakeLinkedReminderRepository()..failure = failure;
      expect(
        await FindLinkedReminder(repo)(_todo()),
        const Ok<LinkedReminder?>(null),
      );
    });

    test('trả nhắc nhở theo reminderId', () async {
      final r1 = _reminder('r1');
      final repo = FakeLinkedReminderRepository([r1, _reminder('r2')]);
      expect(
        await FindLinkedReminder(repo)(_todo(reminderId: 'r1')),
        Ok<LinkedReminder?>(r1),
      );
    });

    test('nhắc nhở đã bị xoá: null', () async {
      final repo = FakeLinkedReminderRepository([_reminder('r2')]);
      expect(
        await FindLinkedReminder(repo)(_todo(reminderId: 'gone')),
        const Ok<LinkedReminder?>(null),
      );
    });

    test('lỗi được trả lại', () async {
      final repo = FakeLinkedReminderRepository()..failure = failure;
      expect(
        await FindLinkedReminder(repo)(_todo(reminderId: 'r1')),
        const Err<LinkedReminder?>(failure),
      );
    });
  });

  group('SetLinkedReminderEnabled', () {
    test('tắt nhắc nhở đang bật', () async {
      final repo = FakeLinkedReminderRepository([_reminder('r1')]);

      await SetLinkedReminderEnabled(repo)((reminderId: 'r1', enabled: false));

      expect(repo.enabledCalls, [('r1', false)]);
      expect(repo['r1']!.enabled, isFalse);
    });

    test('bật lại nhắc nhở đang tắt', () async {
      final repo = FakeLinkedReminderRepository([
        _reminder('r1', enabled: false),
      ]);

      await SetLinkedReminderEnabled(repo)((reminderId: 'r1', enabled: true));

      expect(repo.enabledCalls, [('r1', true)]);
    });

    test('đã đúng trạng thái thì không gọi setEnabled', () async {
      final repo = FakeLinkedReminderRepository([
        _reminder('on'),
        _reminder('off', enabled: false),
      ]);
      final set = SetLinkedReminderEnabled(repo);

      expect(
        await set((reminderId: 'on', enabled: true)),
        const Ok<void>(null),
      );
      expect(
        await set((reminderId: 'off', enabled: false)),
        const Ok<void>(null),
      );

      expect(repo.enabledCalls, isEmpty);
    });

    test('nhắc nhở đã bị xoá thì không làm gì', () async {
      final repo = FakeLinkedReminderRepository();
      expect(
        await SetLinkedReminderEnabled(repo)((
          reminderId: 'gone',
          enabled: false,
        )),
        const Ok<void>(null),
      );
      expect(repo.enabledCalls, isEmpty);
    });

    test('lỗi được trả lại', () async {
      final repo = FakeLinkedReminderRepository([_reminder('r1')])
        ..failure = failure;
      expect(
        await SetLinkedReminderEnabled(repo)((
          reminderId: 'r1',
          enabled: false,
        )),
        const Err<void>(failure),
      );
    });
  });

  group('RemoveLinkedReminder', () {
    test('xoá nhắc nhở theo id', () async {
      final repo = FakeLinkedReminderRepository([_reminder('r1')]);

      expect(await RemoveLinkedReminder(repo)('r1'), const Ok<void>(null));

      expect(repo.removed, ['r1']);
      expect(repo['r1'], isNull);
    });
  });

  group('WatchLinkedReminders', () {
    test('chuyển tiếp changes của repository', () async {
      final repo = FakeLinkedReminderRepository();
      final stream = (await WatchLinkedReminders(repo)(
        const NoParams(),
      )).valueOrNull!;
      var fired = 0;
      final sub = stream.listen((_) => fired++);

      repo.changesController.add(null);
      repo.changesController.add(null);

      expect(fired, 2);
      await sub.cancel();
      await repo.dispose();
    });
  });
}
