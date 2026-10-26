import 'package:event_notice/core/sync/data/state_store_sync_preferences.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/presentation/clip_actions.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_controller.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_tab_state.dart';
import 'package:event_notice/features/clipboard/presentation/pages/clip_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../core/sync/fakes.dart';
import '../domain/fakes.dart';
import 'fixture.dart';

/// [text] shown in a snack bar, not in a tab label of the same wording.
Finder toast(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

/// Clipboard là một tab, bên trong chia bốn mục. Các bài test này dựng tab
/// trên controller thật, với use case thật chạy trên repository và clipboard
/// giả, rồi canh những gì người dùng thấy và bấm được.
void main() {
  late FakeClock clock;
  late FakeClipboardSource source;
  late InMemoryClipboardRepository repo;
  late ClipboardController controller;
  late ClipboardTabState tabState;
  var disposed = true;

  setUp(() {
    clock = FakeClock(at(60));
    source = FakeClipboardSource();
    tabState = ClipboardTabState();
  });

  tearDown(() async {
    if (!disposed) controller.dispose();
    disposed = true;
    tabState.dispose();
    source.dispose();
    await repo.dispose();
  });

  /// The tab as the home page shows it: the clipboard buttons in the app bar
  /// and the floating button of the open section. [sync] backs the sync
  /// button and a menu holding the home page's "Đồng bộ ngay" entry; without
  /// it the app bar is left out.
  Widget harness({SyncController? sync}) {
    final page = Scaffold(
      appBar: sync == null
          ? null
          : AppBar(
              actions: [
                Builder(
                  builder: (context) => Row(
                    children: clipboardActions(
                      context,
                      context.watch<ClipboardTabState>().section,
                    ),
                  ),
                ),
                Builder(
                  builder: (context) => PopupMenuButton<String>(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Tuỳ chọn',
                    onSelected: (v) {
                      if (v == 'sync') runSync(context);
                    },
                    itemBuilder: (_) => [syncNowMenuItem(context, 'sync')],
                  ),
                ),
              ],
            ),
      body: const ClipboardTab(),
      floatingActionButton: Builder(
        builder: (context) =>
            clipboardFab(context, context.watch<ClipboardTabState>().section),
      ),
    );
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ClipboardController>.value(value: controller),
        ChangeNotifierProvider<ClipboardTabState>.value(value: tabState),
        if (sync != null) ...[
          ChangeNotifierProvider<SyncController>.value(value: sync),
          Provider<SyncSettings>.value(value: sync.settings),
        ],
      ],
      child: MaterialApp(home: page),
    );
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    List<ClipItem> clips = const [],
    List<ClipGroup> groups = const [],
    SyncController? sync,
  }) async {
    repo = InMemoryClipboardRepository(clips: clips, groups: groups);
    controller = controllerFor(repo, source, clock: clock);
    disposed = false;
    await controller.init();
    await tester.pumpWidget(harness(sync: sync));
    await tester.pumpAndSettle();
  }

  /// Takes the tab down and stops the controller's hourly sweep, which would
  /// otherwise outlive the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    disposed = true;
  }

  testWidgets('hiện đủ bốn mục con và ô tìm kiếm dùng chung', (tester) async {
    await pumpTab(tester);

    for (final section in ClipboardSection.values) {
      expect(find.text(section.label), findsOneWidget);
    }
    expect(find.text('Tìm trong clipboard…'), findsOneWidget);
    expect(tabState.section, ClipboardSection.temp);
    expect(find.text('Chưa có gì trong bộ nhớ tạm'), findsOneWidget);
    expect(find.text('Thêm clip'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('đổi mục con thì trạng thái ngoài tab đổi theo và bỏ chọn', (
    tester,
  ) async {
    await pumpTab(tester, clips: [clip('a')]);
    controller.toggleSelection('a');
    await tester.pump();
    expect(find.text('Đã chọn 1'), findsOneWidget);

    await tester.tap(find.text('Nhóm'));
    await tester.pumpAndSettle();

    expect(tabState.section, ClipboardSection.groups);
    expect(controller.isSelecting, isFalse);
    expect(find.text('Chưa có nhóm nào'), findsOneWidget);
    expect(find.byTooltip('Lọc theo loại'), findsNothing);
    expect(find.text('Nhóm mới'), findsOneWidget);

    await tester.tap(find.text('Ghim'));
    await tester.pumpAndSettle();

    expect(tabState.section, ClipboardSection.pinned);
    expect(find.text('Chưa ghim clip nào'), findsOneWidget);
    expect(find.byTooltip('Lọc theo loại'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('gõ tìm kiếm ở mục này thì mục khác vẫn giữ nguyên chữ', (
    tester,
  ) async {
    await pumpTab(
      tester,
      clips: [
        clip('a', content: 'mật khẩu wifi'),
        clip('b', content: 'số tài khoản'),
      ],
    );

    await tester.enterText(find.byType(TextField), 'WIFI');
    await tester.pumpAndSettle();
    expect(controller.query, 'WIFI');
    expect(find.text('mật khẩu wifi'), findsOneWidget);
    expect(find.text('số tài khoản'), findsNothing);

    await tester.tap(find.text('Đã lưu'));
    await tester.pumpAndSettle();

    expect(find.text('WIFI'), findsOneWidget);
    expect(controller.query, 'WIFI');

    // Nút xoá trong ô tìm kiếm trả lại cả danh sách.
    await tester.tap(find.text('Tạm (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(controller.query, '');
    expect(find.text('số tài khoản'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('thẻ clip hiện tuổi, hạn xoá, nhóm và số lần dùng', (
    tester,
  ) async {
    await pumpTab(
      tester,
      clips: [
        clip('tam', content: 'clip tạm', createdMin: 0),
        clip(
          'luu',
          content: 'clip đã lưu',
          createdMin: -2 * 24 * 60,
          saved: true,
          groupId: 'g',
          copyCount: 2,
        ),
      ],
      groups: [clipGroup('g', name: 'Mã OTP')],
    );

    expect(find.text('Tạm (1)'), findsOneWidget);
    expect(find.text('Đã lưu (1)'), findsOneWidget);
    expect(find.text('Nhóm (1)'), findsOneWidget);
    expect(find.text('1 giờ trước'), findsOneWidget);
    expect(find.text('còn 23 giờ'), findsOneWidget);
    expect(find.text('8 ký tự'), findsOneWidget);

    await tester.tap(find.text('Đã lưu (1)'));
    await tester.pumpAndSettle();

    expect(find.text('2 ngày trước'), findsOneWidget);
    expect(find.text('Mã OTP'), findsOneWidget);
    expect(find.text('đã dùng 2 lần'), findsOneWidget);
    expect(find.textContaining('còn '), findsNothing);
    await finish(tester);
  });

  testWidgets('chạm vào thẻ thì copy lại vào clipboard', (tester) async {
    await pumpTab(tester, clips: [clip('a', content: 'dán tôi')]);

    await tester.tap(find.text('dán tôi'));
    await tester.pump();

    expect(source.written, ['dán tôi']);
    expect(find.text('Đã copy vào clipboard'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('đã dùng 1 lần'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('ghim clip tạm thì clip được lưu', (tester) async {
    await pumpTab(tester, clips: [clip('a')]);

    await tester.tap(find.byTooltip('Ghim'));
    await tester.pump();

    expect(find.text('Đã ghim và lưu vào danh sách lưu'), findsOneWidget);
    expect(find.text('Ghim (1)'), findsOneWidget);
    expect(find.text('Đã lưu (1)'), findsOneWidget);
    expect(find.text('Chưa có gì trong bộ nhớ tạm'), findsOneWidget);
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('giữ để chọn, rồi copy hết các mục đã chọn', (tester) async {
    await pumpTab(
      tester,
      clips: [
        clip('a', content: 'một', createdMin: 0),
        clip('b', content: 'hai', createdMin: 10),
      ],
    );

    await tester.longPress(find.text('một'));
    await tester.pump();
    expect(find.text('Đã chọn 1'), findsOneWidget);
    expect(find.text('Tìm trong clipboard…'), findsNothing);

    // Đang chọn thì chạm là chọn thêm, không copy.
    await tester.tap(find.text('hai'));
    await tester.pump();
    expect(find.text('Đã chọn 2'), findsOneWidget);
    expect(source.written, isEmpty);

    await tester.tap(find.byTooltip('Copy tất cả mục đã chọn'));
    await tester.pump();

    expect(source.written, ['một\nhai']);
    expect(find.text('Đã copy 2 clip vào clipboard'), findsOneWidget);
    expect(find.text('Tìm trong clipboard…'), findsOneWidget);
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('xoá hàng loạt có hoàn tác', (tester) async {
    await pumpTab(tester, clips: [clip('a', content: 'một')]);

    await tester.longPress(find.text('một'));
    await tester.pump();
    await tester.tap(find.byTooltip('Thao tác hàng loạt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();

    expect(find.text('Đã xoá 1 clip'), findsOneWidget);
    expect(controller.tempCount, 0);

    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(find.text('một'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('lọc theo loại qua bảng chọn', (tester) async {
    await pumpTab(
      tester,
      clips: [
        clip('a', content: 'https://dart.dev', type: ClipType.link),
        clip('b', content: 'văn bản thường'),
      ],
    );

    await tester.tap(find.byTooltip('Lọc theo loại'));
    await tester.pumpAndSettle();
    expect(find.text('Tất cả loại'), findsOneWidget);
    await tester.tap(find.text('Liên kết'));
    await tester.pumpAndSettle();

    expect(controller.typeFilter, ClipType.link);
    expect(find.byTooltip('Đang lọc: Liên kết'), findsOneWidget);
    expect(find.text('https://dart.dev'), findsOneWidget);
    expect(find.text('văn bản thường'), findsNothing);
    await finish(tester);
  });

  testWidgets('thêm clip bằng tay từ nút nổi', (tester) async {
    await pumpTab(tester);

    await tester.tap(find.text('Thêm clip'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'gõ tay',
    );
    await tester.tap(find.text('Lưu'));
    await tester.pump();

    expect(toast('Đã lưu'), findsOneWidget);
    expect(controller.savedCount, 1);
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu (1)'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('mở một nhóm, xoá nhóm thì clip của nhóm vẫn còn', (
    tester,
  ) async {
    await pumpTab(
      tester,
      clips: [clip('a', content: 'trong nhóm', saved: true, groupId: 'g')],
      groups: [clipGroup('g', name: 'Mã OTP')],
    );

    await tester.tap(find.text('Nhóm (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1 clip'), findsOneWidget);

    await tester.tap(find.text('Mã OTP'));
    await tester.pumpAndSettle();
    expect(find.text('trong nhóm'), findsOneWidget);

    await tester.tap(find.byTooltip('Xoá nhóm'));
    await tester.pumpAndSettle();
    expect(find.text('Xoá nhóm "Mã OTP"?'), findsOneWidget);
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();

    // Trang nhóm đã đóng, quay về mục Nhóm.
    expect(find.byTooltip('Xoá nhóm'), findsNothing);
    expect(find.text('Chưa có nhóm nào'), findsOneWidget);
    expect(controller.ungroupedSaved.single.id, 'a');
    await finish(tester);
  });

  testWidgets(
    'trên điện thoại, vuốt phải để lưu, vuốt trái để xoá và hoàn tác',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpTab(tester, clips: [clip('a', content: 'vuốt tôi')]);

      await tester.drag(find.text('vuốt tôi'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(toast('Đã lưu'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(controller.savedCount, 1);

      await tester.tap(find.text('Đã lưu (1)'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('vuốt tôi'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('Đã xoá clip'), findsOneWidget);
      expect(controller.savedCount, 0);

      await tester.tap(find.text('Hoàn tác'));
      await tester.pumpAndSettle();
      expect(controller.savedCount, 1);
      await finish(tester);
    },
  );

  testWidgets('nút đồng bộ đọc SyncController và báo kết quả', (tester) async {
    final engine = FakeSyncEngine()
      ..settings = const SyncSettings(
        isConfigured: true,
        autoSync: false,
        space: 'nha',
      )
      ..monthRequests = 12;
    final preferences = StateStoreSyncPreferences(MemorySyncStateStore());
    final sync = SyncController(
      runSync: RunSync(engine),
      hasPendingChanges: HasPendingChanges(engine),
      getMonthRequests: GetMonthRequests(engine),
      watchLocalChanges: WatchLocalChanges(engine),
      getSyncSettings: GetSyncSettings(engine),
      getAutoSyncChoice: GetAutoSyncChoice(preferences),
      setAutoSyncChoice: SetAutoSyncChoice(preferences),
      clock: clock,
    );
    addTearDown(sync.dispose);
    await sync.start();
    await pumpTab(tester, clips: [clip('a')], sync: sync);

    // A build with automatic sync off says so, in the tooltip and the icon.
    expect(
      find.byTooltip(
        'Đồng bộ ngay (nha)\n12 / 3333 request tháng này (máy này)\n'
        'Sync tự động đang tắt — vẫn bấm để đồng bộ tay được',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Đang ghi clipboard — chạm để dừng'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cloud_outlined));
    await tester.pump();
    expect(engine.fullRequests, [true]);
    expect(find.text('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
    await tester.pumpAndSettle();

    // Nút ghi clipboard bật/tắt nguồn.
    await tester.tap(find.byTooltip('Đang ghi clipboard — chạm để dừng'));
    await tester.pump();
    expect(source.isEnabled, isFalse);
    expect(find.byTooltip('Đã dừng — chạm để ghi'), findsOneWidget);

    // Xoá hết mục tạm hỏi lại trước khi xoá.
    await tester.tap(find.byTooltip('Xoá hết mục tạm'));
    await tester.pumpAndSettle();
    expect(find.text('Xoá hết mục tạm?'), findsOneWidget);
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();
    expect(controller.tempCount, 0);
    final clear = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined),
    );
    expect(clear.onPressed, isNull);
    await finish(tester);
  });

  group('nút đồng bộ theo ngân sách request tháng này', () {
    const budget = SyncBudget.configured;
    final share = budget.deviceShare;
    const lockedLine = '\nVừa đồng bộ tay — bấm lại được sau 30 giây';

    SyncController syncOn(FakeSyncEngine engine) {
      final preferences = StateStoreSyncPreferences(MemorySyncStateStore());
      return SyncController(
        runSync: RunSync(engine),
        hasPendingChanges: HasPendingChanges(engine),
        getMonthRequests: GetMonthRequests(engine),
        watchLocalChanges: WatchLocalChanges(engine),
        getSyncSettings: GetSyncSettings(engine),
        getAutoSyncChoice: GetAutoSyncChoice(preferences),
        setAutoSyncChoice: SetAutoSyncChoice(preferences),
        clock: clock,
      );
    }

    IconButton syncButton(WidgetTester tester, IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    testWidgets('từ mức cảnh báo thì báo sắp hết, icon như thường', (
      tester,
    ) async {
      // Automatic sync on, or there is nothing to thin out; the first cycle
      // reports the same tally.
      final engine = FakeSyncEngine()
        ..settings = const SyncSettings(
          isConfigured: true,
          autoSync: true,
          space: 'nha',
        )
        ..monthRequests = budget.warnAt
        ..status = SyncStatus(
          state: SyncState.ok,
          monthRequests: budget.warnAt,
        );
      final sync = syncOn(engine);
      await sync.start();
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      expect(
        find.byTooltip(
          'Đồng bộ ngay\n${budget.warnAt} / $share request tháng này '
          '(máy này)\nSắp hết ngân sách request tháng này nên sync tự động '
          'thưa hơn',
        ),
        findsOneWidget,
      );
      expect(
        syncButton(tester, Icons.cloud_sync_outlined).onPressed,
        isNotNull,
      );
      await finish(tester);
      // Stops the fallback timer armed after the first cycle.
      sync.dispose();
    });

    testWidgets('hết ngân sách thì sync tự động dừng, icon riêng không đỏ, '
        'vẫn bấm để đồng bộ tay được', (tester) async {
      final engine = FakeSyncEngine()
        ..settings = const SyncSettings(
          isConfigured: true,
          autoSync: true,
          space: 'nha',
        )
        ..monthRequests = budget.stopAt
        // The manual cycle is counted too.
        ..status = SyncStatus(
          state: SyncState.ok,
          monthRequests: budget.stopAt + 1,
        );
      final sync = syncOn(engine);
      await sync.start();
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      const spentNote =
          '\nĐã hết ngân sách request tháng này của máy này — sync tự động '
          'tạm dừng tới tháng sau, vẫn bấm để đồng bộ tay được';
      expect(engine.syncCalls, isEmpty);
      expect(sync.status.state, SyncState.paused);
      expect(
        find.byTooltip(
          'Đồng bộ ngay (nha)\n${budget.stopAt} / $share request tháng này '
          '(máy này)$spentNote',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
      final icon = tester.widget<Icon>(
        find.byIcon(Icons.sync_disabled_rounded),
      );
      expect(icon.color, isNull);
      expect(
        syncButton(tester, Icons.sync_disabled_rounded).onPressed,
        isNotNull,
      );

      await tester.tap(find.byIcon(Icons.sync_disabled_rounded));
      await tester.pump();
      expect(engine.syncCalls, [(full: true, auto: false, checkRemote: true)]);
      expect(find.text('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
      await tester.pumpAndSettle();
      // Just pressed, so the button is locked and says so on a last line.
      expect(
        find.byTooltip(
          'Đồng bộ ngay\n${budget.stopAt + 1} / $share request tháng này '
          '(máy này)$spentNote$lockedLine',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.sync_disabled_rounded), findsOneWidget);

      await finish(tester);
      // Stops the fallback timer that watches for the month to change.
      sync.dispose();
    });

    group('sync tự động đang tắt', () {
      const offLine = '\nSync tự động đang tắt — vẫn bấm để đồng bộ tay được';

      testWidgets('kể cả khi hết ngân sách: icon đám mây không màu, tooltip '
          'có cả hai dòng, bấm thì đồng bộ tay đúng một lần', (tester) async {
        final engine = FakeSyncEngine()
          ..settings = const SyncSettings(
            isConfigured: true,
            autoSync: false,
            space: 'nha',
          )
          ..monthRequests = budget.stopAt
          // The manual cycle is counted too.
          ..status = SyncStatus(
            state: SyncState.ok,
            monthRequests: budget.stopAt + 1,
          );
        final sync = syncOn(engine);
        addTearDown(sync.dispose);
        await sync.start();
        await pumpTab(tester, clips: [clip('a')], sync: sync);

        const spentNote =
            '\nĐã hết ngân sách request tháng này của máy này — sync tự động '
            'tạm dừng tới tháng sau, vẫn bấm để đồng bộ tay được';
        expect(sync.autoSyncEnabled, isFalse);
        expect(sync.budgetLevel, SyncBudgetLevel.exhausted);
        expect(engine.syncCalls, isEmpty);
        expect(
          find.byTooltip(
            'Đồng bộ ngay (nha)\n${budget.stopAt} / $share request tháng này '
            '(máy này)$offLine$spentNote',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.sync_disabled_rounded), findsNothing);
        expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
        final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_outlined));
        expect(icon.color, isNull);
        expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNotNull);

        await tester.tap(find.byIcon(Icons.cloud_outlined));
        await tester.pump();
        expect(engine.syncCalls, [
          (full: true, auto: false, checkRemote: true),
        ]);
        expect(find.text('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
        await tester.pumpAndSettle();
        // Just pressed, so the button is locked and says so on a last line.
        expect(
          find.byTooltip(
            'Đồng bộ ngay\n${budget.stopAt + 1} / $share request tháng này '
            '(máy này)$offLine$spentNote$lockedLine',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
        expect(engine.syncCalls, hasLength(1));

        await finish(tester);
      });

      testWidgets('lỗi thì vẫn là đám mây gạch màu lỗi', (tester) async {
        final engine = FakeSyncEngine()
          ..settings = const SyncSettings(
            isConfigured: true,
            autoSync: false,
            space: 'nha',
          )
          ..monthRequests = 12
          ..status = const SyncStatus(
            state: SyncState.error,
            message: 'mất mạng',
          );
        final sync = syncOn(engine);
        addTearDown(sync.dispose);
        await sync.start();
        await pumpTab(tester, clips: [clip('a')], sync: sync);

        await tester.tap(find.byIcon(Icons.cloud_outlined));
        await tester.pumpAndSettle();

        // A failed cycle still locks the button for the whole wait, with the
        // error said in a snack bar.
        expect(toast('Đồng bộ lỗi: mất mạng'), findsOneWidget);
        expect(syncButton(tester, Icons.cloud_off_rounded).onPressed, isNull);
        clock.current = clock.current.add(SyncController.manualSyncCooldown);
        await tester.pump(SyncController.manualSyncCooldown);

        expect(sync.status.state, SyncState.error);
        expect(
          find.byTooltip(
            'Đồng bộ lỗi: mất mạng\n12 / $share request tháng này '
            '(máy này)$offLine',
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.cloud_outlined), findsNothing);
        final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_off_rounded));
        final scheme = Theme.of(
          tester.element(find.byType(ClipboardTab)),
        ).colorScheme;
        expect(icon.color, scheme.error);
        expect(
          syncButton(tester, Icons.cloud_off_rounded).onPressed,
          isNotNull,
        );

        await finish(tester);
      });
    });
  });

  group('"Đồng bộ ngay" khoá 30 giây sau mỗi lần bấm', () {
    const budget = SyncBudget.configured;
    final share = budget.deviceShare;
    const offLine = '\nSync tự động đang tắt — vẫn bấm để đồng bộ tay được';
    const lockedLine = '\nVừa đồng bộ tay — bấm lại được sau 30 giây';
    const menuText = 'Đồng bộ ngay (clip, việc, ghi chú)';
    const manual = (full: true, auto: false, checkRemote: true);
    // What a manual cycle on this engine leaves in the tooltip.
    final afterCycle =
        'Đồng bộ ngay\n13 / $share request tháng này (máy này)'
        '$offLine';

    /// Automatic sync off, so nothing but a press runs a cycle and the
    /// controller arms no timer of its own.
    FakeSyncEngine engineOff({bool configured = true}) => FakeSyncEngine()
      ..settings = SyncSettings(
        isConfigured: configured,
        autoSync: false,
        space: 'nha',
      )
      ..monthRequests = 12
      ..status = const SyncStatus(state: SyncState.ok, monthRequests: 13);

    Future<SyncController> startSync(FakeSyncEngine engine) async {
      final preferences = StateStoreSyncPreferences(MemorySyncStateStore());
      final sync = SyncController(
        runSync: RunSync(engine),
        hasPendingChanges: HasPendingChanges(engine),
        getMonthRequests: GetMonthRequests(engine),
        watchLocalChanges: WatchLocalChanges(engine),
        getSyncSettings: GetSyncSettings(engine),
        getAutoSyncChoice: GetAutoSyncChoice(preferences),
        setAutoSyncChoice: SetAutoSyncChoice(preferences),
        clock: clock,
      );
      addTearDown(sync.dispose);
      await sync.start();
      return sync;
    }

    IconButton syncButton(WidgetTester tester, IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    /// Whether the menu's "Đồng bộ ngay" entry can be picked, as read when
    /// the menu opens; leaves the menu open.
    Future<bool> menuEnabled(WidgetTester tester) async {
      // By icon: each clip card has a "Tuỳ chọn" button of its own.
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();
      return tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, menuText),
          )
          .enabled;
    }

    /// Dismisses the open menu by tapping its barrier.
    Future<void> closeMenu(WidgetTester tester) async {
      await tester.tapAt(const Offset(5, 400));
      await tester.pumpAndSettle();
    }

    testWidgets('bấm nút thì nút và menu cùng khoá, đúng 30 giây sau tự mở '
        'lại mà không cần thao tác nào', (tester) async {
      final engine = engineOff();
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);
      final pressedAt = clock.current;

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pump();
      expect(engine.syncCalls, [manual]);
      expect(toast('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
      // Same icon, disabled, and the tooltip says why.
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNull);
      expect(find.byTooltip('$afterCycle$lockedLine'), findsOneWidget);
      expect(await menuEnabled(tester), isFalse);
      await closeMenu(tester);

      clock.current = pressedAt.add(const Duration(milliseconds: 29999));
      await tester.pump(const Duration(milliseconds: 29999));
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNull);
      expect(find.byTooltip('$afterCycle$lockedLine'), findsOneWidget);
      expect(await menuEnabled(tester), isFalse);
      await closeMenu(tester);

      clock.current = pressedAt.add(SyncController.manualSyncCooldown);
      await tester.pump(SyncController.manualSyncCooldown);
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNotNull);
      expect(find.byTooltip(afterCycle), findsOneWidget);
      expect(await menuEnabled(tester), isTrue);

      // The next press, here from the menu, runs a cycle of its own.
      await tester.tap(find.text(menuText));
      await tester.pumpAndSettle();
      expect(engine.syncCalls, [manual, manual]);
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNull);

      // Ends inside the new lock: taking the tab down stops its timer.
      await finish(tester);
    });

    testWidgets('máy ngủ quá 30 giây thì thức dậy nút mở lại cùng lúc với '
        'menu, không chờ Timer của nút', (tester) async {
      final engine = engineOff();
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);
      final pressedAt = clock.current;

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pump();
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNull);

      // Asleep: the wall clock runs on, the button's timer does not. Steps
      // through each state, as the app's lifecycle listeners expect.
      void lifecycle(List<AppLifecycleState> states) {
        for (final state in states) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
      }

      lifecycle(const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      clock.current = pressedAt.add(
        SyncController.manualSyncCooldown + const Duration(seconds: 1),
      );
      lifecycle(const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      await tester.pump();

      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNotNull);
      expect(find.byTooltip(afterCycle), findsOneWidget);
      expect(await menuEnabled(tester), isTrue);
      await closeMenu(tester);
      expect(engine.syncCalls, [manual]);
      await finish(tester);
    });

    testWidgets('bấm dồn ở nút và menu chỉ chạy một chu kỳ, một snack bar', (
      tester,
    ) async {
      final engine = engineOff();
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      // Two taps in one frame both reach the button as it was built, plus a
      // menu pick racing them; the controller takes only the first.
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.tap(find.byIcon(Icons.cloud_outlined));
      runSync(tester.element(find.byType(ClipboardTab)));
      await tester.pump();
      // A menu opened now has the entry locked; picking it does nothing.
      expect(await menuEnabled(tester), isFalse);
      await tester.tap(find.text(menuText));
      await tester.pump();
      await closeMenu(tester);

      expect(engine.syncCalls, [manual]);
      expect(sync.status.monthRequests, 13);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(toast('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('bấm ở menu thì nút cũng khoá', (tester) async {
      final engine = engineOff();
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      expect(await menuEnabled(tester), isTrue);
      await tester.tap(find.text(menuText));
      await tester.pumpAndSettle();

      expect(engine.syncCalls, [manual]);
      expect(toast('Đã đồng bộ — đẩy 0, nhận 0 mục'), findsOneWidget);
      expect(syncButton(tester, Icons.cloud_outlined).onPressed, isNull);
      expect(find.byTooltip('$afterCycle$lockedLine'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('chu kỳ lỗi vẫn khoá đủ 30 giây và báo lỗi', (tester) async {
      final engine = engineOff()
        ..status = const SyncStatus(
          state: SyncState.error,
          message: 'mất mạng',
        );
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);
      final pressedAt = clock.current;
      final failed =
          'Đồng bộ lỗi: mất mạng\n12 / $share request tháng này '
          '(máy này)$offLine';

      await tester.tap(find.byIcon(Icons.cloud_outlined));
      await tester.pump();
      expect(toast('Đồng bộ lỗi: mất mạng'), findsOneWidget);
      expect(syncButton(tester, Icons.cloud_off_rounded).onPressed, isNull);
      expect(find.byTooltip('$failed$lockedLine'), findsOneWidget);

      clock.current = pressedAt.add(const Duration(milliseconds: 29999));
      await tester.pump(const Duration(milliseconds: 29999));
      expect(syncButton(tester, Icons.cloud_off_rounded).onPressed, isNull);

      clock.current = pressedAt.add(SyncController.manualSyncCooldown);
      await tester.pump(SyncController.manualSyncCooldown);
      expect(syncButton(tester, Icons.cloud_off_rounded).onPressed, isNotNull);
      expect(find.byTooltip(failed), findsOneWidget);
      expect(engine.syncCalls, [manual]);
      await finish(tester);
    });

    testWidgets('build chưa cấu hình thì nút và mục menu đều tắt', (
      tester,
    ) async {
      final engine = engineOff(configured: false);
      final sync = await startSync(engine);
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      expect(
        find.byTooltip(
          'Chưa cấu hình — build với --dart-define-from-file=.env để bật '
          'đồng bộ',
        ),
        findsOneWidget,
      );
      expect(syncButton(tester, Icons.cloud_off_rounded).onPressed, isNull);
      expect(await menuEnabled(tester), isFalse);
      await closeMenu(tester);
      expect(engine.syncCalls, isEmpty);
      await finish(tester);
    });
  });
}
