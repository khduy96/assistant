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

/// Time as fake_async sees it, so [SyncController]'s checks of elapsed time
/// and of the month move with the timers.
class FakeClock implements Clock {
  FakeClock(this._async, [DateTime? start])
    : _start = start ?? DateTime(2026, 10, 22, 9);

  final FakeAsync _async;
  final DateTime _start;

  @override
  DateTime now() => _start.add(_async.elapsed);
}

/// A [FakeSyncEngine] that logs every call it gets, and can hold a cycle open
/// until the test releases [gate].
class _ScriptedEngine extends FakeSyncEngine {
  /// Every call, in order: `sync(full)`, `sync`, `hasLocalChanges`,
  /// `requestsThisMonth`, `localChanges`.
  final List<String> calls = [];

  /// While set, [sync] waits for it before answering.
  Completer<void>? gate;

  /// While set, [hasLocalChanges] waits for it before answering.
  Completer<void>? pendingGate;

  /// What the next [sync] calls answer, in order; [status] once used up.
  final List<SyncStatus> answers = [];

  int get cycles => calls.where((c) => c.startsWith('sync')).length;

  @override
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  }) async {
    calls.add(full ? 'sync(full)' : 'sync');
    final wait = gate;
    if (wait != null) await wait.future;
    final status = await super.sync(
      full: full,
      auto: auto,
      checkRemote: checkRemote,
    );
    return answers.isEmpty ? status : answers.removeAt(0);
  }

  @override
  Future<bool> hasLocalChanges() async {
    calls.add('hasLocalChanges');
    final wait = pendingGate;
    if (wait != null) await wait.future;
    return super.hasLocalChanges();
  }

  @override
  Future<int> requestsThisMonth() {
    calls.add('requestsThisMonth');
    return super.requestsThisMonth();
  }

  @override
  Stream<void> get localChanges {
    calls.add('localChanges');
    return super.localChanges;
  }
}

/// A [MemorySyncStateStore] that fails, or holds a write, on demand.
class _FlakyStateStore extends MemorySyncStateStore {
  bool failReads = false;
  bool failWrites = false;

  /// While set, [write] waits for it before storing.
  Completer<void>? writeGate;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('không đọc được');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    final wait = writeGate;
    if (wait != null) await wait.future;
    if (failWrites) throw StateError('đĩa đầy');
    return super.write(key, value);
  }
}

/// The user's auto-sync choice is kept in [states], a fresh empty one (no
/// choice) unless given.
SyncController _controllerFor(
  _ScriptedEngine engine,
  Clock clock, [
  SyncBudget budget = SyncBudget.configured,
  SyncStateStore? states,
]) {
  final preferences = StateStoreSyncPreferences(
    states ?? MemorySyncStateStore(),
  );
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
/// the controller and drains what is left. [start] is when the fake clock
/// begins; [states] is where the user's choice is kept.
void _run(
  void Function(FakeAsync async, _ScriptedEngine engine, SyncController c)
  body, {
  SyncSettings? settings,
  SyncBudget budget = SyncBudget.configured,
  DateTime? start,
  SyncStateStore? states,
}) {
  fakeAsync((async) {
    final engine = _ScriptedEngine();
    if (settings != null) engine.settings = settings;
    final controller = _controllerFor(
      engine,
      FakeClock(async, start),
      budget,
      states,
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

/// Turns automatic sync on or off as the user would, and returns whether
/// the choice was saved.
bool _setAuto(FakeAsync async, SyncController c, bool enabled) {
  bool? saved;
  c.setAutoSync(enabled).then((value) => saved = value);
  async.flushMicrotasks();
  return saved!;
}

void main() {
  test('các mốc lấy từ ngân sách; mặc định 30 giây, 14 phút, 2 giờ', () {
    _run((async, engine, c) {
      const budget = SyncBudget.configured;
      expect(c.budget, same(budget));
      expect(c.budgetLevel, SyncBudgetLevel.normal);
      expect(c.pushDelay, budget.pushDelay(SyncBudgetLevel.normal));
      expect(
        c.activeRefreshAfter,
        budget.appActiveRefresh(SyncBudgetLevel.normal),
      );
      expect(
        c.autoSyncInterval,
        budget.fallbackInterval(SyncBudgetLevel.normal),
      );
      // At the default budget.
      expect(c.pushDelay, const Duration(seconds: 30));
      expect(c.activeRefreshAfter, const Duration(minutes: 14));
      expect(c.autoSyncInterval, const Duration(hours: 2));
    });
  });

  test('ngân sách lớn hơn thì không mốc nào dài hơn', () {
    Duration refresh(int monthly) {
      late Duration value;
      _run(
        (async, engine, c) => value = c.activeRefreshAfter,
        budget: SyncBudget(monthlyRequests: monthly, devices: 3),
      );
      return value;
    }

    expect(refresh(5000), greaterThanOrEqualTo(refresh(10000)));
    expect(refresh(10000), greaterThanOrEqualTo(refresh(20000)));
    expect(refresh(5000), greaterThan(refresh(20000)));
  });

  test('trước start() mọi trigger bị bỏ qua', () {
    _run((async, engine, c) {
      c.onAppActive();
      engine.changes.add(null);
      unawaited(c.syncNow(full: true));
      async.elapse(const Duration(hours: 5));

      expect(engine.calls, isEmpty);
      expect(c.status.state, SyncState.notConfigured);
      expect(c.isConfigured, isFalse);
    });
  });

  group('start', () {
    test('đã cấu hình và autoSync bật thì chạy một chu kỳ', () {
      _run((async, engine, c) {
        engine.monthRequests = 42;
        final states = <SyncState>[];
        c.addListener(() => states.add(c.status.state));

        _start(async, c);

        expect(engine.calls.where((x) => x.startsWith('sync')), ['sync']);
        expect(states, [SyncState.idle, SyncState.running, SyncState.ok]);
        expect(c.settings.space, 'nha');
        expect(c.isConfigured, isTrue);
      });
    });

    test('trạng thái idle mang số request của tháng trước chu kỳ đầu', () {
      _run((async, engine, c) {
        engine.monthRequests = 42;
        final seen = <int?>[];
        c.addListener(() {
          if (c.status.state == SyncState.idle) {
            seen.add(c.status.monthRequests);
          }
        });

        _start(async, c);

        expect(seen, [42]);
      });
    });

    test('gọi hai lần chỉ chạy một chu kỳ và nghe một lần', () {
      _run((async, engine, c) {
        unawaited(c.start());
        unawaited(c.start());
        async.flushMicrotasks();

        expect(engine.cycles, 1);
        expect(engine.calls.where((x) => x == 'localChanges'), hasLength(1));
      });
    });

    test('chưa cấu hình thì notConfigured và không gọi engine', () {
      _run(
        (async, engine, c) {
          engine.pending = true;
          _start(async, c);

          engine.changes.add(null);
          c.onAppActive();
          SyncStatus? manual;
          c.syncNow(full: true).then((s) => manual = s);
          async.elapse(const Duration(hours: 5));

          expect(engine.calls, isEmpty);
          expect(c.status.state, SyncState.notConfigured);
          expect(manual!.state, SyncState.notConfigured);
          expect(c.isConfigured, isFalse);
        },
        settings: const SyncSettings(
          isConfigured: false,
          autoSync: true,
          space: '',
        ),
      );
    });
  });

  group('đẩy sau khi sửa', () {
    test('đẩy 30 giây sau lần sửa cuối, nhiều lần sửa thành một chu kỳ', () {
      _run((async, engine, c) {
        _start(async, c);
        expect(engine.cycles, 1);

        engine.changes.add(null);
        async.elapse(const Duration(seconds: 10));
        engine.changes.add(null);
        async.elapse(const Duration(seconds: 10));
        engine.changes.add(null);
        async.elapse(const Duration(seconds: 29));
        expect(engine.cycles, 1);

        async.elapse(const Duration(seconds: 1));
        expect(engine.cycles, 2);
        expect(engine.calls.last, 'sync');

        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 2);
      });
    });

    test('một chu kỳ chạy giữa chừng thì huỷ lần đẩy đang chờ', () {
      _run((async, engine, c) {
        _start(async, c);
        engine.changes.add(null);
        async.elapse(const Duration(seconds: 10));

        unawaited(c.syncNow(full: true));
        async.elapse(const Duration(minutes: 1));

        expect(engine.cycles, 2);
      });
    });
  });

  group('focus, restore, resume', () {
    test('chỉ pull khi lượt kiểm trước bắt đầu đã từ R', () {
      _run((async, engine, c) {
        _start(async, c);
        final r = c.activeRefreshAfter;

        async.elapse(r - const Duration(seconds: 1));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 1);

        async.elapse(const Duration(seconds: 1));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 2);
        expect(engine.calls.last, 'sync');

        // Counted from the cycle that just started.
        async.elapse(const Duration(minutes: 5));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 2);
      });
    });

    test('mốc R tính từ lúc chu kỳ bắt đầu, không phải lúc xong', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);
        final r = c.activeRefreshAfter;
        async.elapse(r - const Duration(minutes: 2));
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(c.status.state, SyncState.ok);

        async.elapse(const Duration(minutes: 2));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 2);
      });
    });

    test('không chạy khi đang có chu kỳ', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);
        expect(c.status.isRunning, isTrue);

        async.elapse(const Duration(minutes: 30));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 1);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        // A focus during a cycle queues nothing.
        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 1);
      });
    });
  });

  group('timer dự phòng 2 giờ', () {
    test('chỉ chạy khi còn thay đổi chưa đẩy', () {
      _run((async, engine, c) {
        _start(async, c);

        async.elapse(const Duration(hours: 2));
        expect(engine.cycles, 1);
        expect(engine.calls.last, 'hasLocalChanges');

        // Re-armed after an idle tick.
        engine.pending = true;
        async.elapse(const Duration(hours: 2));
        expect(engine.cycles, 2);
        expect(engine.calls.last, 'sync');
      });
    });

    test('tính từ lúc chu kỳ trước kết thúc', () {
      _run((async, engine, c) {
        engine.pending = true;
        engine.gate = Completer<void>();
        _start(async, c);
        async.elapse(const Duration(minutes: 5));
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();

        async.elapse(const Duration(hours: 1, minutes: 59, seconds: 59));
        expect(engine.cycles, 1);
        async.elapse(const Duration(seconds: 1));
        expect(engine.cycles, 2);
      });
    });

    test('đọc thay đổi chờ lỗi thì không chạy, hẹn lại 2 giờ', () {
      _run((async, engine, c) {
        _start(async, c);
        engine.error = StateError('db đóng');

        async.elapse(const Duration(hours: 2));
        expect(engine.cycles, 1);

        engine
          ..error = null
          ..pending = true;
        async.elapse(const Duration(hours: 2));
        expect(engine.cycles, 2);
      });
    });
  });

  group('Đồng bộ ngay', () {
    test('syncNow(full: true) chạy full và trả trạng thái của chu kỳ', () {
      _run((async, engine, c) {
        _start(async, c);
        final at = DateTime(2026, 10, 22, 9, 1);
        engine.status = SyncStatus(
          state: SyncState.ok,
          lastSyncAt: at,
          pushed: 2,
          pulled: 3,
          monthRequests: 50,
        );

        SyncStatus? result;
        c.syncNow(full: true).then((s) => result = s);
        async.flushMicrotasks();

        expect(engine.calls.last, 'sync(full)');
        expect(result!.state, SyncState.ok);
        expect(result!.pushed, 2);
        expect(result!.pulled, 3);
        expect(c.status.lastSyncAt, at);
        expect(c.status.monthRequests, 50);
      });
    });

    test('vẫn chạy được khi PARSE_AUTO_SYNC=0', () {
      _run(
        (async, engine, c) {
          _start(async, c);
          unawaited(c.syncNow(full: true));
          async.flushMicrotasks();
          expect(engine.calls.where((x) => x.startsWith('sync')), [
            'sync(full)',
          ]);
        },
        settings: const SyncSettings(
          isConfigured: true,
          autoSync: false,
          space: 'nha',
        ),
      );
    });
  });

  group('yêu cầu đến giữa chu kỳ', () {
    test('syncNow giữa chu kỳ tự động thì một chu kỳ full bấm tay chạy '
        'ngay sau chu kỳ đó', () {
      _run((async, engine, c) {
        engine.answers.addAll(const [
          SyncStatus(state: SyncState.ok, pushed: 1),
          SyncStatus(state: SyncState.ok, pushed: 2, pulled: 3),
        ]);
        engine.gate = Completer<void>();
        _start(async, c);

        SyncStatus? queued;
        c.syncNow(full: true).then((s) => queued = s);
        async.flushMicrotasks();
        expect(queued, isNull);
        expect(engine.cycles, 1);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.syncCalls, [
          (full: false, auto: true, checkRemote: true),
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(queued!.state, SyncState.ok);
        expect(queued!.pushed, 2);
        expect(queued!.pulled, 3);

        // Nothing is left for a push afterwards.
        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 2);
      });
    });

    test('bấm khi lượt bấm tay full đang chạy thì nhận kết quả của lượt đó, '
        'không chạy thêm', () {
      _run((async, engine, c) {
        _start(async, c);
        engine
          ..gate = Completer<void>()
          ..answers.add(
            const SyncStatus(state: SyncState.ok, pushed: 2, pulled: 3),
          );

        final results = <SyncStatus>[];
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();
        c.syncNow(full: true).then(results.add);
        c.syncNow().then(results.add);
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();
        expect(results, isEmpty);
        expect(engine.cycles, 2);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(results, hasLength(4));
        for (final r in results) {
          expect(r.state, SyncState.ok);
          expect(r.pushed, 2);
          expect(r.pulled, 3);
        }

        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 2);
      });
    });

    test('bấm 3 lần giữa chu kỳ tự động thì đúng một chu kỳ full chạy tiếp, '
        'cả 3 nhận kết quả của chu kỳ đó', () {
      _run((async, engine, c) {
        engine.answers.addAll(const [
          SyncStatus(state: SyncState.ok, pushed: 1),
          SyncStatus(state: SyncState.ok, pushed: 4, pulled: 5),
        ]);
        engine.gate = Completer<void>();
        _start(async, c);

        final results = <SyncStatus>[];
        c.syncNow().then(results.add);
        c.syncNow(full: true).then(results.add);
        c.syncNow().then(results.add);
        async.flushMicrotasks();
        expect(results, isEmpty);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.syncCalls, [
          (full: false, auto: true, checkRemote: true),
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(results, hasLength(3));
        for (final r in results) {
          expect(r.pushed, 4);
          expect(r.pulled, 5);
        }

        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 2);
      });
    });

    test('syncNow() không full đang chạy rồi syncNow(full: true) thì một chu '
        'kỳ full chạy tiếp', () {
      _run((async, engine, c) {
        _start(async, c);
        engine
          ..gate = Completer<void>()
          ..answers.addAll(const [
            SyncStatus(state: SyncState.ok, pushed: 1),
            SyncStatus(state: SyncState.ok, pushed: 2, pulled: 3),
          ]);

        SyncStatus? first;
        SyncStatus? second;
        c.syncNow().then((s) => first = s);
        async.flushMicrotasks();
        c.syncNow(full: true).then((s) => second = s);
        async.flushMicrotasks();
        expect(engine.cycles, 2);
        expect(second, isNull);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.syncCalls.skip(1), [
          (full: false, auto: false, checkRemote: true),
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(first!.pushed, 1);
        expect(second!.pushed, 2);
        expect(second!.pulled, 3);

        async.elapse(const Duration(minutes: 5));
        expect(engine.cycles, 3);
      });
    });

    test('lượt bấm tay đang chạy lỗi thì lần bấm ghép vào nhận lỗi', () {
      _run((async, engine, c) {
        _start(async, c);
        engine.gate = Completer<void>();

        final results = <SyncStatus>[];
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();

        engine.error = StateError('hỏng');
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(results, hasLength(2));
        for (final r in results) {
          expect(r.state, SyncState.error);
          expect(r.message, contains('hỏng'));
        }
        expect(engine.cycles, 2);
      });
    });

    test('dispose khi có lượt bấm tay chờ thì future vẫn xong, không chạy '
        'thêm, không còn timer', () {
      fakeAsync((async) {
        final engine = _ScriptedEngine()..gate = Completer<void>();
        final c = _controllerFor(engine, FakeClock(async));
        _start(async, c);

        SyncStatus? queued;
        c.syncNow(full: true).then((s) => queued = s);
        async.flushMicrotasks();
        c.dispose();
        engine.gate!.complete();
        engine.gate = null;
        engine.pending = true;
        async.elapse(const Duration(hours: 5));

        expect(queued, isNotNull);
        expect(engine.cycles, 1);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('sửa giữa chu kỳ thì đẩy 30 giây sau lần sửa', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);

        async.elapse(const Duration(seconds: 10));
        engine.changes.add(null);
        async.elapse(const Duration(seconds: 5));
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.cycles, 1);

        async.elapse(const Duration(seconds: 24));
        expect(engine.cycles, 1);
        async.elapse(const Duration(seconds: 1));
        expect(engine.cycles, 2);
      });
    });

    test('lần đẩy tới hạn khi chu kỳ còn chạy thì đẩy pushDelay sau khi chu '
        'kỳ đó xong', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);

        engine.changes.add(null);
        async.elapse(const Duration(minutes: 1));
        expect(engine.cycles, 1);
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();

        async.elapse(c.pushDelay - const Duration(seconds: 1));
        expect(engine.cycles, 1);
        async.elapse(const Duration(seconds: 1));
        expect(engine.syncCalls.last.auto, isTrue);
        expect(engine.cycles, 2);
      });
    });
  });

  test('PARSE_AUTO_SYNC=0 tắt mọi lần sync tự động', () {
    _run(
      (async, engine, c) {
        engine.pending = true;
        _start(async, c);
        expect(c.status.state, SyncState.idle);

        engine.changes.add(null);
        async.elapse(const Duration(minutes: 1));
        c.onAppActive();
        async.elapse(const Duration(hours: 5));

        expect(engine.cycles, 0);
        expect(engine.calls, isNot(contains('hasLocalChanges')));
      },
      settings: const SyncSettings(
        isConfigured: true,
        autoSync: false,
        space: 'nha',
      ),
    );
  });

  group('lỗi', () {
    test('chu kỳ lỗi giữ lastSyncAt và số request cũ', () {
      _run((async, engine, c) {
        final at = DateTime(2026, 10, 22, 9);
        engine.status = SyncStatus(
          state: SyncState.ok,
          lastSyncAt: at,
          monthRequests: 7,
        );
        _start(async, c);

        engine.status = const SyncStatus(
          state: SyncState.error,
          message: 'Không có kết nối mạng',
        );
        unawaited(c.syncNow(full: true));
        async.flushMicrotasks();

        expect(c.status.state, SyncState.error);
        expect(c.status.message, 'Không có kết nối mạng');
        expect(c.status.lastSyncAt, at);
        expect(c.status.monthRequests, 7);
      });
    });

    test('engine ném lỗi thì trạng thái error, không kẹt ở running', () {
      _run((async, engine, c) {
        _start(async, c);
        engine.error = StateError('hỏng');

        unawaited(c.syncNow(full: true));
        async.flushMicrotasks();

        expect(c.status.state, SyncState.error);
        expect(c.status.message, contains('hỏng'));
      });
    });
  });

  test('dispose giữa chu kỳ thì không báo listener và không hẹn timer', () {
    fakeAsync((async) {
      final engine = _ScriptedEngine()..gate = Completer<void>();
      final c = _controllerFor(engine, FakeClock(async));
      _start(async, c);
      expect(c.status.isRunning, isTrue);

      c.dispose();
      engine.changes.add(null);
      engine.gate!.complete();
      engine.gate = null;
      engine.pending = true;
      async.elapse(const Duration(hours: 5));

      expect(engine.cycles, 1);
      expect(async.pendingTimers, isEmpty);
    });
  });

  group('đường tự động và đường bấm tay', () {
    test('trigger tự động gọi auto: true, bấm tay gọi auto: false', () {
      _run((async, engine, c) {
        _start(async, c);
        expect(engine.syncCalls.last, (
          full: false,
          auto: true,
          checkRemote: true,
        ));

        // A push right after a check does not ask the server again.
        engine.changes.add(null);
        async.elapse(c.pushDelay);
        expect(engine.syncCalls.last, (
          full: false,
          auto: true,
          checkRemote: false,
        ));

        async.elapse(c.activeRefreshAfter);
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.syncCalls.last, (
          full: false,
          auto: true,
          checkRemote: true,
        ));

        unawaited(c.syncNow(full: true));
        async.flushMicrotasks();
        expect(engine.syncCalls.last, (
          full: true,
          auto: false,
          checkRemote: true,
        ));

        engine.pending = true;
        async.elapse(c.autoSyncInterval);
        expect(engine.syncCalls, hasLength(5));
        expect(engine.syncCalls.last, (
          full: false,
          auto: true,
          checkRemote: true,
        ));
      });
    });

    test('timer đẩy kiểm server khi lượt kiểm trước đã cách ít nhất R', () {
      _run((async, engine, c) {
        _start(async, c);

        async.elapse(c.activeRefreshAfter - c.pushDelay);
        engine.changes.add(null);
        async.elapse(c.pushDelay);
        expect(engine.syncCalls, hasLength(2));
        expect(engine.syncCalls.last.checkRemote, isTrue);

        // Counted again from that check.
        engine.changes.add(null);
        async.elapse(c.pushDelay);
        expect(engine.syncCalls, hasLength(3));
        expect(engine.syncCalls.last.checkRemote, isFalse);
      });
    });

    test('chu kỳ chỉ đẩy không dời mốc R của focus', () {
      _run((async, engine, c) {
        _start(async, c);
        final r = c.activeRefreshAfter;

        async.elapse(r - c.pushDelay - const Duration(minutes: 1));
        engine.changes.add(null);
        async.elapse(c.pushDelay);
        expect(engine.syncCalls.last.checkRemote, isFalse);

        async.elapse(const Duration(minutes: 1));
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 3);
        expect(engine.syncCalls.last.checkRemote, isTrue);
      });
    });

    test('hai lần focus liền nhau chỉ chạy một chu kỳ, không đọc đĩa', () {
      _run((async, engine, c) {
        _start(async, c);
        async.elapse(c.activeRefreshAfter);

        c.onAppActive();
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 2);

        engine.gate = Completer<void>();
        async.elapse(c.activeRefreshAfter);
        c.onAppActive();
        c.onAppActive();
        async.flushMicrotasks();
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.cycles, 3);

        expect(engine.calls.where((x) => x == 'requestsThisMonth'), [
          'requestsThisMonth',
        ]);
      });
    });
  });

  group('mức warning', () {
    const budget = SyncBudget.configured;

    void nearlySpent(_ScriptedEngine engine) {
      engine
        ..monthRequests = budget.warnAt
        ..status = SyncStatus(
          state: SyncState.ok,
          monthRequests: budget.warnAt,
        );
    }

    test('focus sau R(normal) không chạy, sau R(warning) thì chạy', () {
      _run((async, engine, c) {
        nearlySpent(engine);
        _start(async, c);
        expect(c.budgetLevel, SyncBudgetLevel.warning);
        expect(engine.cycles, 1);

        final normal = budget.appActiveRefresh(SyncBudgetLevel.normal);
        final warning = budget.appActiveRefresh(SyncBudgetLevel.warning);
        expect(c.activeRefreshAfter, warning);

        async.elapse(normal);
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 1);

        async.elapse(warning - normal);
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.cycles, 2);
        expect(engine.syncCalls.last.auto, isTrue);
      });
    });

    test('timer đẩy chờ pushDelay(warning)', () {
      _run((async, engine, c) {
        nearlySpent(engine);
        _start(async, c);
        final delay = budget.pushDelay(SyncBudgetLevel.warning);
        expect(c.pushDelay, delay);
        expect(delay, greaterThan(budget.pushDelay(SyncBudgetLevel.normal)));

        engine.changes.add(null);
        async.elapse(delay - const Duration(seconds: 1));
        expect(engine.cycles, 1);
        async.elapse(const Duration(seconds: 1));
        expect(engine.cycles, 2);
      });
    });
  });

  group('mức exhausted', () {
    const budget = SyncBudget.configured;

    void spent(_ScriptedEngine engine) {
      engine
        ..monthRequests = budget.stopAt
        ..status = SyncStatus(
          state: SyncState.ok,
          monthRequests: budget.stopAt,
        );
    }

    test('focus, sửa và timer không gọi engine; bấm tay chạy một chu kỳ', () {
      _run((async, engine, c) {
        spent(engine);
        engine.pending = true;
        _start(async, c);

        expect(c.budgetLevel, SyncBudgetLevel.exhausted);
        expect(c.status.state, SyncState.paused);
        expect(c.status.message, contains('hết ngân sách request tháng này'));
        expect(c.status.message, contains('tháng sau'));
        expect(c.status.monthRequests, budget.stopAt);

        engine.changes.add(null);
        async.elapse(const Duration(minutes: 1));
        c.onAppActive();
        async.elapse(const Duration(hours: 10));
        c.onAppActive();
        engine.changes.add(null);
        async.elapse(const Duration(hours: 1));
        expect(engine.syncCalls, isEmpty);
        expect(c.status.state, SyncState.paused);

        SyncStatus? manual;
        c.syncNow(full: true).then((s) => manual = s);
        async.flushMicrotasks();
        expect(engine.syncCalls, [
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(manual!.state, SyncState.ok);

        engine.changes.add(null);
        c.onAppActive();
        async.elapse(const Duration(hours: 5));
        expect(engine.syncCalls, hasLength(1));
        expect(c.status.state, SyncState.paused);
      });
    });

    test('bấm khi lượt bấm tay đang chạy thì ghép vào, không chạy thêm', () {
      _run((async, engine, c) {
        spent(engine);
        _start(async, c);
        expect(c.status.state, SyncState.paused);
        engine.gate = Completer<void>();

        final results = <SyncStatus>[];
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();
        c.syncNow(full: true).then(results.add);
        async.flushMicrotasks();
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();

        expect(engine.syncCalls, [
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(results, hasLength(2));
        expect(results.map((r) => r.state), everyElement(SyncState.ok));
      });
    });

    test('chu kỳ tự động chạm ngưỡng thì lượt bấm tay chờ sau nó vẫn chạy', () {
      _run((async, engine, c) {
        engine
          ..gate = Completer<void>()
          ..answers.addAll([
            SyncStatus(state: SyncState.paused, monthRequests: budget.stopAt),
            SyncStatus(state: SyncState.ok, monthRequests: budget.stopAt + 5),
          ]);
        _start(async, c);

        SyncStatus? queued;
        c.syncNow(full: true).then((s) => queued = s);
        async.flushMicrotasks();
        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();

        expect(engine.syncCalls, [
          (full: false, auto: true, checkRemote: true),
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(queued!.state, SyncState.ok);
        expect(queued!.monthRequests, budget.stopAt + 5);
        expect(c.budgetLevel, SyncBudgetLevel.exhausted);

        engine.pending = true;
        async.elapse(const Duration(hours: 5));
        expect(engine.cycles, 2);
        expect(c.status.state, SyncState.paused);
      });
    });

    test('sang tháng mới có thay đổi chờ thì tự chạy, không cần start lại', () {
      _run((async, engine, c) {
        spent(engine);
        engine.pending = true;
        _start(async, c);
        expect(c.status.state, SyncState.paused);

        // Up to the first second of November.
        async.elapse(const Duration(hours: 4) - const Duration(seconds: 1));
        expect(engine.syncCalls, isEmpty);

        engine.status = const SyncStatus(state: SyncState.ok, monthRequests: 2);
        async.elapse(budget.fallbackInterval(SyncBudgetLevel.normal));
        expect(engine.syncCalls, hasLength(1));
        expect(engine.syncCalls.single.auto, isTrue);
        expect(c.status.state, SyncState.ok);
        expect(c.budgetLevel, SyncBudgetLevel.normal);
      }, start: DateTime(2026, 10, 31, 20));
    });

    test('sang tháng mới không có thay đổi chờ thì focus kế tiếp chạy', () {
      _run((async, engine, c) {
        spent(engine);
        _start(async, c);
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.syncCalls, isEmpty);
        expect(c.status.state, SyncState.paused);

        async.elapse(const Duration(minutes: 31));
        expect(c.budgetLevel, SyncBudgetLevel.normal);
        engine.status = const SyncStatus(state: SyncState.ok, monthRequests: 1);
        c.onAppActive();
        async.flushMicrotasks();
        expect(engine.syncCalls, [
          (full: false, auto: true, checkRemote: true),
        ]);
        expect(c.status.state, SyncState.ok);
      }, start: DateTime(2026, 10, 31, 23, 30));
    });

    test('sang tháng mới thì bỏ trạng thái paused và đếm lại từ 0', () {
      _run((async, engine, c) {
        spent(engine);
        _start(async, c);
        expect(c.status.state, SyncState.paused);

        // The fallback tick after midnight notices the new month.
        async.elapse(budget.fallbackInterval(SyncBudgetLevel.exhausted));
        expect(engine.syncCalls, isEmpty);
        expect(c.status.state, SyncState.idle);
        expect(c.status.monthRequests, 0);
        expect(c.status.message, isNull);
      }, start: DateTime(2026, 10, 31, 23, 30));
    });
  });

  group('bật/tắt sync tự động lúc chạy', () {
    const budget = SyncBudget.configured;
    const builtOff = SyncSettings(
      isConfigured: true,
      autoSync: false,
      space: 'nha',
    );

    void spent(_ScriptedEngine engine) {
      engine
        ..monthRequests = budget.stopAt
        ..status = SyncStatus(
          state: SyncState.ok,
          monthRequests: budget.stopAt,
        );
    }

    group('load', () {
      test('đọc một lần, báo listener, không gọi engine', () {
        _run((async, engine, c) {
          expect(c.settingsLoaded, isFalse);
          expect(c.autoSyncEnabled, isFalse);
          var notified = 0;
          c.addListener(() => notified++);

          final first = c.load();
          expect(c.load(), same(first));
          async.flushMicrotasks();

          expect(c.settingsLoaded, isTrue);
          expect(c.autoSyncEnabled, isTrue);
          expect(c.settings.autoSync, isTrue);
          expect(c.settings.space, 'nha');
          expect(notified, 1);
          expect(engine.calls, isEmpty);
        });
      });

      test('lựa chọn đã lưu thắng giá trị build', () {
        _run(
          (async, engine, c) {
            unawaited(c.load());
            async.flushMicrotasks();
            expect(c.autoSyncEnabled, isFalse);
            expect(c.settings.autoSync, isFalse);
          },
          states: MemorySyncStateStore()
            ..values[StateStoreSyncPreferences.autoSyncKey] = '0',
        );
      });

      test(
        'đọc lựa chọn lỗi thì coi như tắt, không ghi đè lựa chọn đã lưu',
        () {
          final states = _FlakyStateStore()
            ..values[StateStoreSyncPreferences.autoSyncKey] = '1'
            ..failReads = true;
          _run((async, engine, c) {
            engine.pending = true;
            _start(async, c);
            expect(c.settingsLoaded, isTrue);
            expect(c.autoSyncEnabled, isFalse);
            expect(c.settings.autoSync, isFalse);
            expect(c.status.state, SyncState.idle);

            engine.changes.add(null);
            c.onAppActive();
            async.elapse(const Duration(hours: 5));
            expect(engine.cycles, 0);
            expect(engine.calls, isNot(contains('hasLocalChanges')));
            expect(states.values[StateStoreSyncPreferences.autoSyncKey], '1');
          }, states: states);
        },
      );

      test('đọc lựa chọn lỗi rồi bật lại thì sync tự động chạy', () {
        final states = _FlakyStateStore()..failReads = true;
        _run((async, engine, c) {
          _start(async, c);
          expect(c.autoSyncEnabled, isFalse);

          expect(_setAuto(async, c, true), isTrue);
          expect(c.autoSyncEnabled, isTrue);
          expect(states.values[StateStoreSyncPreferences.autoSyncKey], '1');
          // No check of the server yet, so it checks now.
          expect(engine.syncCalls, [
            (full: false, auto: true, checkRemote: true),
          ]);
        }, states: states);
      });
    });

    test('chưa cấu hình thì setAutoSync trả false, không lưu gì', () {
      final states = MemorySyncStateStore();
      _run(
        (async, engine, c) {
          _start(async, c);
          expect(_setAuto(async, c, false), isFalse);
          expect(c.autoSyncEnabled, isTrue);
          expect(states.values, isEmpty);
          expect(engine.calls, isEmpty);
        },
        settings: const SyncSettings(
          isConfigured: false,
          autoSync: true,
          space: '',
        ),
        states: states,
      );
    });

    group('tắt', () {
      test('focus, sửa và timer không gọi engine trong 5 giờ', () {
        _run((async, engine, c) {
          engine.pending = true;
          _start(async, c);
          expect(engine.cycles, 1);

          expect(_setAuto(async, c, false), isTrue);
          expect(c.autoSyncEnabled, isFalse);
          expect(c.settings.autoSync, isFalse);
          expect(async.pendingTimers, isEmpty);

          engine.changes.add(null);
          async.elapse(c.activeRefreshAfter);
          c.onAppActive();
          engine.changes.add(null);
          async.elapse(const Duration(hours: 5));
          c.onAppActive();
          async.flushMicrotasks();

          expect(engine.cycles, 1);
          expect(engine.calls, isNot(contains('hasLocalChanges')));
          expect(async.pendingTimers, isEmpty);
        });
      });

      test('sửa rồi tắt ở giây 10 thì tới giây 30 không có chu kỳ', () {
        _run((async, engine, c) {
          _start(async, c);
          engine.changes.add(null);
          async.elapse(const Duration(seconds: 10));
          _setAuto(async, c, false);

          async.elapse(const Duration(seconds: 20));
          expect(engine.cycles, 1);
          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 1);
        });
      });

      test('tắt giữa chu kỳ thì chu kỳ đó xong, sau đó không hẹn gì', () {
        _run((async, engine, c) {
          engine
            ..pending = true
            ..gate = Completer<void>();
          _start(async, c);
          expect(c.status.isRunning, isTrue);
          // Queues a push for after the cycle.
          engine.changes.add(null);
          async.elapse(const Duration(seconds: 40));

          _setAuto(async, c, false);
          engine.gate!.complete();
          engine.gate = null;
          async.flushMicrotasks();
          expect(c.status.state, SyncState.ok);
          expect(engine.cycles, 1);

          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 1);
          expect(engine.calls, isNot(contains('hasLocalChanges')));
          expect(async.pendingTimers, isEmpty);
        });
      });

      test('tick dự phòng đang đọc thay đổi chờ thì không chạy chu kỳ', () {
        _run((async, engine, c) {
          _start(async, c);
          engine
            ..pending = true
            ..pendingGate = Completer<void>();
          async.elapse(c.autoSyncInterval);
          expect(engine.calls.last, 'hasLocalChanges');

          _setAuto(async, c, false);
          engine.pendingGate!.complete();
          engine.pendingGate = null;
          async.flushMicrotasks();

          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 1);
          expect(async.pendingTimers, isEmpty);
        });
      });

      test('Đồng bộ ngay vẫn chạy đúng một chu kỳ full bấm tay', () {
        _run((async, engine, c) {
          _start(async, c);
          _setAuto(async, c, false);

          unawaited(c.syncNow(full: true));
          async.flushMicrotasks();
          expect(engine.syncCalls, [
            (full: false, auto: true, checkRemote: true),
            (full: true, auto: false, checkRemote: true),
          ]);

          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 2);
        });
      });

      test('bấm khi lượt bấm tay full đang chạy thì ghép vào lượt đó', () {
        _run((async, engine, c) {
          _start(async, c);
          engine.gate = Completer<void>();

          final results = <SyncStatus>[];
          c.syncNow(full: true).then(results.add);
          async.flushMicrotasks();
          c.syncNow(full: true).then(results.add);
          async.flushMicrotasks();
          expect(results, isEmpty);
          engine.gate!.complete();
          engine.gate = null;
          async.flushMicrotasks();

          expect(results, hasLength(2));
          expect(results.map((r) => r.state), everyElement(SyncState.ok));
          async.elapse(const Duration(hours: 5));
          expect(engine.syncCalls, [
            (full: true, auto: false, checkRemote: true),
          ]);
          expect(async.pendingTimers, isEmpty);
        }, settings: builtOff);
      });

      test('tắt giữa chu kỳ tự động rồi bấm thì vẫn có lượt bấm tay chạy '
          'tiếp, sau đó không hẹn gì', () {
        _run((async, engine, c) {
          engine.gate = Completer<void>();
          _start(async, c);
          _setAuto(async, c, false);

          SyncStatus? queued;
          c.syncNow(full: true).then((s) => queued = s);
          async.flushMicrotasks();
          engine.gate!.complete();
          engine.gate = null;
          async.flushMicrotasks();

          expect(engine.syncCalls, [
            (full: false, auto: true, checkRemote: true),
            (full: true, auto: false, checkRemote: true),
          ]);
          expect(queued!.state, SyncState.ok);
          engine.pending = true;
          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 2);
          expect(async.pendingTimers, isEmpty);
        });
      });

      test('focus chỉ nhận ra tháng mới để gỡ paused, không gọi engine', () {
        _run((async, engine, c) {
          spent(engine);
          _start(async, c);
          expect(c.status.state, SyncState.paused);
          _setAuto(async, c, false);

          async.elapse(const Duration(minutes: 31));
          expect(c.status.state, SyncState.paused);
          c.onAppActive();
          async.flushMicrotasks();

          expect(c.status.state, SyncState.idle);
          expect(c.status.monthRequests, 0);
          expect(engine.syncCalls, isEmpty);
          expect(engine.calls, isNot(contains('hasLocalChanges')));
        }, start: DateTime(2026, 10, 31, 23, 30));
      });
    });

    group('bật lại', () {
      test('còn thay đổi chờ thì một chu kỳ trong vòng pushDelay', () {
        _run((async, engine, c) {
          _start(async, c);
          _setAuto(async, c, false);
          async.elapse(const Duration(minutes: 1));
          engine.pending = true;

          expect(_setAuto(async, c, true), isTrue);
          expect(c.autoSyncEnabled, isTrue);
          expect(engine.cycles, 1);
          async.elapse(c.pushDelay - const Duration(seconds: 1));
          expect(engine.cycles, 1);
          async.elapse(const Duration(seconds: 1));
          expect(engine.cycles, 2);
          expect(engine.syncCalls.last.auto, isTrue);

          async.elapse(const Duration(minutes: 1));
          expect(engine.cycles, 2);
        });
      });

      test('không có thay đổi chờ, chưa tới R thì không chạy; vẫn hẹn '
          'timer dự phòng', () {
        _run((async, engine, c) {
          _start(async, c);
          _setAuto(async, c, false);
          async.elapse(const Duration(minutes: 5));

          _setAuto(async, c, true);
          async.elapse(const Duration(hours: 1));
          expect(engine.cycles, 1);

          // The fallback timer counts from the moment it was turned on.
          engine.pending = true;
          async.elapse(
            c.autoSyncInterval -
                const Duration(hours: 1) -
                const Duration(seconds: 1),
          );
          expect(engine.cycles, 1);
          async.elapse(const Duration(seconds: 1));
          expect(engine.cycles, 2);
        });
      });

      test('không có thay đổi chờ, đã quá R thì một chu kỳ kiểm server', () {
        _run((async, engine, c) {
          _start(async, c);
          _setAuto(async, c, false);
          async.elapse(c.activeRefreshAfter);

          _setAuto(async, c, true);
          expect(engine.cycles, 2);
          expect(engine.syncCalls.last, (
            full: false,
            auto: true,
            checkRemote: true,
          ));
        });
      });

      test('bật/tắt liền 5 lần không thêm chu kỳ kiểm server nào', () {
        _run((async, engine, c) {
          _start(async, c);
          async.elapse(const Duration(minutes: 1));

          // Queued all at once, then one by one.
          for (var i = 0; i < 5; i++) {
            unawaited(c.setAutoSync(false));
            unawaited(c.setAutoSync(true));
          }
          async.flushMicrotasks();
          for (var i = 0; i < 5; i++) {
            _setAuto(async, c, false);
            _setAuto(async, c, true);
          }
          expect(engine.cycles, 1);
          expect(c.autoSyncEnabled, isTrue);

          // Once R has passed, the first time back on checks; the rest not.
          async.elapse(c.activeRefreshAfter - const Duration(minutes: 1));
          for (var i = 0; i < 5; i++) {
            _setAuto(async, c, false);
            _setAuto(async, c, true);
          }
          expect(engine.cycles, 2);
          expect(engine.syncCalls.where((s) => s.checkRemote), hasLength(2));
        });
      });

      test('hết ngân sách thì paused, sang tháng mới timer dự phòng chạy', () {
        _run(
          (async, engine, c) {
            spent(engine);
            engine.pending = true;
            _start(async, c);
            expect(c.status.state, SyncState.idle);

            expect(_setAuto(async, c, true), isTrue);
            expect(engine.syncCalls, isEmpty);
            expect(c.status.state, SyncState.paused);

            // Up to the first second of November.
            async.elapse(const Duration(hours: 4) - const Duration(seconds: 1));
            expect(engine.syncCalls, isEmpty);

            engine.status = const SyncStatus(
              state: SyncState.ok,
              monthRequests: 2,
            );
            async.elapse(budget.fallbackInterval(SyncBudgetLevel.normal));
            expect(engine.syncCalls, hasLength(1));
            expect(engine.syncCalls.single.auto, isTrue);
            expect(c.status.state, SyncState.ok);
          },
          settings: builtOff,
          start: DateTime(2026, 10, 31, 20),
        );
      });

      group('giữa lượt bấm tay', () {
        /// Starts [c] with automatic sync off and leaves the user's full sync
        /// running until the test opens [_ScriptedEngine.gate].
        void manualRunning(
          FakeAsync async,
          _ScriptedEngine engine,
          SyncController c,
        ) {
          _start(async, c);
          engine.gate = Completer<void>();
          unawaited(c.syncNow(full: true));
          async.flushMicrotasks();
          expect(c.status.isRunning, isTrue);
        }

        void finish(FakeAsync async, _ScriptedEngine engine) {
          engine.gate!.complete();
          engine.gate = null;
          async.flushMicrotasks();
        }

        test('có thay đổi chờ thì đẩy trong pushDelay sau lượt đó', () {
          _run((async, engine, c) {
            manualRunning(async, engine, c);
            // Made while off, so nothing is scheduled for it.
            engine
              ..pending = true
              ..changes.add(null);
            async.flushMicrotasks();
            expect(_setAuto(async, c, true), isTrue);
            async.elapse(const Duration(seconds: 10));
            finish(async, engine);
            expect(engine.cycles, 1);

            async.elapse(c.pushDelay - const Duration(seconds: 1));
            expect(engine.cycles, 1);
            async.elapse(const Duration(seconds: 1));
            expect(engine.cycles, 2);
            expect(engine.syncCalls.last.auto, isTrue);

            async.elapse(const Duration(minutes: 1));
            expect(engine.cycles, 2);
          }, settings: builtOff);
        });

        test('bật rồi tắt lại trước khi lượt đó xong thì không làm gì', () {
          _run((async, engine, c) {
            manualRunning(async, engine, c);
            engine.pending = true;
            _setAuto(async, c, true);
            _setAuto(async, c, false);
            finish(async, engine);

            async.elapse(const Duration(hours: 5));
            expect(engine.cycles, 1);
            expect(engine.calls, isNot(contains('hasLocalChanges')));
            expect(async.pendingTimers, isEmpty);
          }, settings: builtOff);
        });

        test('không có thay đổi chờ thì chỉ hẹn timer dự phòng', () {
          _run((async, engine, c) {
            manualRunning(async, engine, c);
            _setAuto(async, c, true);
            finish(async, engine);
            expect(engine.calls.last, 'hasLocalChanges');

            async.elapse(const Duration(hours: 1));
            expect(engine.cycles, 1);
            engine.pending = true;
            async.elapse(
              c.autoSyncInterval -
                  const Duration(hours: 1) -
                  const Duration(seconds: 1),
            );
            expect(engine.cycles, 1);
            async.elapse(const Duration(seconds: 1));
            expect(engine.cycles, 2);
            expect(engine.syncCalls.last.auto, isTrue);
          }, settings: builtOff);
        });

        test('hết ngân sách sau lượt đó thì paused', () {
          _run((async, engine, c) {
            manualRunning(async, engine, c);
            engine
              ..pending = true
              ..status = SyncStatus(
                state: SyncState.ok,
                monthRequests: budget.stopAt,
              );
            _setAuto(async, c, true);
            finish(async, engine);

            expect(c.budgetLevel, SyncBudgetLevel.exhausted);
            expect(c.status.state, SyncState.paused);
            async.elapse(const Duration(hours: 5));
            expect(engine.cycles, 1);
          }, settings: builtOff);
        });
      });
    });

    group('lưu lựa chọn', () {
      test('đã tắt thì lần mở sau không có chu kỳ hay timer tự động', () {
        fakeAsync((async) {
          final states = MemorySyncStateStore();
          final engine = _ScriptedEngine()..pending = true;
          final a = _controllerFor(engine, FakeClock(async), budget, states);
          _start(async, a);
          expect(engine.cycles, 1);
          expect(_setAuto(async, a, false), isTrue);
          a.dispose();
          expect(states.values[StateStoreSyncPreferences.autoSyncKey], '0');

          final b = _controllerFor(engine, FakeClock(async), budget, states);
          _start(async, b);
          expect(b.autoSyncEnabled, isFalse);
          expect(b.settings.autoSync, isFalse);
          engine.changes.add(null);
          b.onAppActive();
          async.elapse(const Duration(hours: 5));

          expect(engine.cycles, 1);
          expect(engine.calls, isNot(contains('hasLocalChanges')));
          expect(async.pendingTimers, isEmpty);
          b.dispose();
          async.flushMicrotasks();
        });
      });

      test('build tắt nhưng đã lưu bật thì start() chạy chu kỳ đầu', () {
        _run(
          (async, engine, c) {
            _start(async, c);
            expect(c.autoSyncEnabled, isTrue);
            expect(engine.syncCalls, [
              (full: false, auto: true, checkRemote: true),
            ]);
          },
          settings: builtOff,
          states: MemorySyncStateStore()
            ..values[StateStoreSyncPreferences.autoSyncKey] = '1',
        );
      });
    });

    group('đổi trước khi start() xong', () {
      test('tắt trước start() thì start() không chạy chu kỳ', () {
        _run((async, engine, c) {
          expect(_setAuto(async, c, false), isTrue);
          _start(async, c);
          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 0);
          expect(c.autoSyncEnabled, isFalse);
        });
      });

      test('tắt ngay trước start() chưa flush thì không chạy chu kỳ', () {
        _run((async, engine, c) {
          unawaited(c.setAutoSync(false));
          unawaited(c.start());
          async.flushMicrotasks();
          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 0);
          expect(c.autoSyncEnabled, isFalse);
        });
      });

      test('tắt ngay sau start() chưa flush thì không chạy chu kỳ', () {
        final states = _FlakyStateStore();
        _run((async, engine, c) {
          // Made in fake time, so that completing it runs in fake time.
          states.writeGate = Completer<void>();
          engine.pending = true;
          unawaited(c.start());
          unawaited(c.setAutoSync(false));
          // start() waits for the choice still being saved.
          async.flushMicrotasks();
          expect(engine.cycles, 0);
          expect(c.status.state, SyncState.notConfigured);

          states.writeGate!.complete();
          states.writeGate = null;
          async.flushMicrotasks();
          expect(c.status.state, SyncState.idle);
          async.elapse(const Duration(hours: 5));
          expect(engine.cycles, 0);
          expect(engine.calls, isNot(contains('hasLocalChanges')));
          expect(async.pendingTimers, isEmpty);
          expect(c.autoSyncEnabled, isFalse);
        }, states: states);
      });

      test('bật ngay sau start() chưa flush thì đúng một chu kỳ đầu', () {
        _run((async, engine, c) {
          unawaited(c.start());
          unawaited(c.setAutoSync(true));
          async.flushMicrotasks();
          expect(engine.syncCalls, [
            (full: false, auto: true, checkRemote: true),
          ]);
          async.elapse(const Duration(minutes: 5));
          expect(engine.cycles, 1);
          expect(c.autoSyncEnabled, isTrue);
        }, settings: builtOff);
      });
    });

    test('lưu lỗi thì trả false, giữ trạng thái và timer, báo listener', () {
      final states = _FlakyStateStore();
      _run((async, engine, c) {
        _start(async, c);
        // Arms the push timer next to the fallback one.
        engine.changes.add(null);
        async.flushMicrotasks();
        final timers = async.pendingTimers.toList();
        expect(timers, hasLength(2));
        var notified = 0;
        c.addListener(() => notified++);

        states.failWrites = true;
        expect(_setAuto(async, c, false), isFalse);

        expect(c.autoSyncEnabled, isTrue);
        expect(c.settings.autoSync, isTrue);
        expect(notified, 1);
        expect(async.pendingTimers, timers);
        expect(states.values, isNot(contains('sync_auto')));
        async.elapse(c.pushDelay);
        expect(engine.cycles, 2);
      }, states: states);
    });
  });
}
