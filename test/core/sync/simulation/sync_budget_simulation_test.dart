import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_simulation_harness.dart';

/// A month of October on three devices sharing one space: the real engine
/// and controller on each, one in-memory Back4App, fake time.
///
/// Proves the budget acceptance end to end: what the reference workload
/// costs against [userMonthlyRequestBudget], that automatic sync keeps to a
/// device's share under a heavy one, that edits reach the server within the
/// push delay, and that every device ends up with the same data.
void main() {
  const budget = SyncBudget.configured;

  /// Every device and the server hold the same rows of every class, and no
  /// object a device deleted survives anywhere.
  void expectConverged(Simulation simulation) {
    for (final className in simClasses) {
      final server = serverSnapshot(simulation.server, className);
      expect(server.length, lessThan(500), reason: '$className dưới 500 dòng');
      expect(
        simulation.server.classOf(className).length,
        server.length,
        reason: 'mỗi localId chỉ có một object trên server',
      );
      for (final device in simulation.devices) {
        expect(
          deviceSnapshot(device, className),
          server,
          reason: '${device.name} / $className giống server',
        );
      }
    }

    var deleted = 0;
    for (final device in simulation.devices) {
      for (final collection in device.collections) {
        expect(collection.tombstones, isEmpty);
        expect(collection.rows.values.where((r) => r.dirty), isEmpty);
      }
      for (final MapEntry(key: className, value: ids)
          in device.deletedObjectIds.entries) {
        deleted += ids.length;
        expect(
          simulation.server.classOf(className).keys.toSet().intersection(ids),
          isEmpty,
          reason: 'xoá trên ${device.name} đã xoá trên server',
        );
        for (final other in simulation.devices) {
          final remoteIds = {
            for (final row in deviceSnapshot(other, className).values)
              row['objectId'],
          };
          expect(
            remoteIds.intersection(ids),
            isEmpty,
            reason: 'xoá trên ${device.name} cũng biến mất trên ${other.name}',
          );
        }
      }
    }
    expect(deleted, greaterThan(0), reason: 'workload có xoá');
  }

  /// The engine's meter, the server's log and the logged cycles agree.
  void expectMetered(Simulation simulation) {
    for (final device in simulation.devices) {
      expect(device.serverRequests, greaterThan(0));
      expect(
        device.meter,
        device.serverRequests,
        reason: 'meter của ${device.name} = request server ghi theo tag',
      );
      expect(
        device.autoRequests + device.manualRequests,
        device.meter,
        reason: 'mọi request đều thuộc một chu kỳ',
      );
    }
  }

  void printTable(Simulation simulation) {
    // ignore: avoid_print
    print(
      '\nMô phỏng ${simulation.workload.days} ngày, workload '
      '${simulation.workload.name} (${simulation.workload.editsPerDay} lượt '
      'sửa/ngày, ${simulation.rowEdits} dòng; '
      '${simulation.workload.focusPerDevicePerDay} focus/máy/ngày), ngân sách '
      '${budget.monthlyRequests}, phần mỗi máy ${budget.deviceShare}, '
      'cảnh báo ${budget.warnAt}:\n'
      '${requestTable(simulation, budget)}\n',
    );
  }

  group('workload thường', () {
    late Simulation simulation;

    setUpAll(() => simulation = runSimulation(Workload.normal));

    test('tổng request cả 3 máy ≤ 70% ngân sách, không máy nào tới '
        'ngưỡng cảnh báo', () {
      printTable(simulation);
      final total = simulation.metersAtEnd.values.reduce((a, b) => a + b);
      expect(total, lessThanOrEqualTo(budget.monthlyRequests * 70 ~/ 100));
      for (final device in simulation.devices) {
        expect(
          simulation.metersAtEnd[device.name],
          lessThan(budget.warnAt),
          reason: device.name,
        );
        // Including the final syncs by hand.
        expect(device.meter, lessThan(budget.warnAt), reason: device.name);
        expect(
          device.cycles.where((r) => r.levelBefore != SyncBudgetLevel.normal),
          isEmpty,
        );
      }
    });

    test('meter của mỗi máy bằng số request server ghi theo tag máy đó', () {
      expectMetered(simulation);
    });

    test('mỗi ngày mỗi máy: 1 lần mở app, bấm tay 1 lần; cả tháng chạy '
        'đủ', () {
      for (final device in simulation.devices) {
        final manual = device.cycles.where((r) => !r.auto).toList();
        // 30 days, then the final check by hand.
        expect(manual, hasLength(simulation.workload.days + 1));
        expect(manual.every((r) => r.full && r.state == SyncState.ok), isTrue);
        expect(
          device.cycles.where((r) => r.auto && r.state != SyncState.ok),
          isEmpty,
        );
      }
      expect(simulation.rowEdits, greaterThanOrEqualTo(20 * 30));
    });

    test('độ tươi: thay đổi local lên server trong vòng 30 giây sau lần '
        'sửa cuối', () {
      final pushDelay = budget.pushDelay(SyncBudgetLevel.normal);
      expect(pushDelay, const Duration(seconds: 30));
      for (final device in simulation.devices) {
        expect(device.hasUnpushed, isFalse);
        expect(device.pushLatencies, isNotEmpty);
        expect(
          device.pushLatencies.reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(pushDelay),
          reason: device.name,
        );
      }
    });

    test('sau một lần đồng bộ tay mỗi máy, 4 class trên 3 máy và server '
        'giống hệt nhau, kể cả bản ghi đã xoá', () {
      expectConverged(simulation);
    });
  });

  group('workload nặng', () {
    late Simulation simulation;

    // A device whose share ran out holds its edits until a manual sync, and
    // all three may; one round by hand, one device after the other, cannot
    // bring the last device's edits to the first. A second round does.
    setUpAll(
      () => simulation = runSimulation(Workload.heavy, handSyncRounds: 2),
    );

    test('request của các chu kỳ tự động ≤ phần ngân sách trên mỗi máy', () {
      printTable(simulation);
      for (final device in simulation.devices) {
        expect(
          device.autoRequests,
          lessThanOrEqualTo(budget.deviceShare),
          reason: device.name,
        );
        expect(
          device.cycles.where(
            (r) => r.auto && r.levelBefore == SyncBudgetLevel.exhausted,
          ),
          isEmpty,
          reason: 'không chu kỳ tự động nào bắt đầu khi đã hết phần',
        );
      }
    });

    test('đồng bộ tay được đếm vào meter và không bị chặn', () {
      expectMetered(simulation);
      for (final device in simulation.devices) {
        final manual = device.cycles.where((r) => !r.auto).toList();
        expect(manual, hasLength(simulation.workload.days + 2));
        for (final cycle in manual) {
          expect(cycle.state, SyncState.ok);
          expect(cycle.requests, greaterThan(0));
        }
      }
      final spent = [
        for (final device in simulation.devices)
          ...device.cycles.where(
            (r) => !r.auto && r.levelBefore == SyncBudgetLevel.exhausted,
          ),
      ];
      if (simulation.devices.any((d) => d.meter >= budget.stopAt)) {
        expect(spent, isNotEmpty, reason: 'có lần bấm tay sau khi hết phần');
      }
    });

    test('dữ liệu hội tụ sau khi mỗi máy đồng bộ tay', () {
      expectConverged(simulation);
    });
  });
}
