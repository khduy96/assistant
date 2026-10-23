import 'dart:async';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// Time as fake_async sees it, so [SyncController]'s 10-minute check moves
/// with the timers.
class FakeClock implements Clock {
  FakeClock(this._async);

  final FakeAsync _async;
  final DateTime _start = DateTime(2026, 10, 22, 9);

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

  int get cycles => calls.where((c) => c.startsWith('sync')).length;

  @override
  Future<SyncStatus> sync({bool full = false}) async {
    calls.add(full ? 'sync(full)' : 'sync');
    final wait = gate;
    if (wait != null) await wait.future;
    return super.sync(full: full);
  }

  @override
  Future<bool> hasLocalChanges() {
    calls.add('hasLocalChanges');
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

SyncController _controllerFor(_ScriptedEngine engine, Clock clock) =>
    SyncController(
      runSync: RunSync(engine),
      hasPendingChanges: HasPendingChanges(engine),
      getMonthRequests: GetMonthRequests(engine),
      watchLocalChanges: WatchLocalChanges(engine),
      getSyncSettings: GetSyncSettings(engine),
      clock: clock,
    );

/// Runs [body] in fake time with a fresh engine and controller, then disposes
/// the controller and drains what is left.
void _run(
  void Function(FakeAsync async, _ScriptedEngine engine, SyncController c)
  body, {
  SyncSettings? settings,
}) {
  fakeAsync((async) {
    final engine = _ScriptedEngine();
    if (settings != null) engine.settings = settings;
    final controller = _controllerFor(engine, FakeClock(async));
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

void main() {
  test('hằng số giữ như ClipboardStore cũ', () {
    expect(SyncController.pushDelay, const Duration(seconds: 30));
    expect(SyncController.activeRefreshAfter, const Duration(minutes: 10));
    expect(SyncController.autoSyncInterval, const Duration(hours: 2));
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
    test('chỉ pull khi chu kỳ trước bắt đầu đã từ 10 phút', () {
      _run((async, engine, c) {
        _start(async, c);

        async.elapse(const Duration(minutes: 9, seconds: 59));
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

    test('mốc 10 phút tính từ lúc chu kỳ bắt đầu, không phải lúc xong', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);
        async.elapse(const Duration(minutes: 8));
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
    test('syncNow giữa chu kỳ thì sau chu kỳ đó lên lịch đẩy tiếp', () {
      _run((async, engine, c) {
        engine.gate = Completer<void>();
        _start(async, c);

        SyncStatus? queued;
        c.syncNow(full: true).then((s) => queued = s);
        async.flushMicrotasks();
        expect(queued!.isRunning, isTrue);
        expect(engine.cycles, 1);

        engine.gate!.complete();
        engine.gate = null;
        async.flushMicrotasks();
        expect(engine.cycles, 1);

        async.elapse(const Duration(seconds: 29));
        expect(engine.cycles, 1);
        async.elapse(const Duration(seconds: 1));
        expect(engine.cycles, 2);
        expect(engine.calls.last, 'sync');
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
}
