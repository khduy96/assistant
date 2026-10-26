import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/domain/entities/alarm_payload.dart';
import 'package:event_notice/features/reminders/domain/entities/pending_alert.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/alert_from_payload.dart';
import 'package:event_notice/features/reminders/domain/usecases/delete_reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/dismiss_alert.dart';
import 'package:event_notice/features/reminders/domain/usecases/get_due_alerts.dart';
import 'package:event_notice/features/reminders/domain/usecases/save_reminder.dart';
import 'package:event_notice/features/reminders/domain/usecases/set_reminder_enabled.dart';
import 'package:event_notice/features/reminders/domain/usecases/snooze_alert.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

const _disk = StorageFailure('disk');

Reminder _r(
  String id, {
  RepeatRule repeat = RepeatRule.once,
  DateTime? date,
  int hour = 14,
  int minute = 0,
  int leadMinutes = 0,
  int snoozeMinutes = 5,
  bool enabled = true,
  DateTime? firedUpTo,
  DateTime? snoozedUntil,
}) => Reminder(
  id: id,
  title: id,
  repeat: repeat,
  enabled: enabled,
  date: date ?? DateTime(2026, 9, 14),
  time: TimeOfDay(hour: hour, minute: minute),
  leadMinutes: leadMinutes,
  snoozeMinutes: snoozeMinutes,
  firedUpTo: firedUpTo,
  snoozedUntil: snoozedUntil,
  createdAt: DateTime(2026, 9, 1),
);

DateTime _at(int hour, [int minute = 0, int second = 0]) =>
    DateTime(2026, 9, 14, hour, minute, second);

void main() {
  late FakeClock clock;
  late InMemoryReminderRepository repo;
  late GetDueAlerts due;

  /// Runs the ticker once against [queue] and appends what came due.
  Future<List<PendingAlert>> tick(List<PendingAlert> queue) async {
    final result = (await due(queue)).valueOrNull!;
    queue.addAll(result.alerts);
    return result.alerts;
  }

  setUp(() {
    clock = FakeClock(_at(9));
    repo = InMemoryReminderRepository();
    due = GetDueAlerts(repo, clock);
  });

  group('GetDueAlerts', () {
    test('lần báo tới hạn vào hàng đợi đúng một lần', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      final queue = <PendingAlert>[];

      clock.current = _at(13, 59, 59);
      expect(await tick(queue), isEmpty, reason: 'chưa tới giờ');

      clock.current = _at(14);
      final raised = await tick(queue);
      expect(raised, hasLength(1));
      expect(raised.single.at, _at(14));
      expect(raised.single.eventAt, _at(14));
      expect(raised.single.isLead, isFalse);
      expect(raised.single.reminder.firedUpTo, _at(14));
      expect(repo['a']!.firedUpTo, _at(14));

      // Còn trong hàng đợi: không đưa vào lần nữa.
      clock.current = _at(14, 0, 1);
      expect(await tick(queue), isEmpty);

      // Đã đóng lần báo: mốc đã qua nên cũng không báo lại.
      queue.clear();
      clock.current = _at(14, 0, 2);
      expect(await tick(queue), isEmpty);
    });

    test('trễ quá 30 phút thì bỏ qua nhưng mốc vẫn tiến lên', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      clock.current = _at(14, 30, 1);

      final result = (await due(const [])).valueOrNull!;

      expect(result.alerts, isEmpty);
      expect(result.saveFailure, isNull);
      expect(repo['a']!.firedUpTo, _at(14));
      // Lần sau cũng không kêu cho mốc đó nữa.
      expect((await due(const [])).valueOrNull!.alerts, isEmpty);
    });

    test('trễ dưới 30 phút vẫn kêu bù', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      clock.current = _at(14, 20);

      final alerts = (await due(const [])).valueOrNull!.alerts;

      expect(alerts.single.at, _at(14));
      expect(repo['a']!.firedUpTo, _at(14));
    });

    test('trễ đúng 30 phút vẫn còn trong cửa sổ báo bù', () async {
      expect(GetDueAlerts.catchUpWindow, const Duration(minutes: 30));
      await repo.save(_r('a', firedUpTo: _at(13)));
      clock.current = _at(14, 30);

      expect((await due(const [])).valueOrNull!.alerts, hasLength(1));
    });

    test('báo trước giờ là một lần báo riêng, rồi tới sự kiện', () async {
      await repo.save(_r('a', leadMinutes: 10, firedUpTo: _at(13)));
      final queue = <PendingAlert>[];

      clock.current = _at(13, 50);
      final lead = (await tick(queue)).single;
      expect(lead.isLead, isTrue);
      expect(lead.at, _at(13, 50));
      expect(lead.eventAt, _at(14));

      queue.clear();
      clock.current = _at(14);
      final event = (await tick(queue)).single;
      expect(event.isLead, isFalse);
      expect(event.at, _at(14));
    });

    test('chưa có mốc thì chỉ tính từ một giây trước bây giờ', () async {
      // Mốc 14:00 đã qua từ trước khi nhắc nhở có trong danh sách.
      await repo.save(_r('a'));
      clock.current = _at(14, 5);

      expect((await due(const [])).valueOrNull!.alerts, isEmpty);
    });

    test('không có gì tới hạn thì không ghi', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      final writes = repo.writes;
      clock.current = _at(13, 30);

      await due(const []);

      expect(repo.writes, writes);
      expect(repo.saveAllCalls, isEmpty);
    });

    test('nhiều lần báo cùng lúc: lưu một lần, theo thứ tự hiển thị', () async {
      await repo.save(_r('b', hour: 14, minute: 1, firedUpTo: _at(13)));
      await repo.save(_r('a', hour: 14, firedUpTo: _at(13)));
      await repo.save(_r('stale', hour: 9, firedUpTo: _at(8)));
      clock.current = _at(14, 2);

      final alerts = (await due(const [])).valueOrNull!.alerts;

      expect([for (final a in alerts) a.reminder.id], ['a', 'b']);
      expect(repo.saveAllCalls, hasLength(1));
      expect(
        {for (final r in repo.saveAllCalls.single) r.id},
        {'a', 'b', 'stale'},
      );
    });

    test('lần báo lại kêu đúng giờ hẹn và xoá hẹn', () async {
      await repo.save(
        _r(
          'a',
          repeat: RepeatRule.daily,
          firedUpTo: _at(14, 1),
          snoozedUntil: _at(14, 6),
        ),
      );
      clock.current = _at(14, 6);

      final alert = (await due(const [])).valueOrNull!.alerts.single;

      expect(alert.at, _at(14, 6));
      expect(alert.isLead, isFalse);
      expect(alert.eventAt, DateTime(2026, 9, 15, 14));
      expect(repo['a']!.snoozedUntil, isNull);
      expect(repo['a']!.firedUpTo, _at(14, 6));
    });

    test('lưu mốc lỗi thì vẫn trả lần báo và báo lỗi', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      repo.writeFailure = _disk;
      clock.current = _at(14);

      final result = (await due(const [])).valueOrNull!;

      expect(result.alerts, hasLength(1));
      expect(result.saveFailure, _disk);
    });

    test('đọc lỗi thì trả lỗi', () async {
      repo.failure = _disk;
      expect(await due(const []), const Err<DueAlerts>(_disk));
    });
  });

  group('DismissAlert', () {
    Future<PendingAlert> raise(Reminder r, DateTime at) async {
      await repo.save(r);
      clock.current = at;
      return (await due(const [])).valueOrNull!.alerts.single;
    }

    test('tắt lần báo chính của nhắc một lần thì nhắc đó bị tắt', () async {
      final alert = await raise(_r('a', firedUpTo: _at(13)), _at(14));

      expect(await DismissAlert(repo)(alert), const Ok<void>(null));

      expect(repo['a']!.enabled, isFalse);
      expect(repo['a']!.snoozedUntil, isNull);
    });

    test('tắt lần báo trước giờ thì nhắc vẫn bật và vẫn kêu', () async {
      final alert = await raise(
        _r('a', leadMinutes: 10, firedUpTo: _at(13)),
        _at(13, 50),
      );

      await DismissAlert(repo)(alert);

      expect(repo['a']!.enabled, isTrue);
      clock.current = _at(14);
      expect((await due(const [])).valueOrNull!.alerts.single.isLead, isFalse);
    });

    test('nhắc lặp lại vẫn bật sau khi tắt lần báo', () async {
      final alert = await raise(
        _r('a', repeat: RepeatRule.daily, firedUpTo: _at(13)),
        _at(14),
      );

      await DismissAlert(repo)(alert);

      expect(repo['a']!.enabled, isTrue);
    });

    test('tắt lần báo lại thì bỏ hẹn', () async {
      await repo.save(
        _r('a', repeat: RepeatRule.daily, snoozedUntil: _at(14, 6)),
      );
      final alert = PendingAlert(
        reminder: repo['a']!,
        at: _at(14, 6),
        eventAt: _at(14),
        isLead: false,
      );

      await DismissAlert(repo)(alert);

      expect(repo['a']!.snoozedUntil, isNull);
    });

    test('nhắc đã bị xoá thì bỏ qua, không ghi', () async {
      final alert = await raise(_r('a', firedUpTo: _at(13)), _at(14));
      await repo.delete('a');
      final writes = repo.writes;

      expect(await DismissAlert(repo)(alert), const Ok<void>(null));
      expect(repo.writes, writes);
    });

    test('lỗi của repository được trả lại', () async {
      final alert = await raise(_r('a', firedUpTo: _at(13)), _at(14));
      repo.writeFailure = _disk;
      expect(await DismissAlert(repo)(alert), const Err<void>(_disk));
    });
  });

  group('SnoozeAlert', () {
    test('hoãn thì kêu lại sau snoozeMinutes', () async {
      await repo.save(
        _r(
          'a',
          repeat: RepeatRule.daily,
          snoozeMinutes: 10,
          firedUpTo: _at(13),
        ),
      );
      final queue = <PendingAlert>[];
      clock.current = _at(14);
      final alert = (await tick(queue)).single;

      clock.current = _at(14, 1);
      expect(await SnoozeAlert(repo, clock)(alert), const Ok<void>(null));
      queue.clear();

      expect(repo['a']!.snoozedUntil, _at(14, 11));
      expect(repo['a']!.firedUpTo, _at(14, 1));
      expect(repo['a']!.enabled, isTrue);

      clock.current = _at(14, 10, 59);
      expect(await tick(queue), isEmpty, reason: 'chưa hết giờ hoãn');

      clock.current = _at(14, 11);
      final again = (await tick(queue)).single;
      expect(again.at, _at(14, 11));
      expect(again.isLead, isFalse);
    });

    test('hoãn nhắc một lần thì nhắc vẫn bật để kêu lại', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      clock.current = _at(14);
      final alert = (await due(const [])).valueOrNull!.alerts.single;

      await SnoozeAlert(repo, clock)(alert);

      clock.current = _at(14, 5);
      expect((await due(const [])).valueOrNull!.alerts.single.at, _at(14, 5));
    });

    test('nhắc đã bị xoá thì bỏ qua', () async {
      final alert = PendingAlert(
        reminder: _r('gone'),
        at: _at(14),
        eventAt: _at(14),
        isLead: false,
      );
      expect(await SnoozeAlert(repo, clock)(alert), const Ok<void>(null));
      expect(repo.writes, 0);
    });

    test('lỗi của repository được trả lại', () async {
      await repo.save(_r('a'));
      repo.failure = _disk;
      final alert = PendingAlert(
        reminder: _r('a'),
        at: _at(14),
        eventAt: _at(14),
        isLead: false,
      );
      expect(await SnoozeAlert(repo, clock)(alert), const Err<void>(_disk));
    });
  });

  group('lưu, sửa, bật/tắt đặt mốc bằng Clock.now()', () {
    test('lưu nhắc mới: mốc là bây giờ', () async {
      clock.current = _at(9, 15);
      final saved = (await SaveReminder(repo, clock)(_r('a'))).valueOrNull!;

      expect(saved.firedUpTo, _at(9, 15));
      expect(repo['a'], saved);
    });

    test('sửa sau khi lỡ giờ thì không kêu cho mốc đã qua', () async {
      // Lỡ lần 09:00 hôm nay (app đóng), mốc còn ở hôm qua.
      final missed = _r(
        'a',
        repeat: RepeatRule.daily,
        hour: 9,
        firedUpTo: DateTime(2026, 9, 13, 9),
      );
      await repo.save(missed);
      clock.current = _at(9, 10);

      await SaveReminder(repo, clock)(missed.copyWith(title: 'Họp sớm'));

      expect(repo['a']!.firedUpTo, _at(9, 10));
      expect((await due(const [])).valueOrNull!.alerts, isEmpty);
      clock.current = DateTime(2026, 9, 15, 9);
      expect(
        (await due(const [])).valueOrNull!.alerts.single.at,
        DateTime(2026, 9, 15, 9),
      );
    });

    test('bật lại thì không kêu cho mốc đã qua, và bỏ hẹn', () async {
      await repo.save(
        _r(
          'a',
          repeat: RepeatRule.daily,
          hour: 9,
          enabled: false,
          firedUpTo: DateTime(2026, 9, 13, 9),
          snoozedUntil: _at(9, 20),
        ),
      );
      clock.current = _at(9, 10);

      final result = await SetReminderEnabled(repo, clock)((
        id: 'a',
        enabled: true,
      ));

      expect(result.valueOrNull, repo['a']);
      expect(repo['a']!.enabled, isTrue);
      expect(repo['a']!.snoozedUntil, isNull);
      expect(repo['a']!.firedUpTo, _at(9, 10));
      expect((await due(const [])).valueOrNull!.alerts, isEmpty);
    });

    test('tắt thì không còn kêu', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      clock.current = _at(13, 30);

      await SetReminderEnabled(repo, clock)((id: 'a', enabled: false));

      expect(repo['a']!.enabled, isFalse);
      expect(repo['a']!.firedUpTo, _at(13, 30));
      clock.current = _at(14);
      expect((await due(const [])).valueOrNull!.alerts, isEmpty);
    });

    test('id không có thì trả null, không ghi', () async {
      final result = await SetReminderEnabled(repo, clock)((
        id: 'x',
        enabled: true,
      ));
      expect(result, const Ok<Reminder?>(null));
      expect(repo.writes, 0);
    });

    test('lỗi của repository được trả lại', () async {
      repo.failure = _disk;
      expect(
        await SaveReminder(repo, clock)(_r('a')),
        const Err<Reminder>(_disk),
      );
      expect(
        await SetReminderEnabled(repo, clock)((id: 'a', enabled: true)),
        const Err<Reminder?>(_disk),
      );
    });
  });

  group('DeleteReminder', () {
    test('xoá nhắc nhở thì bỏ luôn các lần báo của nó đang chờ', () async {
      await repo.save(_r('a', firedUpTo: _at(13)));
      await repo.save(_r('b', hour: 14, minute: 1, firedUpTo: _at(13)));
      clock.current = _at(14, 2);
      final queue = <PendingAlert>[];
      await tick(queue);
      expect(queue, hasLength(2));

      final left = await DeleteReminder(repo)((id: 'a', pending: queue));

      expect([for (final a in left.valueOrNull!) a.reminder.id], ['b']);
      expect(repo['a'], isNull);
      expect(repo['b'], isNotNull);
    });

    test('lỗi thì trả lỗi', () async {
      repo.failure = _disk;
      expect(
        await DeleteReminder(repo)((id: 'a', pending: const [])),
        const Err<List<PendingAlert>>(_disk),
      );
    });
  });

  group('AlertFromPayload', () {
    final at = _at(13, 50);

    setUp(() async {
      await repo.save(_r('a', leadMinutes: 10));
    });

    test('dựng lại lần báo chính', () async {
      final payload = AlarmPayload(reminderId: 'a', at: _at(14), isLead: false);

      final alert = await AlertFromPayload(repo)((
        payload: payload.encode(),
        queued: const [],
      ));

      expect(
        alert.valueOrNull,
        PendingAlert(
          reminder: repo['a']!,
          at: _at(14),
          eventAt: _at(14),
          isLead: false,
        ),
      );
    });

    test('báo trước giờ thì sự kiện ở sau leadMinutes', () async {
      final payload = AlarmPayload(reminderId: 'a', at: at, isLead: true);

      final alert = (await AlertFromPayload(repo)((
        payload: payload.encode(),
        queued: const [],
      ))).valueOrNull!;

      expect(alert.at, at);
      expect(alert.eventAt, _at(14));
      expect(alert.isLead, isTrue);
    });

    test('payload hỏng, nhắc đã xoá, hoặc đang chờ thì null', () async {
      final use = AlertFromPayload(repo);
      final ok = AlarmPayload(reminderId: 'a', at: at, isLead: true).encode();
      final queued = [
        PendingAlert(reminder: repo['a']!, at: at, eventAt: at, isLead: true),
      ];

      expect(
        (await use((payload: 'rác', queued: const []))).valueOrNull,
        isNull,
      );
      expect(
        (await use((
          payload: AlarmPayload(
            reminderId: 'x',
            at: at,
            isLead: false,
          ).encode(),
          queued: const [],
        ))).valueOrNull,
        isNull,
      );
      expect((await use((payload: ok, queued: queued))).valueOrNull, isNull);
      expect(repo.writes, 1, reason: 'không ghi gì ngoài lần lưu ban đầu');
    });

    test('lỗi của repository được trả lại', () async {
      repo.failure = _disk;
      final ok = AlarmPayload(reminderId: 'a', at: at, isLead: true).encode();
      expect(
        await AlertFromPayload(repo)((payload: ok, queued: const [])),
        const Err<PendingAlert?>(_disk),
      );
    });
  });
}
