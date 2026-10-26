import '../../presentation/format.dart';
import '../domain/entities/sync_budget.dart';
import '../domain/entities/sync_settings.dart';
import '../domain/entities/sync_status.dart';

/// Tooltip of the sync button: how the last cycle went, what this device has
/// spent of its share of [budget] this month, and what [level] means for
/// automatic sync. When `settings.autoSync` is off it says so and drops the
/// warning line. [now] is the time "lần cuối" is counted back from.
///
/// [manualCooldown] is the full length of the lock after a manual sync, not
/// the time left; when given, a fixed last line says the button can be
/// pressed again after that long. Null leaves the text unchanged.
///
/// The budget is the user's own, so the text never calls it a Back4App limit.
String syncTooltip({
  required SyncStatus status,
  required SyncSettings settings,
  required SyncBudget budget,
  required SyncBudgetLevel level,
  required DateTime now,
  Duration? manualCooldown,
}) {
  if (status.state == SyncState.notConfigured) {
    return 'Chưa cấu hình — build với --dart-define-from-file=.env để bật đồng bộ';
  }
  final spent = status.monthRequests == null
      ? ''
      : '\n${status.monthRequests} / ${budget.deviceShare}'
            ' request tháng này (máy này)';
  // Off: nothing automatic to thin out, so no warning line; the exhausted
  // line stays so turning it back on is known not to run before next month.
  final off = settings.autoSync
      ? ''
      : '\nSync tự động đang tắt — vẫn bấm để đồng bộ tay được';
  final note =
      status.state == SyncState.paused || level == SyncBudgetLevel.exhausted
      ? '\nĐã hết ngân sách request tháng này của máy này — sync tự động tạm'
            ' dừng tới tháng sau, vẫn bấm để đồng bộ tay được'
      : level == SyncBudgetLevel.warning && settings.autoSync
      ? '\nSắp hết ngân sách request tháng này nên sync tự động thưa hơn'
      : '';
  final head = switch (status.state) {
    SyncState.error => 'Đồng bộ lỗi: ${status.message}',
    SyncState.ok =>
      status.lastSyncAt == null
          ? 'Đồng bộ ngay'
          : 'Đồng bộ lần cuối ${formatRelative(status.lastSyncAt!, now: now)}'
                ' · đẩy ${status.pushed}, nhận ${status.pulled}',
    _ => 'Đồng bộ ngay (${settings.space})',
  };
  final cooldown = manualCooldown == null
      ? ''
      : '\nVừa đồng bộ tay — bấm lại được sau ${manualCooldown.inSeconds} giây';
  return '$head$spent$off$note$cooldown';
}
