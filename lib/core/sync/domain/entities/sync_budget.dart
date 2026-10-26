/// Requests per calendar month that every device in one space may spend on
/// Back4App together, as set by the user.
///
/// This is the user's own budget, not a limit Back4App imposes. To change it,
/// edit this value and rebuild; nothing else needs editing, since every
/// threshold and interval in [SyncBudget] follows from it.
///
/// [expectedSyncDevices], right below, is how many devices share the budget.
/// Each device keeps to its own share, since devices do not tell each other
/// what they spent.
const int userMonthlyRequestBudget = 10000;
const int expectedSyncDevices = 3;

/// How close this device is to its share of the monthly budget.
enum SyncBudgetLevel {
  /// Below [SyncBudget.warnAt]: automatic sync at its usual pace.
  normal,

  /// From [SyncBudget.warnAt]: automatic sync slows down.
  warning,

  /// From [SyncBudget.stopAt]: automatic sync stops until the month changes;
  /// a manual sync still runs.
  exhausted,
}

/// One device's share of the monthly request budget, and every threshold and
/// interval derived from it.
///
/// Nothing here is tuned for one budget: the intervals come from a model of
/// how a device spends requests, so a bigger budget never makes an interval
/// longer or a threshold lower, and a smaller one never does the opposite.
///
/// The model, with `dailyAllowance = deviceShare / 31`:
///
/// * `appActiveRefresh(normal)` = `720 / (0.5 × dailyAllowance)` minutes,
///   rounded up: checks on coming back to the app, spread over 720 active
///   minutes a day, spend at most half the daily allowance.
/// * `fullPullEvery(normal)` = `24 × 9 / (0.1 × dailyAllowance)` hours,
///   rounded up: full pulls, about 9 requests each, spend at most a tenth of
///   the daily allowance.
/// * `pushDelay(normal)` = 30 seconds and `fallbackInterval(normal)` = 2 hours.
/// * At [SyncBudgetLevel.warning] every interval is 4 times longer.
/// * At [SyncBudgetLevel.exhausted] automatic cycles do not run. The fallback
///   tick keeps its normal interval, since it then only checks locally whether
///   the month has changed; the other intervals stay at their warning values.
class SyncBudget {
  const SyncBudget({required this.monthlyRequests, required this.devices})
    : assert(devices > 0),
      assert(monthlyRequests >= devices);

  /// The budget this build was made with.
  static const SyncBudget configured = SyncBudget(
    monthlyRequests: userMonthlyRequestBudget,
    devices: expectedSyncDevices,
  );

  /// Percentage of [deviceShare] at which [SyncBudgetLevel.warning] starts.
  static const int warnPercent = 70;

  /// Days the share has to last: the longest month, so it lasts any month.
  static const int daysPerMonth = 31;

  /// Minutes a day the app is assumed to be in use, over which checks on
  /// coming back to the app are spread (12 hours).
  static const int activeMinutesPerDay = 720;

  /// Percentage of the daily allowance that checks on coming back to the app
  /// may spend (0.5).
  static const int appActiveSharePercent = 50;

  /// Requests one full pull is assumed to cost: every class read again, plus
  /// the ids used to notice deletes.
  static const int fullPullRequests = 9;

  /// Percentage of the daily allowance that full pulls may spend (0.1).
  static const int fullPullSharePercent = 10;

  /// How many times longer every interval gets at [SyncBudgetLevel.warning].
  static const int warningSlowdown = 4;

  /// Quiet time after a local change before it goes out, so a burst of edits
  /// travels in one cycle.
  static const Duration normalPushDelay = Duration(seconds: 30);

  /// Fallback cadence, for what other devices did meanwhile.
  static const Duration normalFallbackInterval = Duration(hours: 2);

  static const int _hoursPerDay = 24;

  /// Requests per calendar month, for every device in the space together.
  final int monthlyRequests;

  /// Devices expected to share [monthlyRequests].
  final int devices;

  /// What this device may spend in a month.
  int get deviceShare => monthlyRequests ~/ devices;

  /// Requests this month from which automatic sync slows down.
  int get warnAt => deviceShare * warnPercent ~/ 100;

  /// Requests this month from which automatic sync stops.
  int get stopAt => deviceShare;

  /// Where [used] requests this month leave this device.
  SyncBudgetLevel levelFor(int used) {
    if (used >= stopAt) return SyncBudgetLevel.exhausted;
    if (used >= warnAt) return SyncBudgetLevel.warning;
    return SyncBudgetLevel.normal;
  }

  /// Coming back to the app checks the server only when the last check is at
  /// least this old.
  Duration appActiveRefresh(SyncBudgetLevel level) => _slowed(
    level,
    // 720 / (0.5 × share / 31) minutes, in whole numbers.
    Duration(
      minutes: _ceilDiv(
        activeMinutesPerDay * daysPerMonth * 100,
        appActiveSharePercent * deviceShare,
      ),
    ),
  );

  /// A pull reads every class again, counters or not, once the last full pull
  /// is at least this old.
  Duration fullPullEvery(SyncBudgetLevel level) => _slowed(
    level,
    // 24 × 9 / (0.1 × share / 31) hours, in whole numbers.
    Duration(
      hours: _ceilDiv(
        _hoursPerDay * fullPullRequests * daysPerMonth * 100,
        fullPullSharePercent * deviceShare,
      ),
    ),
  );

  /// Quiet time after a local change before it goes out.
  Duration pushDelay(SyncBudgetLevel level) => _slowed(level, normalPushDelay);

  /// Fallback cadence, counted from the end of the last cycle.
  Duration fallbackInterval(SyncBudgetLevel level) =>
      level == SyncBudgetLevel.exhausted
      ? normalFallbackInterval
      : _slowed(level, normalFallbackInterval);

  static Duration _slowed(SyncBudgetLevel level, Duration normal) =>
      level == SyncBudgetLevel.normal ? normal : normal * warningSlowdown;

  static int _ceilDiv(int a, int b) => (a + b - 1) ~/ b;
}
