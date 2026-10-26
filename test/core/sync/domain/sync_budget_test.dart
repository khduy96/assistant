import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every interval that depends on the budget, by name, at [level].
Map<String, Duration> _intervals(SyncBudget budget, SyncBudgetLevel level) => {
  'appActiveRefresh': budget.appActiveRefresh(level),
  'fullPullEvery': budget.fullPullEvery(level),
  'pushDelay': budget.pushDelay(level),
  'fallbackInterval': budget.fallbackInterval(level),
};

void main() {
  // The default case, spelled out so the test stays green when the
  // configured budget is edited.
  const byDefault = SyncBudget(monthlyRequests: 10000, devices: 3);

  /// Budgets from smallest to largest.
  const budgets = [
    SyncBudget(monthlyRequests: 5000, devices: 3),
    SyncBudget(monthlyRequests: 10000, devices: 3),
    SyncBudget(monthlyRequests: 20000, devices: 3),
  ];

  test('configured lấy từ hai hằng số do người dùng đặt', () {
    expect(SyncBudget.configured.monthlyRequests, userMonthlyRequestBudget);
    expect(SyncBudget.configured.devices, expectedSyncDevices);
  });

  group('ở ngân sách mặc định (10.000, 3 máy)', () {
    test('phần của máy, ngưỡng cảnh báo và ngưỡng dừng', () {
      expect(byDefault.deviceShare, 3333);
      expect(byDefault.warnAt, 2333);
      expect(byDefault.stopAt, 3333);
    });

    test('R không quá 15 phút, pull đầy đủ không quá 24 giờ', () {
      final normal = SyncBudgetLevel.normal;
      expect(
        byDefault.appActiveRefresh(normal),
        lessThanOrEqualTo(const Duration(minutes: 15)),
      );
      expect(
        byDefault.fullPullEvery(normal),
        lessThanOrEqualTo(const Duration(hours: 24)),
      );
      expect(byDefault.pushDelay(normal), const Duration(seconds: 30));
      expect(byDefault.fallbackInterval(normal), const Duration(hours: 2));
    });
  });

  group('pull đầy đủ ở mức warning, trần 24 giờ', () {
    test('trần là 24 giờ', () {
      expect(SyncBudget.warningFullPullCap, const Duration(hours: 24));
    });

    test('ngân sách mặc định: normal 21 giờ, warning 24 giờ thay vì 84', () {
      expect(
        byDefault.fullPullEvery(SyncBudgetLevel.normal),
        const Duration(hours: 21),
      );
      expect(
        byDefault.fullPullEvery(SyncBudgetLevel.warning),
        const Duration(hours: 24),
      );
    });

    test('ngân sách mặc định: mức exhausted giữ normal × 4 = 84 giờ', () {
      expect(
        byDefault.fullPullEvery(SyncBudgetLevel.exhausted),
        const Duration(hours: 84),
      );
    });

    test('normal × 4 dưới 24 giờ thì giữ normal × 4', () {
      const big = SyncBudget(monthlyRequests: 60000, devices: 3);
      expect(
        big.fullPullEvery(SyncBudgetLevel.normal),
        const Duration(hours: 4),
      );
      expect(
        big.fullPullEvery(SyncBudgetLevel.warning),
        const Duration(hours: 16),
      );
    });

    test('normal đã quá 24 giờ thì warning bằng normal, không nhanh hơn', () {
      const small = SyncBudget(monthlyRequests: 5000, devices: 3);
      expect(
        small.fullPullEvery(SyncBudgetLevel.normal),
        const Duration(hours: 41),
      );
      expect(
        small.fullPullEvery(SyncBudgetLevel.warning),
        const Duration(hours: 41),
      );
    });
  });

  test('khớp công thức trong doc comment', () {
    for (final budget in budgets) {
      final daily = budget.deviceShare / 31;
      final normal = SyncBudgetLevel.normal;
      expect(
        budget.appActiveRefresh(normal),
        Duration(minutes: (720 / (0.5 * daily)).ceil()),
        reason: '${budget.monthlyRequests}',
      );
      expect(
        budget.fullPullEvery(normal),
        Duration(hours: (24 * 9 / (0.1 * daily)).ceil()),
        reason: '${budget.monthlyRequests}',
      );
    }
  });

  group('đơn điệu theo ngân sách', () {
    for (var i = 0; i < budgets.length; i++) {
      for (var j = i + 1; j < budgets.length; j++) {
        final smaller = budgets[i];
        final larger = budgets[j];
        final name = '${smaller.monthlyRequests} và ${larger.monthlyRequests}';

        test('$name: ngưỡng của ngân sách lớn không thấp hơn', () {
          expect(larger.deviceShare, greaterThanOrEqualTo(smaller.deviceShare));
          expect(larger.warnAt, greaterThanOrEqualTo(smaller.warnAt));
          expect(larger.stopAt, greaterThanOrEqualTo(smaller.stopAt));
        });

        for (final level in SyncBudgetLevel.values) {
          test('$name, mức ${level.name}: ngân sách lớn không có khoảng '
              'nào dài hơn, ngân sách nhỏ không có khoảng nào ngắn hơn', () {
            final big = _intervals(larger, level);
            final small = _intervals(smaller, level);
            for (final key in big.keys) {
              expect(big[key], lessThanOrEqualTo(small[key]!), reason: key);
              expect(small[key], greaterThanOrEqualTo(big[key]!), reason: key);
            }
          });
        }
      }
    }
  });

  group('theo mức', () {
    for (final budget in budgets) {
      final name = '${budget.monthlyRequests}';

      test('$name: mức warning có mọi khoảng, trừ fullPullEvery, dài gấp 4 '
          'mức normal', () {
        final normal = _intervals(budget, SyncBudgetLevel.normal);
        final warning = _intervals(budget, SyncBudgetLevel.warning);
        for (final key in normal.keys) {
          if (key == 'fullPullEvery') continue;
          expect(warning[key], greaterThan(normal[key]!), reason: key);
          expect(warning[key], normal[key]! * 4, reason: key);
        }
      });

      test('$name: fullPullEvery(warning) không ngắn hơn normal, không dài '
          'hơn normal × 4', () {
        final normal = budget.fullPullEvery(SyncBudgetLevel.normal);
        final warning = budget.fullPullEvery(SyncBudgetLevel.warning);
        expect(warning, greaterThanOrEqualTo(normal));
        expect(warning, lessThanOrEqualTo(normal * 4));
      });

      test('$name: mức exhausted giữ khoảng dự phòng của normal', () {
        expect(
          budget.fallbackInterval(SyncBudgetLevel.exhausted),
          budget.fallbackInterval(SyncBudgetLevel.normal),
        );
      });

      test('$name: biên của levelFor', () {
        expect(budget.levelFor(0), SyncBudgetLevel.normal);
        expect(budget.levelFor(budget.warnAt - 1), SyncBudgetLevel.normal);
        expect(budget.levelFor(budget.warnAt), SyncBudgetLevel.warning);
        expect(budget.levelFor(budget.stopAt - 1), SyncBudgetLevel.warning);
        expect(budget.levelFor(budget.stopAt), SyncBudgetLevel.exhausted);
        expect(budget.levelFor(budget.stopAt + 100), SyncBudgetLevel.exhausted);
      });
    }
  });
}
