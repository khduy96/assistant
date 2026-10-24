import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
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
  /// button; without it the app bar is left out.
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
    final sync = SyncController(
      runSync: RunSync(engine),
      hasPendingChanges: HasPendingChanges(engine),
      getMonthRequests: GetMonthRequests(engine),
      watchLocalChanges: WatchLocalChanges(engine),
      getSyncSettings: GetSyncSettings(engine),
      clock: clock,
    );
    addTearDown(sync.dispose);
    await sync.start();
    await pumpTab(tester, clips: [clip('a')], sync: sync);

    expect(
      find.byTooltip(
        'Đồng bộ ngay (nha)\n12 / 3333 request tháng này (máy này)',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Đang ghi clipboard — chạm để dừng'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.cloud_sync_outlined));
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

    SyncController syncOn(FakeSyncEngine engine) => SyncController(
      runSync: RunSync(engine),
      hasPendingChanges: HasPendingChanges(engine),
      getMonthRequests: GetMonthRequests(engine),
      watchLocalChanges: WatchLocalChanges(engine),
      getSyncSettings: GetSyncSettings(engine),
      clock: clock,
    );

    IconButton syncButton(WidgetTester tester, IconData icon) =>
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    testWidgets('từ mức cảnh báo thì báo sắp hết, icon như thường', (
      tester,
    ) async {
      final engine = FakeSyncEngine()
        ..settings = const SyncSettings(
          isConfigured: true,
          autoSync: false,
          space: 'nha',
        )
        ..monthRequests = budget.warnAt;
      final sync = syncOn(engine);
      addTearDown(sync.dispose);
      await sync.start();
      await pumpTab(tester, clips: [clip('a')], sync: sync);

      expect(
        find.byTooltip(
          'Đồng bộ ngay (nha)\n${budget.warnAt} / $share request tháng này '
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
      expect(
        find.byTooltip(
          'Đồng bộ ngay\n${budget.stopAt + 1} / $share request tháng này '
          '(máy này)$spentNote',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.sync_disabled_rounded), findsOneWidget);

      await finish(tester);
      // Stops the fallback timer that watches for the month to change.
      sync.dispose();
    });
  });
}
