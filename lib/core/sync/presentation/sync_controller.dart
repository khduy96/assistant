import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/clock.dart';
import '../../domain/result.dart';
import '../../domain/usecase.dart';
import '../domain/entities/sync_settings.dart';
import '../domain/entities/sync_status.dart';
import '../domain/usecases/get_month_requests.dart';
import '../domain/usecases/get_sync_settings.dart';
import '../domain/usecases/has_pending_changes.dart';
import '../domain/usecases/run_sync.dart';
import '../domain/usecases/watch_local_changes.dart';

/// When sync cycles run, and how the last one went — one button, one timer
/// and one status for clips, todos and notes alike.
///
/// Back4App's free tier meters requests, so cycles run on demand: a local
/// change pushes after [pushDelay], coming back to the app pulls through
/// [onAppActive], and the timer is only a fallback for what other devices did
/// meanwhile. An idle cycle costs one request (see ParseSyncEngine).
///
/// Only talks to use cases. Every trigger is ignored until [start].
class SyncController extends ChangeNotifier {
  SyncController({
    required this._runSync,
    required this._hasPendingChanges,
    required this._getMonthRequests,
    required this._watchLocalChanges,
    required this._getSyncSettings,
    required this._clock,
  });

  final RunSync _runSync;
  final HasPendingChanges _hasPendingChanges;
  final GetMonthRequests _getMonthRequests;
  final WatchLocalChanges _watchLocalChanges;
  final GetSyncSettings _getSyncSettings;
  final Clock _clock;

  /// Fallback cadence, counted from the end of the last cycle.
  static const Duration autoSyncInterval = Duration(hours: 2);

  /// Quiet time after a local change before it goes out, so a burst of edits
  /// travels in one cycle.
  static const Duration pushDelay = Duration(seconds: 30);

  /// Coming back to the app pulls only when the last cycle is older than this.
  static const Duration activeRefreshAfter = Duration(minutes: 10);

  /// What [settings] says until [start] has read the real ones.
  static const SyncSettings _unknownSettings = SyncSettings(
    isConfigured: false,
    autoSync: false,
    space: '',
  );

  SyncSettings _settings = _unknownSettings;
  SyncStatus _status = const SyncStatus();
  bool _started = false;
  bool _disposed = false;

  StreamSubscription<void>? _localChanges;
  Timer? _pushTimer;
  Timer? _fallbackTimer;
  DateTime? _lastSyncStarted;

  /// A change or a request arrived while a cycle was running.
  bool _syncAgain = false;

  /// How the last cycle went, or where the sync stands between cycles.
  SyncStatus get status => _status;

  /// How this build is set up to sync. Reads as not configured before
  /// [start].
  SyncSettings get settings => _settings;

  bool get isConfigured => _settings.isConfigured;

  bool get _autoSync => _settings.isConfigured && _settings.autoSync;

  // --------------------------------------------------------------- lifecycle

  /// Reads the settings, starts listening for local changes and, when
  /// automatic sync is on, runs the first cycle. Call once every list is
  /// loaded. Safe to call twice.
  ///
  /// Unconfigured, the status becomes [SyncState.notConfigured] and nothing
  /// here touches the engine again.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    if (await _getSyncSettings(const NoParams()) case Ok(:final value)) {
      _settings = value;
    }
    if (_disposed) return;
    if (!_settings.isConfigured) {
      _status = const SyncStatus(state: SyncState.notConfigured);
      _notify();
      return;
    }

    final month = await _getMonthRequests(const NoParams());
    final watched = await _watchLocalChanges(const NoParams());
    if (_disposed) return;
    _status = SyncStatus(
      state: SyncState.idle,
      monthRequests: month.valueOrNull,
    );
    if (watched case Ok(:final value)) {
      _localChanges = value.listen((_) => _requestPush());
    }
    _notify();

    // The cycle schedules the next one when it ends.
    if (_autoSync) unawaited(syncNow());
  }

  @override
  void dispose() {
    _disposed = true;
    _pushTimer?.cancel();
    _fallbackTimer?.cancel();
    _localChanges?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------- triggers

  /// The user is back (focus, restore, resume): pull what other devices did,
  /// unless a cycle is running or started less than [activeRefreshAfter] ago.
  void onAppActive() {
    if (!_started || !_autoSync || _status.isRunning) return;
    final last = _lastSyncStarted;
    if (last != null && _clock.now().difference(last) < activeRefreshAfter) {
      return;
    }
    unawaited(syncNow());
  }

  /// Runs a sync cycle now and returns how it went.
  ///
  /// [full] pulls every class whatever the change counters say — for the
  /// "Đồng bộ ngay" button, where the user expects a fresh look. Called while
  /// a cycle runs, it queues a push for after that cycle instead.
  Future<SyncStatus> syncNow({bool full = false}) async {
    // A focus event can beat start(); start() runs the first cycle itself.
    if (!_started || _disposed || !_settings.isConfigured) return _status;
    if (_status.isRunning) {
      _syncAgain = true;
      return _status;
    }
    // This cycle pushes everything pending; nothing left for those timers.
    _pushTimer?.cancel();
    _fallbackTimer?.cancel();
    _lastSyncStarted = _clock.now();
    _status = SyncStatus(
      state: SyncState.running,
      lastSyncAt: _status.lastSyncAt,
      monthRequests: _status.monthRequests,
    );
    _notify();

    final result = await _runSync(RunSyncParams(full: full));
    final outcome = switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => SyncStatus(
        state: SyncState.error,
        message: '${failure.cause ?? failure.message}',
      ),
    };
    _status = outcome.state == SyncState.ok
        ? outcome
        : SyncStatus(
            state: outcome.state,
            message: outcome.message,
            lastSyncAt: _status.lastSyncAt,
            monthRequests: outcome.monthRequests ?? _status.monthRequests,
          );
    if (_disposed) return _status;
    _notify();

    _scheduleFallback();
    if (_syncAgain) {
      _syncAgain = false;
      _requestPush();
    }
    return _status;
  }

  /// Pushes local changes shortly, coalescing a burst into one cycle.
  void _requestPush() {
    if (!_started || _disposed || !_autoSync) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDelay, () => unawaited(syncNow()));
  }

  /// Arms the fallback timer, counted from the cycle that just ended.
  void _scheduleFallback() {
    _fallbackTimer?.cancel();
    if (!_autoSync) return;
    _fallbackTimer = Timer(autoSyncInterval, () => unawaited(_fallbackTick()));
  }

  /// The fallback tick only runs a cycle when something here is still waiting
  /// to go out (a push that failed, say). Otherwise it costs nothing; what
  /// other devices did arrives on the next focus, start or manual sync.
  Future<void> _fallbackTick() async {
    final pending = await _hasPendingChanges(const NoParams());
    if (_disposed) return;
    if (pending case Ok(value: true)) {
      await syncNow();
    } else {
      _scheduleFallback();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
