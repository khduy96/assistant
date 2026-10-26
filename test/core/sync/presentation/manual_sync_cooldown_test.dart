import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/sync/data/state_store_sync_preferences.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_state_store.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// Time as fake_async sees it, so the lock moves with the timers; [shift]
/// sets the wall clock back or forward.
class _FakeClock implements Clock {
  _FakeClock(this._async, [DateTime? start])
    : _start = start ?? DateTime(2026, 10, 22, 9);

  final FakeAsync _async;
  final DateTime _start;
  Duration shift = Duration.zero;

  @override
  DateTime now() => _start.add(_async.elapsed).add(shift);
}

/// A [FakeSyncEngine] that can hold a cycle open until the test releases
/// [gate].
class _GatedEngine extends FakeSyncEngine {
  /// While set, [sync] waits for it before answering. Read when the call
  /// arrives, so a cycle already waiting keeps its own gate.
  Completer<void>? gate;

  /// The arguments of every [sync] call, logged as it arrives, before any
  /// [gate]; [syncCalls] logs a call once past it.
  final List<({bool full, bool auto, bool checkRemote})> started = [];

  /// What the next [sync] calls answer, in order; [status] once used up.
  final List<SyncStatus> answers = [];

  @override
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  }) async {
    started.add((full: full, auto: auto, checkRemote: checkRemote));
    final wait = gate;
    if (wait != null) await wait.future;
    final status = await super.sync(
      full: full,
      auto: auto,
      checkRemote: checkRemote,
    );
    return answers.isEmpty ? status : answers.removeAt(0);
  }
}

const _manual = (full: true, auto: false, checkRemote: true);

/// Automatic sync off unless [autoSync]: then only presses reach the engine.
SyncSettings _settings({bool autoSync = false}) =>
    SyncSettings(isConfigured: true, autoSync: autoSync, space: 'nha');

SyncController _controllerFor(
  _GatedEngine engine,
  Clock clock,
  SyncStateStore states, [
  SyncBudget budget = SyncBudget.configured,
]) {
  final preferences = StateStoreSyncPreferences(states);
  return SyncController(
    runSync: RunSync(engine),
    hasPendingChanges: HasPendingChanges(engine),
    getMonthRequests: GetMonthRequests(engine),
    watchLocalChanges: WatchLocalChanges(engine),
    getSyncSettings: GetSyncSettings(engine),
    getAutoSyncChoice: GetAutoSyncChoice(preferences),
    setAutoSyncChoice: SetAutoSyncChoice(preferences),
    clock: clock,
    budget: budget,
  );
}

/// Runs [body] in fake time with a fresh engine and controller, then disposes
/// the controller and drains what is left.
void _run(
  void Function(FakeAsync async, _GatedEngine engine, SyncController c) body, {
  SyncSettings? settings,
  SyncBudget budget = SyncBudget.configured,
  DateTime? start,
  SyncStateStore? states,
}) {
  fakeAsync((async) {
    final engine = _GatedEngine()..settings = settings ?? _settings();
    final controller = _controllerFor(
      engine,
      _FakeClock(async, start),
      states ?? MemorySyncStateStore(),
      budget,
    );
    body(async, engine, controller);
    controller.dispose();
    async.flushMicrotasks();
  });
}

/// Starts [c] and lets the first cycle (if any) finish.
void _start(FakeAsync async, SyncController c) {
  unawaited(c.start());
  async.flushMicrotasks();
}

/// A press whose answer lands in the returned list once it arrives.
List<SyncStatus?> _press(SyncController c) {
  final answers = <SyncStatus?>[];
  c.pressSyncNow().then(answers.add);
  return answers;
}

void main() {
  test('khoá 30 giây; trước lần bấm đầu không khoá', () {
    expect(SyncController.manualSyncCooldown, const Duration(seconds: 30));
    _run((async, engine, c) {
      expect(c.manualSyncLocked, isFalse);
      expect(c.manualSyncCooldownLeft, Duration.zero);
      _start(async, c);
      expect(c.manualSyncLocked, isFalse);
      expect(c.manualSyncCooldownLeft, Duration.zero);
    });
  });

  test('hai lần bấm trong cùng microtask chỉ chạy một chu kỳ full bấm tay', () {
    _run((async, engine, c) {
      _start(async, c);
      final notified = <bool>[];
      c.addListener(() => notified.add(c.manualSyncLocked));

      final first = _press(c);
      // Taken before the first wait.
      expect(c.manualSyncLocked, isTrue);
      expect(notified, isNotEmpty);
      expect(notified.first, isTrue);
      final second = _press(c);
      async.flushMicrotasks();

      expect(engine.syncCalls, [_manual]);
      expect(first.single!.state, SyncState.ok);
      expect(second, [null]);
    });
  });

  test('khoá ở mọi mốc trước 30 giây, mở đúng ở 30 giây; bấm dồn chỉ tốn '
      'một chu kỳ', () {
    _run((async, engine, c) {
      _start(async, c);

      final answers = <SyncStatus?>[];
      c.pressSyncNow().then(answers.add);
      async.flushMicrotasks();
      expect(c.manualSyncLocked, isTrue);
      expect(c.manualSyncCooldownLeft, const Duration(seconds: 30));

      async.elapse(const Duration(seconds: 10));
      c.pressSyncNow().then(answers.add);
      async.elapse(const Duration(seconds: 10));
      c.pressSyncNow().then(answers.add);
      async.elapse(const Duration(milliseconds: 9999));
      c.pressSyncNow().then(answers.add);
      async.flushMicrotasks();

      expect(c.manualSyncLocked, isTrue);
      expect(c.manualSyncCooldownLeft, const Duration(milliseconds: 1));
      expect(engine.syncCalls, [_manual]);
      expect(answers, hasLength(4));
      expect(answers.first!.state, SyncState.ok);
      expect(answers.skip(1), everyElement(isNull));

      async.elapse(const Duration(milliseconds: 1));
      expect(c.manualSyncLocked, isFalse);
      expect(c.manualSyncCooldownLeft, Duration.zero);

      // Unlocked, the next press runs a cycle of its own.
      final again = _press(c);
      async.flushMicrotasks();
      expect(again.single!.state, SyncState.ok);
      expect(engine.syncCalls, [_manual, _manual]);
      expect(c.manualSyncLocked, isTrue);
    });
  });

  test('chu kỳ bấm tay dài hơn 30 giây thì khoá tới khi nó xong, rồi mở '
      'ngay và báo listener', () {
    _run((async, engine, c) {
      _start(async, c);
      engine.gate = Completer<void>();

      final answer = _press(c);
      async.elapse(const Duration(seconds: 45));
      expect(c.manualSyncLocked, isTrue);
      expect(c.manualSyncCooldownLeft, Duration.zero);
      final turnedAway = _press(c);
      async.flushMicrotasks();
      expect(turnedAway, [null]);
      expect(answer, isEmpty);

      final notified = <bool>[];
      c.addListener(() => notified.add(c.manualSyncLocked));
      engine.gate!.complete();
      engine.gate = null;
      async.flushMicrotasks();

      expect(answer.single!.state, SyncState.ok);
      expect(c.manualSyncLocked, isFalse);
      expect(notified.last, isFalse);
      expect(engine.syncCalls, [_manual]);
    });
  });

  test('engine trả lỗi thì vẫn khoá đủ 30 giây', () {
    _run((async, engine, c) {
      _start(async, c);
      engine.status = const SyncStatus(
        state: SyncState.error,
        message: 'mất mạng',
      );

      final answer = _press(c);
      async.flushMicrotasks();
      expect(answer.single!.state, SyncState.error);

      async.elapse(const Duration(milliseconds: 29999));
      expect(c.manualSyncLocked, isTrue);
      final turnedAway = _press(c);
      async.flushMicrotasks();
      expect(turnedAway, [null]);
      async.elapse(const Duration(milliseconds: 1));
      expect(c.manualSyncLocked, isFalse);
      expect(engine.syncCalls, [_manual]);
    });
  });

  test('engine ném lỗi thì pressSyncNow trả error, không ném, và vẫn khoá '
      'đủ 30 giây', () {
    _run((async, engine, c) {
      _start(async, c);
      engine.error = StateError('hỏng');

      Object? thrown;
      final answer = <SyncStatus?>[];
      c.pressSyncNow().then(answer.add, onError: (Object e) => thrown = e);
      async.flushMicrotasks();

      expect(thrown, isNull);
      expect(answer.single!.state, SyncState.error);
      expect(answer.single!.message, contains('hỏng'));

      async.elapse(const Duration(milliseconds: 29999));
      expect(c.manualSyncLocked, isTrue);
      async.elapse(const Duration(milliseconds: 1));
      expect(c.manualSyncLocked, isFalse);
    });
  });

  test('giờ hệ thống lùi sau khi bấm thì khoá theo giờ hết ngay, không quá '
      '30 giây; chu kỳ còn chạy vẫn giữ khoá', () {
    fakeAsync((async) {
      final engine = _GatedEngine()..settings = _settings();
      final clock = _FakeClock(async);
      final c = _controllerFor(engine, clock, MemorySyncStateStore());
      _start(async, c);

      // Set back an hour while the press's cycle still runs.
      engine.gate = Completer<void>();
      final answer = _press(c);
      async.elapse(const Duration(seconds: 5));
      clock.shift = const Duration(hours: -1);
      expect(c.manualSyncCooldownLeft, Duration.zero);
      expect(c.manualSyncLocked, isTrue);
      final turnedAway = _press(c);
      async.flushMicrotasks();
      expect(turnedAway, [null]);

      engine.gate!.complete();
      engine.gate = null;
      async.flushMicrotasks();
      expect(answer.single!.state, SyncState.ok);
      expect(c.manualSyncLocked, isFalse);

      // Set back after the cycle ended: open at once, not 30 s plus the hour.
      final again = _press(c);
      async.flushMicrotasks();
      expect(again.single!.state, SyncState.ok);
      expect(c.manualSyncCooldownLeft, SyncController.manualSyncCooldown);
      async.elapse(const Duration(seconds: 5));
      clock.shift -= const Duration(hours: 1);
      expect(c.manualSyncCooldownLeft, Duration.zero);
      expect(c.manualSyncLocked, isFalse);
      final third = _press(c);
      async.flushMicrotasks();
      expect(third.single!.state, SyncState.ok);
      expect(engine.syncCalls, [_manual, _manual, _manual]);

      c.dispose();
      async.flushMicrotasks();
    });
  });

  group('bấm giữa chu kỳ tự động', () {
    test('lần bấm được nhận, chạy ngay sau chu kỳ đó và trả kết quả của '
        'lượt bấm tay; khoá ít nhất 30 giây', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);
        expect(c.status.isRunning, isTrue);

        final answer = _press(c);
        async.flushMicrotasks();
        expect(answer, isEmpty);
        expect(c.manualSyncLocked, isTrue);

        async.elapse(const Duration(seconds: 5));
        engine.answers.addAll(const [
          SyncStatus(state: SyncState.ok, pushed: 1),
          SyncStatus(state: SyncState.ok, pushed: 2, pulled: 3),
        ]);
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();

        expect(engine.syncCalls, [
          (full: false, auto: true, checkRemote: true),
          _manual,
        ]);
        expect(answer.single!.pushed, 2);
        expect(answer.single!.pulled, 3);
        // Done, but 30 seconds have not passed.
        expect(c.manualSyncLocked, isTrue);
        async.elapse(const Duration(seconds: 24, milliseconds: 999));
        expect(c.manualSyncLocked, isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(c.manualSyncLocked, isFalse);
      }, settings: _settings(autoSync: true));
    });

    test('lượt xếp hàng còn chạy quá 30 giây thì khoá tới khi nó xong', () {
      _run((async, engine, c) {
        final automatic = Completer<void>();
        engine.gate = automatic;
        _start(async, c);

        final answer = _press(c);
        async.elapse(const Duration(seconds: 5));
        // The queued cycle waits on a gate of its own.
        final queued = Completer<void>();
        engine.gate = queued;
        automatic.complete();
        async.flushMicrotasks();
        expect(engine.started, [
          (full: false, auto: true, checkRemote: true),
          _manual,
        ]);

        async.elapse(const Duration(seconds: 40));
        expect(c.manualSyncLocked, isTrue);
        expect(answer, isEmpty);
        final turnedAway = _press(c);
        async.flushMicrotasks();
        expect(turnedAway, [null]);

        engine.gate = null;
        queued.complete();
        async.flushMicrotasks();
        expect(answer.single!.state, SyncState.ok);
        expect(c.manualSyncLocked, isFalse);
        expect(engine.syncCalls, hasLength(2));
      }, settings: _settings(autoSync: true));
    });
  });

  group('trigger tự động không để ý khoá', () {
    test('thay đổi local trong lúc khoá vẫn đẩy sau pushDelay', () {
      _run((async, engine, c) {
        _start(async, c);
        engine.syncCalls.clear();

        _press(c);
        async.flushMicrotasks();
        engine.changes.add(null);
        async.elapse(c.pushDelay - const Duration(milliseconds: 1));
        expect(c.manualSyncLocked, isTrue);
        expect(engine.syncCalls, [_manual]);

        async.elapse(const Duration(milliseconds: 1));
        // The last check of the server started with the press.
        expect(engine.syncCalls, [
          _manual,
          (full: false, auto: true, checkRemote: false),
        ]);
      }, settings: _settings(autoSync: true));
    });

    test('đẩy sau thay đổi local và onAppActive giống hệt khi gọi syncNow '
        'không khoá', () {
      List<({bool full, bool auto, bool checkRemote})> script(bool press) {
        late List<({bool full, bool auto, bool checkRemote})> calls;
        _run((async, engine, c) {
          _start(async, c);
          async.elapse(const Duration(minutes: 20));
          if (press) {
            unawaited(c.pressSyncNow());
          } else {
            unawaited(c.syncNow(full: true));
          }
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 5));
          c.onAppActive();
          engine.changes.add(null);
          async.elapse(const Duration(seconds: 20));
          c.onAppActive();
          async.elapse(const Duration(minutes: 20));
          c.onAppActive();
          async.flushMicrotasks();
          calls = [...engine.syncCalls];
        }, settings: _settings(autoSync: true));
        return calls;
      }

      final pressed = script(true);
      expect(pressed, script(false));
      expect(pressed, [
        (full: false, auto: true, checkRemote: true),
        _manual,
        (full: false, auto: true, checkRemote: false),
        (full: false, auto: true, checkRemote: true),
      ]);
    });

    test('onAppActive trong lúc khoá vẫn chạy chu kỳ khi tới lượt', () {
      // Spent at start, so the first cycle pauses and checks nothing; the
      // month then turns while the press before start() still locks.
      _run(
        (async, engine, c) {
          engine.monthRequests = 10;
          _press(c);
          async.flushMicrotasks();
          expect(c.manualSyncLocked, isTrue);
          _start(async, c);
          expect(c.status.state, SyncState.paused);
          expect(engine.syncCalls, isEmpty);

          async.elapse(const Duration(seconds: 20));
          expect(c.manualSyncLocked, isTrue);
          c.onAppActive();
          async.flushMicrotasks();
          expect(engine.syncCalls, [
            (full: false, auto: true, checkRemote: true),
          ]);
        },
        settings: _settings(autoSync: true),
        budget: const SyncBudget(monthlyRequests: 30, devices: 3),
        start: DateTime(2026, 10, 31, 23, 59, 50),
      );
    });

    test('bật lại sync tự động trong lúc khoá vẫn đẩy phần còn chờ', () {
      _run((async, engine, c) {
        _start(async, c);
        _press(c);
        async.flushMicrotasks();
        engine.pending = true;

        bool? saved;
        c.setAutoSync(true).then((v) => saved = v);
        async.flushMicrotasks();
        expect(saved, isTrue);
        expect(c.manualSyncLocked, isTrue);

        async.elapse(c.pushDelay);
        expect(engine.syncCalls, [
          _manual,
          (full: false, auto: true, checkRemote: false),
        ]);
      });
    });
  });

  test('controller không hẹn Timer nào cho khoá', () {
    _run((async, engine, c) {
      _start(async, c);
      _press(c);
      async.flushMicrotasks();
      expect(c.manualSyncLocked, isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('dispose giữa lúc khoá không để lại Timer', () {
    fakeAsync((async) {
      final engine = _GatedEngine()..settings = _settings();
      final c = _controllerFor(
        engine,
        _FakeClock(async),
        MemorySyncStateStore(),
      );
      _start(async, c);
      _press(c);
      async.elapse(const Duration(seconds: 10));
      expect(c.manualSyncLocked, isTrue);

      c.dispose();
      async.flushMicrotasks();
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('dispose khi chu kỳ bấm tay còn chạy: chu kỳ vẫn xong, '
      'không lỗi và không để lại Timer', () {
    fakeAsync((async) {
      final engine = _GatedEngine()..settings = _settings();
      final c = _controllerFor(
        engine,
        _FakeClock(async),
        MemorySyncStateStore(),
      );
      _start(async, c);
      engine.gate = Completer<void>();
      final answer = _press(c);
      async.flushMicrotasks();

      c.dispose();
      engine.gate!.complete();
      async.flushMicrotasks();
      expect(answer.single!.state, SyncState.ok);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('khoá không ghi gì xuống store và không còn ở controller mới', () {
    final states = MemorySyncStateStore();
    late Map<String, String> before;
    _run((async, engine, c) {
      _start(async, c);
      before = {...states.values};
      _press(c);
      async.elapse(const Duration(seconds: 5));
      expect(c.manualSyncLocked, isTrue);
      expect(states.values, before);
    }, states: states);

    _run((async, engine, c) {
      expect(c.manualSyncLocked, isFalse);
      _start(async, c);
      expect(c.manualSyncLocked, isFalse);
      expect(states.values, before);
    }, states: states);
  });
}
