import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:event_notice/features/reminders/domain/entities/scheduled_alarm.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_body_formatter.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_ringer.dart';
import 'package:event_notice/features/reminders/domain/ports/alarm_scheduler.dart';
import 'package:event_notice/features/reminders/domain/repositories/reminder_repository.dart';

/// A clock that stays at [current] until a test moves it.
class FakeClock implements Clock {
  FakeClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}

/// Hands out `id-1`, `id-2`, ... in order.
class SequentialIdGenerator implements IdGenerator {
  int _next = 1;

  @override
  String newId() => 'id-${_next++}';
}

/// Keeps reminders in a map. Set [failure] to make every call return it, or
/// [writeFailure] to make only the writes return it.
class InMemoryReminderRepository implements ReminderRepository {
  InMemoryReminderRepository([Iterable<Reminder> initial = const []]) {
    for (final r in initial) {
      _reminders[r.id] = r;
    }
  }

  final Map<String, Reminder> _reminders = {};
  final _changes = StreamController<void>.broadcast(sync: true);

  /// How many calls wrote (save, saveAll, delete), so a test can tell that
  /// nothing was written.
  int writes = 0;

  /// What each [saveAll] call was given, in order.
  final List<List<Reminder>> saveAllCalls = [];

  Failure? failure;
  Failure? writeFailure;

  Reminder? operator [](String id) => _reminders[id];

  int get length => _reminders.length;

  @override
  Future<Result<List<Reminder>>> getAll() async {
    if (failure case final f?) return Err(f);
    return Ok(_reminders.values.toList());
  }

  @override
  Future<Result<Reminder?>> find(String id) async {
    if (failure case final f?) return Err(f);
    return Ok(_reminders[id]);
  }

  @override
  Future<Result<void>> save(Reminder reminder) => _write(() {
    _reminders[reminder.id] = reminder;
  });

  @override
  Future<Result<void>> saveAll(Iterable<Reminder> reminders) {
    saveAllCalls.add(reminders.toList());
    return _write(() {
      for (final r in reminders) {
        _reminders[r.id] = r;
      }
    });
  }

  @override
  Future<Result<void>> delete(String id) => _write(() {
    _reminders.remove(id);
  });

  Future<Result<void>> _write(void Function() body) async {
    if (failure case final f?) return Err(f);
    writes++;
    if (writeFailure case final f?) return Err(f);
    body();
    _changes.add(null);
    return const Ok(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  Future<void> dispose() => _changes.close();
}

/// Records every call. Set [failure] to make every call return it.
class FakeAlarmScheduler implements AlarmScheduler {
  FakeAlarmScheduler({this.ringsNatively = true});

  @override
  bool ringsNatively;

  /// Names of the methods called, in order.
  final List<String> calls = [];

  /// What each [scheduleAll] call was given, in order.
  final List<List<ScheduledAlarm>> scheduled = [];

  String? ringing;
  String? launch;
  bool exact = true;
  bool overlays = false;
  Failure? failure;

  Future<Result<T>> _answer<T>(String name, T value) async {
    calls.add(name);
    if (failure case final f?) return Err(f);
    return Ok(value);
  }

  @override
  Future<Result<void>> scheduleAll(List<ScheduledAlarm> alarms) {
    scheduled.add(alarms);
    return _answer('scheduleAll', null);
  }

  @override
  Future<Result<void>> stopRinging() => _answer('stopRinging', null);

  @override
  Future<Result<String?>> ringingPayload() =>
      _answer('ringingPayload', ringing);

  @override
  Future<Result<String?>> launchPayload() => _answer('launchPayload', launch);

  @override
  Future<Result<void>> requestPermissions() =>
      _answer('requestPermissions', null);

  @override
  Future<Result<bool>> canScheduleExactAlarms() =>
      _answer('canScheduleExactAlarms', exact);

  @override
  Future<Result<bool>> canDrawOverlays() =>
      _answer('canDrawOverlays', overlays);

  @override
  Future<Result<void>> requestOverlayPermission() =>
      _answer('requestOverlayPermission', null);

  @override
  Future<Result<void>> testRing() => _answer('testRing', null);
}

/// Records `start`, `stop` and `dispose` in [calls].
class FakeAlarmRinger implements AlarmRinger {
  final List<String> calls = [];

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// Writes `<id>@HH:mm` for the event, and `lead <id>@HH:mm` before it, so a
/// test can see what the formatter was given.
class FakeAlarmBodyFormatter implements AlarmBodyFormatter {
  @override
  String body(Reminder reminder, DateTime eventAt, {required bool isLead}) {
    final hh = eventAt.hour.toString().padLeft(2, '0');
    final mm = eventAt.minute.toString().padLeft(2, '0');
    return '${isLead ? 'lead ' : ''}${reminder.id}@$hh:$mm';
  }
}
