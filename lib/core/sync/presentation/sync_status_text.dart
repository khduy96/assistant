import '../../presentation/format.dart';
import '../domain/entities/sync_budget.dart';
import '../domain/entities/sync_settings.dart';
import '../domain/entities/sync_status.dart';

/// Tooltip of the sync button: how the last cycle went, what this device has
/// spent of its share of [budget] this month, and what [level] means for
/// automatic sync. [now] is the time "lần cuối" is counted back from.
///
/// The budget is the user's own, so the text never calls it a Back4App limit.
String syncTooltip({
  required SyncStatus status,
  required SyncSettings settings,
  required SyncBudget budget,
  required SyncBudgetLevel level,
  required DateTime now,
}) {
  if (status.state == SyncState.notConfigured) {
    return 'Chưa cấu hình — build với --dart-define-from-file=.env để bật đồng bộ';
  }
  final spent = status.monthRequests == null
      ? ''
      : '\n${status.monthRequests} / ${budget.deviceShare}'
            ' request tháng này (máy này)';
  final note =
      status.state == SyncState.paused || level == SyncBudgetLevel.exhausted
      ? '\nĐã hết ngân sách request tháng này của máy này — sync tự động tạm'
            ' dừng tới tháng sau, vẫn bấm để đồng bộ tay được'
      : level == SyncBudgetLevel.warning
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
  return '$head$spent$note';
}
