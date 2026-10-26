import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/presentation/sync_status_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// Share 3000, warning from 2100, stop at 3000; spelled out so the strings
/// below do not move with the configured budget.
const _budget = SyncBudget(monthlyRequests: 9000, devices: 3);

const _settings = SyncSettings(
  isConfigured: true,
  autoSync: true,
  space: 'nha',
);

final _now = DateTime(2026, 10, 23, 9);

const _warning =
    '\nSắp hết ngân sách request tháng này nên sync tự động thưa hơn';
const _exhausted =
    '\nĐã hết ngân sách request tháng này của máy này — sync tự động tạm dừng'
    ' tới tháng sau, vẫn bấm để đồng bộ tay được';

String _text(
  SyncStatus status, {
  SyncBudget budget = _budget,
  SyncBudgetLevel? level,
}) => syncTooltip(
  status: status,
  settings: _settings,
  budget: budget,
  level: level ?? budget.levelFor(status.monthRequests ?? 0),
  now: _now,
);

void main() {
  group('các trạng thái giữ câu chữ, dòng đếm thành x / y', () {
    test('chưa cấu hình', () {
      expect(
        _text(const SyncStatus(state: SyncState.notConfigured)),
        'Chưa cấu hình — build với --dart-define-from-file=.env để bật đồng bộ',
      );
    });

    test('lỗi', () {
      expect(
        _text(
          const SyncStatus(
            state: SyncState.error,
            message: 'Không có kết nối mạng',
            monthRequests: 12,
          ),
        ),
        'Đồng bộ lỗi: Không có kết nối mạng\n'
        '12 / 3000 request tháng này (máy này)',
      );
    });

    test('ok chưa có lần cuối', () {
      expect(
        _text(const SyncStatus(state: SyncState.ok, monthRequests: 12)),
        'Đồng bộ ngay\n12 / 3000 request tháng này (máy này)',
      );
    });

    test('ok có lần cuối, tính lùi từ now', () {
      expect(
        _text(
          SyncStatus(
            state: SyncState.ok,
            lastSyncAt: _now.subtract(const Duration(minutes: 5)),
            pushed: 2,
            pulled: 3,
            monthRequests: 12,
          ),
        ),
        'Đồng bộ lần cuối 5 phút trước · đẩy 2, nhận 3\n'
        '12 / 3000 request tháng này (máy này)',
      );
    });

    test('idle và running', () {
      for (final state in [SyncState.idle, SyncState.running]) {
        expect(
          _text(SyncStatus(state: state, monthRequests: 12)),
          'Đồng bộ ngay (nha)\n12 / 3000 request tháng này (máy này)',
        );
      }
    });

    test('chưa biết số request thì không có dòng đếm', () {
      expect(
        _text(const SyncStatus(state: SyncState.idle)),
        'Đồng bộ ngay (nha)',
      );
    });

    test('phần của máy theo ngân sách truyền vào', () {
      expect(
        _text(
          const SyncStatus(state: SyncState.idle, monthRequests: 12),
          budget: const SyncBudget(monthlyRequests: 5000, devices: 2),
        ),
        'Đồng bộ ngay (nha)\n12 / 2500 request tháng này (máy này)',
      );
    });
  });

  group('mức ngân sách', () {
    test('normal không thêm dòng nào', () {
      expect(
        _text(const SyncStatus(state: SyncState.idle, monthRequests: 2099)),
        'Đồng bộ ngay (nha)\n2099 / 3000 request tháng này (máy này)',
      );
    });

    test('warning báo sắp hết và sync tự động thưa hơn', () {
      expect(
        _text(const SyncStatus(state: SyncState.idle, monthRequests: 2100)),
        'Đồng bộ ngay (nha)\n2100 / 3000 request tháng này (máy này)$_warning',
      );
      expect(
        _text(const SyncStatus(state: SyncState.ok, monthRequests: 2500)),
        'Đồng bộ ngay\n2500 / 3000 request tháng này (máy này)$_warning',
      );
    });

    test('paused nói đã hết, tạm dừng tới tháng sau, vẫn bấm tay được', () {
      expect(
        _text(
          const SyncStatus(
            state: SyncState.paused,
            message: 'Đã dùng hết ngân sách request tháng này của máy này',
            monthRequests: 3000,
          ),
        ),
        'Đồng bộ ngay (nha)\n3000 / 3000 request tháng này (máy này)'
        '$_exhausted',
      );
    });

    test('exhausted sau một lần bấm tay vẫn báo đã hết', () {
      expect(
        _text(
          SyncStatus(
            state: SyncState.ok,
            lastSyncAt: _now,
            pushed: 1,
            monthRequests: 3012,
          ),
        ),
        'Đồng bộ lần cuối vừa xong · đẩy 1, nhận 0\n'
        '3012 / 3000 request tháng này (máy này)$_exhausted',
      );
    });
  });

  test('không chuỗi nào gọi ngân sách là hạn mức của Back4App', () {
    final texts = [
      for (final state in SyncState.values)
        for (final used in [null, 0, 2100, 3000, 4000])
          _text(SyncStatus(state: state, message: 'x', monthRequests: used)),
    ];
    for (final text in texts) {
      expect(text, isNot(contains('Back4App')));
      expect(text, isNot(contains('hạn mức')));
    }
  });
}
