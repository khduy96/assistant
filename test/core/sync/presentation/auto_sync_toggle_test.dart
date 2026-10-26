import 'package:event_notice/core/sync/data/state_store_sync_preferences.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_state_store.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/auto_sync_toggle.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../fakes.dart';

/// A [MemorySyncStateStore] whose writes fail, as a full disk would.
class _FailingWriteStore extends MemorySyncStateStore {
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('đĩa đầy');
}

SyncController _controllerFor(FakeSyncEngine engine, SyncStateStore states) {
  final preferences = StateStoreSyncPreferences(states);
  return SyncController(
    runSync: RunSync(engine),
    hasPendingChanges: HasPendingChanges(engine),
    getMonthRequests: GetMonthRequests(engine),
    watchLocalChanges: WatchLocalChanges(engine),
    getSyncSettings: GetSyncSettings(engine),
    getAutoSyncChoice: GetAutoSyncChoice(preferences),
    setAutoSyncChoice: SetAutoSyncChoice(preferences),
    clock: FixedClock(DateTime(2026, 10, 24, 9)),
  );
}

/// A button that calls [toggleAutoSync], as the ⚙ menu item does.
Widget _harness(SyncController sync) => ChangeNotifierProvider.value(
  value: sync,
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => toggleAutoSync(context),
          child: const Text('bật/tắt'),
        ),
      ),
    ),
  ),
);

/// The snack bar now on screen, checked against calling the budget a
/// Back4App limit.
String _shownMessage(WidgetTester tester) {
  final text = tester.widget<Text>(
    find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
  );
  final message = text.data!;
  expect(message, isNot(contains('Back4App')));
  expect(message, isNot(contains('hạn mức')));
  return message;
}

Future<void> _toggle(WidgetTester tester) async {
  await tester.tap(find.text('bật/tắt'));
  // The snack bar before, if any, slides out first.
  await tester.pumpAndSettle();
}

void main() {
  const offMessage = 'Đã tắt sync tự động — vẫn dùng "Đồng bộ ngay" được.';
  const onMessage = 'Đã bật sync tự động.';

  testWidgets('tắt rồi bật lại: đổi trạng thái, lưu lựa chọn và báo đúng', (
    tester,
  ) async {
    final states = MemorySyncStateStore();
    final engine = FakeSyncEngine();
    final sync = _controllerFor(engine, states);
    addTearDown(sync.dispose);
    await sync.load();
    await tester.pumpWidget(_harness(sync));
    expect(sync.autoSyncEnabled, isTrue);

    await _toggle(tester);
    expect(sync.autoSyncEnabled, isFalse);
    expect(sync.settings.autoSync, isFalse);
    expect(states.values[StateStoreSyncPreferences.autoSyncKey], '0');
    expect(_shownMessage(tester), offMessage);

    await _toggle(tester);
    expect(sync.autoSyncEnabled, isTrue);
    expect(states.values[StateStoreSyncPreferences.autoSyncKey], '1');
    expect(_shownMessage(tester), onMessage);
    // Turning it on or off sends nothing itself.
    expect(engine.syncCalls, isEmpty);
  });

  testWidgets('bật khi đã hết ngân sách thì nói sẽ tự chạy lại từ tháng sau', (
    tester,
  ) async {
    final engine = FakeSyncEngine()
      ..settings = const SyncSettings(
        isConfigured: true,
        autoSync: false,
        space: 'nha',
      )
      ..monthRequests = SyncBudget.configured.stopAt;
    final sync = _controllerFor(engine, MemorySyncStateStore());
    await sync.start();
    await tester.pumpWidget(_harness(sync));
    expect(sync.autoSyncEnabled, isFalse);

    await _toggle(tester);
    expect(sync.autoSyncEnabled, isTrue);
    expect(sync.status.state, SyncState.paused);
    expect(engine.syncCalls, isEmpty);
    expect(
      _shownMessage(tester),
      'Đã bật sync tự động — đã hết ngân sách request tháng này của máy này, '
      'sẽ tự chạy lại từ tháng sau.',
    );

    await tester.pumpWidget(const SizedBox());
    // Stops the fallback timer that watches for the month to change.
    sync.dispose();
  });

  testWidgets('không lưu được thì giữ như cũ và báo lỗi tiếng Việt', (
    tester,
  ) async {
    final states = _FailingWriteStore();
    final sync = _controllerFor(FakeSyncEngine(), states);
    addTearDown(sync.dispose);
    await sync.load();
    await tester.pumpWidget(_harness(sync));

    await _toggle(tester);
    expect(sync.autoSyncEnabled, isTrue);
    expect(sync.settings.autoSync, isTrue);
    expect(states.values, isEmpty);
    expect(
      _shownMessage(tester),
      'Không lưu được lựa chọn sync tự động, vẫn giữ như cũ.',
    );
  });
}
