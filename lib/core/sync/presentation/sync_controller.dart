import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/clock.dart';
import '../../domain/result.dart';
import '../../domain/usecase.dart';
import '../domain/entities/sync_budget.dart';
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
/// Every request counts against the user's monthly budget ([SyncBudget]), so
/// cycles run on demand: a local change pushes after [pushDelay], coming back
/// to the app pulls through [onAppActive], and the timer is only a fallback
/// for what other devices did meanwhile. An idle cycle costs one request (see
/// ParseSyncEngine).
///
/// Those intervals follow [budgetLevel]: they stretch once this device nears
/// its share of the budget, and automatic cycles stop once it is spent, until
/// the month changes. [syncNow] is the user's button and always runs.
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
    this._budget = SyncBudget.configured,
  });

  final RunSync _runSync;
  final HasPendingChanges _hasPendingChanges;
  final GetMonthRequests _getMonthRequests;
  final WatchLocalChanges _watchLocalChanges;
  final GetSyncSettings _getSyncSettings;
  final Clock _clock;
  final SyncBudget _budget;

  /// Why automatic cycles are held back, shown with [SyncState.paused].
  static const String _pausedMessage =
      'Đã dùng hết ngân sách request tháng này của máy này — sync tự động tạm '
      'dừng tới tháng sau';

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

  /// When the last cycle that asked the server what changed started.
  DateTime? _lastCheckStarted;

  /// When [SyncStatus.monthRequests] was last read, to tell which month it
  /// counts.
  DateTime? _monthReadAt;

  /// A change or a request arrived while a cycle was running.
  bool _syncAgain = false;

  /// How the last cycle went, or where the sync stands between cycles.
  SyncStatus get status => _status;

  /// How this build is set up to sync. Reads as not configured before
  /// [start].
  SyncSettings get settings => _settings;

  bool get isConfigured => _settings.isConfigured;

  bool get _autoSync => _settings.isConfigured && _settings.autoSync;

  /// The monthly request budget this controller keeps to.
  SyncBudget get budget => _budget;

  /// How close this device is to its share of [budget] this month.
  SyncBudgetLevel get budgetLevel => _budget.levelFor(_usedThisMonth);

  /// Fallback cadence, counted from the end of the last cycle.
  Duration get autoSyncInterval => _budget.fallbackInterval(budgetLevel);

  /// Quiet time after a local change before it goes out, so a burst of edits
  /// travels in one cycle.
  Duration get pushDelay => _budget.pushDelay(budgetLevel);

  /// Coming back to the app asks the server what changed only when the last
  /// check started at least this long ago.
  Duration get activeRefreshAfter => _budget.appActiveRefresh(budgetLevel);

  /// Requests this device made this month, as last read: a reading from an
  /// earlier month counts as none, the tally having started over. Answered
  /// without touching the disk.
  int get _usedThisMonth {
    final read = _monthReadAt;
    if (read == null || !_sameMonth(read, _clock.now())) return 0;
    return _status.monthRequests ?? 0;
  }

  static bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  /// Whether the last check of the server is old enough for a push to ask
  /// again what changed.
  bool get _remoteCheckDue {
    final last = _lastCheckStarted;
    return last == null || _clock.now().difference(last) >= activeRefreshAfter;
  }

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
    _monthReadAt = _clock.now();
    if (watched case Ok(:final value)) {
      _localChanges = value.listen((_) => _requestPush());
    }
    _notify();

    // The cycle schedules the next one when it ends.
    if (_autoSync) _autoCycle(checkRemote: true);
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
  /// unless a cycle is running, the last check of the server started less
  /// than [activeRefreshAfter] ago, or the budget is spent.
  void onAppActive() {
    if (!_started || !_autoSync || _status.isRunning) return;
    _rollMonth();
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    final last = _lastCheckStarted;
    if (last != null && _clock.now().difference(last) < activeRefreshAfter) {
      return;
    }
    _autoCycle(checkRemote: true);
  }

  /// Runs a sync cycle now, as the user asked, and returns how it went. Runs
  /// even once the budget is spent.
  ///
  /// [full] pulls every class whatever the change counters say — for the
  /// "Đồng bộ ngay" button, where the user expects a fresh look. Called while
  /// a cycle runs, it queues a push for after that cycle instead.
  Future<SyncStatus> syncNow({bool full = false}) =>
      _cycle(full: full, auto: false, checkRemote: true);

  /// Runs a cycle no one asked for, unless this device has spent its share of
  /// the budget this month.
  void _autoCycle({required bool checkRemote}) {
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    unawaited(_cycle(full: false, auto: true, checkRemote: checkRemote));
  }

  Future<SyncStatus> _cycle({
    required bool full,
    required bool auto,
    required bool checkRemote,
  }) async {
    // A focus event can beat start(); start() runs the first cycle itself.
    if (!_started || _disposed || !_settings.isConfigured) return _status;
    if (_status.isRunning) {
      _syncAgain = true;
      return _status;
    }
    // This cycle pushes everything pending; nothing left for those timers.
    _pushTimer?.cancel();
    _fallbackTimer?.cancel();
    if (checkRemote) _lastCheckStarted = _clock.now();
    _status = SyncStatus(
      state: SyncState.running,
      lastSyncAt: _status.lastSyncAt,
      monthRequests: _status.monthRequests,
    );
    _notify();

    final result = await _runSync(
      RunSyncParams(full: full, auto: auto, checkRemote: checkRemote),
    );
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
    if (outcome.monthRequests != null) _monthReadAt = _clock.now();
    if (_disposed) return _status;
    _notify();

    _scheduleFallback();
    if (_syncAgain) {
      _syncAgain = false;
      _requestPush();
    }
    return _status;
  }

  /// Pushes local changes shortly, coalescing a burst into one cycle. Once
  /// the budget is spent they stay pending until a cycle may run.
  void _requestPush() {
    if (!_started || _disposed || !_autoSync) return;
    _pushTimer?.cancel();
    _rollMonth();
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    _pushTimer = Timer(pushDelay, () {
      _rollMonth();
      _autoCycle(checkRemote: _remoteCheckDue);
    });
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
  ///
  /// With the budget spent it only looks at the clock, so the first tick of
  /// the next month sends what piled up.
  Future<void> _fallbackTick() async {
    _rollMonth();
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    final pending = await _hasPendingChanges(const NoParams());
    if (_disposed) return;
    if (pending case Ok(value: true)) {
      _autoCycle(checkRemote: _remoteCheckDue);
    } else {
      _scheduleFallback();
    }
  }

  /// Holds automatic cycles back while the budget is spent: the status says
  /// why, and the fallback timer keeps watching for the month to change.
  void _pause() {
    if (_disposed || _status.isRunning) return;
    if (_status.state != SyncState.paused) {
      _status = SyncStatus(
        state: SyncState.paused,
        message: _pausedMessage,
        lastSyncAt: _status.lastSyncAt,
        monthRequests: _status.monthRequests,
      );
      _notify();
    }
    if (_autoSync && !(_fallbackTimer?.isActive ?? false)) _scheduleFallback();
  }

  /// Once the month has changed since the tally was read, starts it over at
  /// zero, as the engine does, and lifts a pause.
  void _rollMonth() {
    final read = _monthReadAt;
    final now = _clock.now();
    if (read == null || _sameMonth(read, now) || _status.isRunning) return;
    _monthReadAt = now;
    final paused = _status.state == SyncState.paused;
    _status = SyncStatus(
      state: paused ? SyncState.idle : _status.state,
      message: paused ? null : _status.message,
      lastSyncAt: _status.lastSyncAt,
      pushed: _status.pushed,
      pulled: _status.pulled,
      monthRequests: _status.monthRequests == null ? null : 0,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
