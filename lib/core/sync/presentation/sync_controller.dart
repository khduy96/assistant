import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/clock.dart';
import '../../domain/result.dart';
import '../../domain/usecase.dart';
import '../domain/entities/sync_budget.dart';
import '../domain/entities/sync_settings.dart';
import '../domain/entities/sync_status.dart';
import '../domain/usecases/get_auto_sync_choice.dart';
import '../domain/usecases/get_month_requests.dart';
import '../domain/usecases/get_sync_settings.dart';
import '../domain/usecases/has_pending_changes.dart';
import '../domain/usecases/run_sync.dart';
import '../domain/usecases/set_auto_sync_choice.dart';
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
/// the month changes. [syncNow] is the user's sync and always runs.
///
/// A press of the "Đồng bộ ngay" button goes through [pressSyncNow], which
/// locks further presses for [manualSyncCooldown] ([manualSyncLocked]), so a
/// burst of presses costs one cycle. [syncNow] itself has no lock, and no
/// automatic trigger looks at it. The lock lives in memory only.
///
/// The user turns automatic cycles on or off on this device with
/// [setAutoSync]; the choice is kept and beats the build setting. Off, every
/// automatic trigger is ignored and local changes wait for [syncNow].
///
/// Only talks to use cases. Every trigger is ignored until [start].
class SyncController extends ChangeNotifier {
  SyncController({
    required this._runSync,
    required this._hasPendingChanges,
    required this._getMonthRequests,
    required this._watchLocalChanges,
    required this._getSyncSettings,
    required this._getAutoSyncChoice,
    required this._setAutoSyncChoice,
    required this._clock,
    this._budget = SyncBudget.configured,
  });

  final RunSync _runSync;
  final HasPendingChanges _hasPendingChanges;
  final GetMonthRequests _getMonthRequests;
  final WatchLocalChanges _watchLocalChanges;
  final GetSyncSettings _getSyncSettings;
  final GetAutoSyncChoice _getAutoSyncChoice;
  final SetAutoSyncChoice _setAutoSyncChoice;
  final Clock _clock;
  final SyncBudget _budget;

  /// Why automatic cycles are held back, shown with [SyncState.paused].
  static const String _pausedMessage =
      'Đã dùng hết ngân sách request tháng này của máy này — sync tự động tạm '
      'dừng tới tháng sau';

  /// What [settings] says until [load] has read the real ones.
  static const SyncSettings _unknownSettings = SyncSettings(
    isConfigured: false,
    autoSync: false,
    space: '',
  );

  /// The settings as the build has them.
  SyncSettings _built = _unknownSettings;

  /// What the user chose on this device; null when they never did, false
  /// when it could not be read.
  bool? _choice;

  /// [_built] with [_choice] applied.
  SyncSettings _settings = _unknownSettings;

  SyncStatus _status = const SyncStatus();
  Future<void>? _loading;
  bool _loaded = false;
  bool _started = false;

  /// [start] has finished: from here on a change of [autoSyncEnabled]
  /// rearranges the timers itself.
  bool _ready = false;
  bool _disposed = false;

  /// The choices being saved, one after the other.
  Future<void> _writes = Future<void>.value();

  StreamSubscription<void>? _localChanges;
  Timer? _pushTimer;
  Timer? _fallbackTimer;

  /// When the last cycle that asked the server what changed started.
  DateTime? _lastCheckStarted;

  /// When [SyncStatus.monthRequests] was last read, to tell which month it
  /// counts.
  DateTime? _monthReadAt;

  /// The cycle running now, and whether it is the user's full sync, which a
  /// press arriving meanwhile joins.
  Future<SyncStatus>? _current;
  bool _currentManualFull = false;

  /// An automatic trigger fired while a cycle was running: push after it.
  bool _pushAgain = false;

  /// Automatic cycles were turned back on while a cycle was running.
  bool _resumeAgain = false;

  /// The user's sync asked for while another cycle was running: runs right
  /// after it, once for every such press, full when any of them was.
  Completer<SyncStatus>? _manualAgain;
  bool _manualAgainFull = false;

  /// When [pressSyncNow] last took the lock, and whether the cycle it asked
  /// for has not ended yet.
  DateTime? _pressedAt;
  bool _pressRunning = false;

  /// How the last cycle went, or where the sync stands between cycles.
  SyncStatus get status => _status;

  /// How sync is set up on this device: the build's settings, with
  /// [SyncSettings.autoSync] as applied here ([autoSyncEnabled]). Reads as
  /// not configured before [load].
  SyncSettings get settings => _settings;

  bool get isConfigured => _settings.isConfigured;

  /// Whether [load] has read the settings and the user's choice.
  bool get settingsLoaded => _loaded;

  /// Whether automatic cycles are on here: the user's choice, or the build
  /// setting when they never chose. False before [load].
  bool get autoSyncEnabled => _settings.autoSync;

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

  /// How long a press of [pressSyncNow] locks the next one, counted from the
  /// press.
  static const Duration manualSyncCooldown = Duration(seconds: 30);

  /// Whether [pressSyncNow] would turn a press away now: less than
  /// [manualSyncCooldown] has passed since the last press it took, or the
  /// cycle that press asked for has not ended. Automatic cycles and [syncNow]
  /// ignore it.
  ///
  /// Listeners hear when the lock is taken and when that cycle ends, but not
  /// when the time runs out; whoever shows the lock waits
  /// [manualSyncCooldownLeft] and asks again.
  bool get manualSyncLocked =>
      _pressRunning || manualSyncCooldownLeft > Duration.zero;

  /// Time left until the clock alone no longer holds the lock;
  /// [Duration.zero] once it does not, or before any press. Never more than
  /// [manualSyncCooldown]: a clock set back past the press frees it.
  Duration get manualSyncCooldownLeft {
    final pressed = _pressedAt;
    if (pressed == null) return Duration.zero;
    final elapsed = _clock.now().difference(pressed);
    if (elapsed.isNegative) return Duration.zero;
    final left = manualSyncCooldown - elapsed;
    return left > Duration.zero ? left : Duration.zero;
  }

  /// Whether the last check of the server is old enough for a push to ask
  /// again what changed.
  bool get _remoteCheckDue {
    final last = _lastCheckStarted;
    return last == null || _clock.now().difference(last) >= activeRefreshAfter;
  }

  // --------------------------------------------------------------- lifecycle

  /// Reads the build settings and the user's choice, once; later calls get
  /// the same future. Sends no request.
  ///
  /// A choice that cannot be read turns automatic cycles off for this
  /// session, whatever the build says; what is stored is left alone, and
  /// [setAutoSync] still works.
  Future<void> load() => _loading ??= _load(notify: true);

  Future<void> _load({required bool notify}) async {
    if (await _getSyncSettings(const NoParams()) case Ok(:final value)) {
      _built = value;
    }
    _choice = switch (await _getAutoSyncChoice(const NoParams())) {
      Ok(:final value) => value,
      Err() => false,
    };
    _loaded = true;
    _applyChoice();
    if (notify) _notify();
  }

  void _applyChoice() {
    _settings = SyncSettings(
      isConfigured: _built.isConfigured,
      autoSync: _choice ?? _built.autoSync,
      space: _built.space,
    );
  }

  /// Reads the settings, starts listening for local changes and, when
  /// automatic sync is on, runs the first cycle. Call once every list is
  /// loaded. Safe to call twice.
  ///
  /// Unconfigured, the status becomes [SyncState.notConfigured] and nothing
  /// here touches the engine again.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // The status set below tells listeners the settings are in.
    await (_loading ??= _load(notify: false));
    if (_disposed) return;
    if (!_settings.isConfigured) {
      _status = const SyncStatus(state: SyncState.notConfigured);
      _notify();
      return;
    }

    final month = await _getMonthRequests(const NoParams());
    final watched = await _watchLocalChanges(const NoParams());
    // A choice still being saved decides whether the first cycle runs.
    await _writesDone();
    if (_disposed) return;
    _status = SyncStatus(
      state: SyncState.idle,
      monthRequests: month.valueOrNull,
    );
    _monthReadAt = _clock.now();
    if (watched case Ok(:final value)) {
      _localChanges = value.listen((_) => _requestPush());
    }
    _ready = true;
    _notify();

    // The cycle schedules the next one when it ends.
    if (_autoSync) _autoCycle(checkRemote: true);
  }

  /// Waits for every choice saved so far, including those queued meanwhile.
  Future<void> _writesDone() async {
    Future<void> writes;
    do {
      writes = _writes;
      await writes;
    } while (!identical(writes, _writes));
  }

  /// Turns automatic cycles on or off on this device and keeps the choice.
  /// Sends no request itself.
  ///
  /// The choice is saved first and applied only once saved. Returns false,
  /// changing nothing, when it could not be saved or sync is not configured.
  /// Calls run one after the other, in order.
  ///
  /// Off, the push and fallback timers stop; a cycle already running ends
  /// normally. On again, it acts as [onAppActive] plus a push of what is
  /// still pending, once a cycle running meanwhile has ended.
  Future<bool> setAutoSync(bool enabled) {
    final saved = _writes.then((_) => _saveChoice(enabled));
    _writes = saved.then<void>((_) {}, onError: (Object _) {});
    return saved;
  }

  Future<bool> _saveChoice(bool enabled) async {
    await load();
    if (_disposed || !_settings.isConfigured) return false;
    final saved = await _setAutoSyncChoice(enabled);
    if (_disposed) return saved is Ok;
    if (saved is Err) {
      // Nothing changed, but the control redraws from what is applied.
      _notify();
      return false;
    }
    final wasOn = _autoSync;
    _choice = enabled;
    _applyChoice();
    _notify();
    // Until then start() reads the choice itself.
    if (_ready && wasOn != _autoSync) {
      if (_autoSync) {
        unawaited(_resumeAutoSync());
      } else {
        _haltAutoSync();
      }
    }
    return true;
  }

  /// Automatic cycles were turned off: nothing more is scheduled.
  void _haltAutoSync() {
    _pushTimer?.cancel();
    _fallbackTimer?.cancel();
    _resumeAgain = false;
  }

  /// Automatic cycles were turned back on: pushes what waited, else checks
  /// the server only when [onAppActive] would, and arms the fallback timer
  /// either way. With the budget spent it pauses until the month changes.
  /// Called while a cycle runs, it does all this once that cycle ends.
  Future<void> _resumeAutoSync() async {
    if (_status.isRunning) {
      _resumeAgain = true;
      return;
    }
    _rollMonth();
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    final pending = await _hasPendingChanges(const NoParams());
    // Turned off again meanwhile.
    if (_disposed || !_autoSync) return;
    // A cycle began meanwhile.
    if (_status.isRunning) {
      _resumeAgain = true;
      return;
    }
    if (pending case Ok(value: true)) {
      _requestPush();
    } else if (_remoteCheckDue) {
      _autoCycle(checkRemote: true);
      return;
    }
    _scheduleFallback();
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
  ///
  /// With automatic sync off it only notices a new month, so that a pause
  /// from the month before lifts.
  void onAppActive() {
    if (!_started || _status.isRunning) return;
    _rollMonth();
    if (!_autoSync) return;
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
  /// "Đồng bộ ngay" button, where the user expects a fresh look.
  ///
  /// Called while the user's full sync runs, it returns how that one went
  /// and costs nothing more. Called while any other cycle runs, it queues one
  /// cycle of the user's for right after it — full when any press waiting
  /// was — and every press waiting returns how that one went.
  ///
  /// Has no lock: every call is taken. A press of the user's goes through
  /// [pressSyncNow] instead, which locks for [manualSyncCooldown].
  Future<SyncStatus> syncNow({bool full = false}) =>
      _cycle(full: full, auto: false, checkRemote: true);

  /// The "Đồng bộ ngay" button: a full [syncNow], unless [manualSyncLocked],
  /// in which case it does nothing, sends nothing and returns null.
  ///
  /// Takes the lock before it first waits, so two presses in a row cost one
  /// cycle. The lock holds for [manualSyncCooldown] from the press, failed
  /// cycle or not, and until the cycle it asked for ends — one queued after
  /// a running cycle included. Listeners hear when it is taken and when that
  /// cycle ends.
  Future<SyncStatus?> pressSyncNow() async {
    if (manualSyncLocked) return null;
    _pressedAt = _clock.now();
    _pressRunning = true;
    _notify();
    try {
      return await syncNow(full: true);
    } finally {
      _pressRunning = false;
      _notify();
    }
  }

  /// Runs a cycle no one asked for, unless this device has spent its share of
  /// the budget this month.
  void _autoCycle({required bool checkRemote}) {
    if (!_autoSync) return;
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    unawaited(_cycle(full: false, auto: true, checkRemote: checkRemote));
  }

  /// Runs a cycle, or, while one runs, records what was asked for: an
  /// automatic trigger becomes a push after it, a press of the user's joins
  /// their full sync or waits for the cycle queued after the running one.
  Future<SyncStatus> _cycle({
    required bool full,
    required bool auto,
    required bool checkRemote,
  }) {
    // A focus event can beat start(); start() runs the first cycle itself.
    if (!_started || _disposed || !_settings.isConfigured) {
      return Future.value(_status);
    }
    final current = _current;
    if (current != null) {
      if (auto) {
        _pushAgain = true;
        return Future.value(_status);
      }
      if (_currentManualFull) return current;
      _manualAgainFull |= full;
      return (_manualAgain ??= Completer<SyncStatus>()).future;
    }
    // Sets the status to running before it first waits.
    final cycle = _runCycle(full: full, auto: auto, checkRemote: checkRemote);
    _current = cycle;
    _currentManualFull = !auto && full;
    return cycle;
  }

  Future<SyncStatus> _runCycle({
    required bool full,
    required bool auto,
    required bool checkRemote,
  }) async {
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
    final done = _status;
    _current = null;
    final manual = _manualAgain;
    if (_disposed) {
      _manualAgain = null;
      manual?.complete(done);
      return done;
    }
    _notify();

    if (manual != null) {
      // The user's cycle runs whatever the switch and the budget say, and
      // pushes everything pending; what follows it is scheduled when it ends.
      final again = _manualAgainFull;
      _manualAgain = null;
      _manualAgainFull = false;
      _pushAgain = false;
      manual.complete(_cycle(full: again, auto: false, checkRemote: true));
      return done;
    }
    _scheduleFallback();
    if (_pushAgain) {
      _pushAgain = false;
      _requestPush();
    }
    if (_resumeAgain) {
      _resumeAgain = false;
      if (_autoSync) unawaited(_resumeAutoSync());
    }
    return done;
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
      if (!_autoSync) return;
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
    if (!_autoSync) return;
    _rollMonth();
    if (budgetLevel == SyncBudgetLevel.exhausted) {
      _pause();
      return;
    }
    final pending = await _hasPendingChanges(const NoParams());
    // Turned off meanwhile.
    if (_disposed || !_autoSync) return;
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
