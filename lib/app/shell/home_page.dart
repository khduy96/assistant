import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/startup_service.dart';
import '../../core/presentation/format.dart';
import '../../core/sync/domain/entities/sync_settings.dart';
import '../../core/sync/presentation/auto_sync_toggle.dart';
import '../../core/sync/presentation/sync_controller.dart';
import '../../features/clipboard/presentation/clip_actions.dart';
import '../../features/clipboard/presentation/clipboard_controller.dart';
import '../../features/clipboard/presentation/clipboard_tab_state.dart';
import '../../features/clipboard/presentation/pages/clip_tabs.dart';
import '../../features/notes/presentation/pages/notes_tab.dart';
import '../../features/p2p/presentation/p2p_files.dart';
import '../../features/p2p/presentation/pages/p2p_tab.dart';
import '../../features/pomodoro/presentation/pages/pomodoro_page.dart';
import '../../features/reminders/presentation/pages/reminders_tab.dart';
import '../../features/reminders/presentation/reminders_controller.dart';
import '../../features/running_text/presentation/pages/running_text_tab.dart';
import '../../features/todos/presentation/pages/todo_page.dart';
import '../../features/todos/presentation/todo_reminder_editor.dart';

/// The main window: current time plus the reminders, deadlines, todos, notes
/// and the clipboard history.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.todoReminderEditor,
    required this.p2pFiles,
  });

  /// How the todo tab turns an item into a reminder or deadline; the todos
  /// themselves come from the `TodosController` in the widget tree, the
  /// reminders from the `RemindersController`.
  final TodoReminderEditor todoReminderEditor;

  /// How the "Gửi tệp" tab reaches this machine's files; the transfers
  /// themselves come from the `P2pController` in the widget tree.
  final P2pFiles p2pFiles;

  /// The reminder side owns the first tabs; the clipboard is the last one and
  /// splits into its four lists inside itself.
  static const _reminderTabs = 4;
  static const _clipboardTab = _reminderTabs;

  /// Truyền tệp ngang hàng: tab cuối cùng, sau clipboard.
  static const _p2pTab = _clipboardTab + 1;

  /// Chạy chữ kiểu bảng LED.
  static const _runningTextTab = _p2pTab + 1;
  static const _tabCount = _runningTextTab + 1;

  @override
  Widget build(BuildContext context) {
    // Ticks once a second while the window is on screen, which keeps the
    // clock in the app bar running.
    final reminders = context.watch<RemindersController>();
    final now = reminders.now();

    // The clipboard's own bar, buttons and count follow its state, so the
    // page watches that controller as well as the reminders.
    final clips = context.watch<ClipboardController>();
    final clipTab = context.watch<ClipboardTabState>();

    return DefaultTabController(
      length: _tabCount,
      child: Builder(builder: (context) {
        final tab = DefaultTabController.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Trợ lý'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Text(
                    '${two(now.hour)}:${two(now.minute)}:${two(now.second)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
              // Clipboard buttons only while the clipboard tab is open.
              AnimatedBuilder(
                animation: tab,
                builder: (context, _) => tab.index == _clipboardTab
                    ? Row(children: clipboardActions(context, clipTab.section))
                    : const SizedBox.shrink(),
              ),
              _SettingsMenu(reminders: reminders),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(icon: Icon(Icons.alarm), text: 'Nhắc nhở'),
                const Tab(icon: Icon(Icons.hourglass_bottom), text: 'Deadline'),
                const Tab(icon: Icon(Icons.checklist), text: 'Việc cần làm'),
                const Tab(
                    icon: Icon(Icons.sticky_note_2_outlined), text: 'Ghi chú'),
                const Tab(
                    icon: Icon(Icons.content_paste_rounded), text: 'Clipboard'),
                const Tab(icon: Icon(Icons.swap_horiz_rounded), text: 'Gửi tệp'),
                const Tab(
                    icon: Icon(Icons.text_rotation_none), text: 'Chạy chữ'),
              ],
            ),
          ),
          floatingActionButton: AnimatedBuilder(
            animation: tab,
            builder: (context, _) => switch (tab.index) {
              // Selecting clips has its own actions; the FAB would cover
              // the list while they are being picked.
              _clipboardTab => clips.isSelecting
                  ? const SizedBox.shrink()
                  : clipboardFab(context, clipTab.section),
              // Gửi tệp bắt đầu từ nút trên từng thiết bị, không từ FAB.
              _p2pTab => const SizedBox.shrink(),
              // Nút "Bắt đầu chạy chữ" đã nằm trong tab.
              _runningTextTab => const SizedBox.shrink(),
              1 => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'pomodoro',
                      tooltip: 'Đồng hồ Pomodoro',
                      onPressed: () => openPomodoro(context),
                      child: const Icon(Icons.timer_outlined),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'countdown',
                      tooltip: 'Đồng hồ đếm ngược',
                      onPressed: () => openCountdown(context),
                      child: const Icon(Icons.hourglass_bottom),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton.extended(
                      heroTag: 'add-deadline',
                      onPressed: () => addReminder(context, deadline: true),
                      icon: const Icon(Icons.hourglass_top),
                      label: const Text('Thêm deadline'),
                    ),
                  ],
                ),
              2 => FloatingActionButton.extended(
                  onPressed: () => addTodo(context),
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Thêm việc'),
                ),
              3 => FloatingActionButton.extended(
                  onPressed: () => createNote(context),
                  icon: const Icon(Icons.note_add),
                  label: const Text('Thêm ghi chú'),
                ),
              _ => FloatingActionButton.extended(
                  onPressed: () => addReminder(context, deadline: false),
                  icon: const Icon(Icons.add_alarm),
                  label: const Text('Thêm nhắc nhở'),
                ),
            },
          ),
          body: TabBarView(
            children: [
              const RemindersTab(),
              const DeadlinesTab(),
              TodoListView(reminderEditor: todoReminderEditor),
              const NotesTab(),
              const ClipboardTab(),
              P2pTab(files: p2pFiles),
              const RunningTextTab(),
            ],
          ),
        );
      }),
    );
  }
}

/// App-level options: for now, whether Windows launches the app at login.
class _SettingsMenu extends StatefulWidget {
  const _SettingsMenu({required this.reminders});

  /// Its OS alarm settings only exist on Android, where the OS rings.
  final RemindersController reminders;

  @override
  State<_SettingsMenu> createState() => _SettingsMenuState();
}

class _SettingsMenuState extends State<_SettingsMenu> {
  final _startup = StartupService();
  late bool _autoStart = Platform.isWindows && _startup.isEnabled();

  void _toggleAutoStart() {
    final applied = _startup.setEnabled(!_autoStart);
    setState(() => _autoStart = applied);
    _say(applied
        ? 'Đã bật: app sẽ tự chạy nền cùng Windows.'
        : 'Đã tắt tự khởi động cùng Windows.');
  }

  Future<void> _requestPermissions() async {
    await widget.reminders.requestPermissions();
    final exact = await widget.reminders.canScheduleExactAlarms();
    _say(exact
        ? 'Đã có quyền báo đúng giờ.'
        : 'Chưa được cấp quyền "Báo thức & nhắc nhở" — chuông có thể bị trễ.');
  }

  Future<void> _testRing() async {
    await widget.reminders.testRing();
    _say('Đang phát thử chuông — bấm "Tắt chuông" trên thông báo để dừng.');
  }

  Future<void> _requestOverlay() async {
    if (await widget.reminders.canDrawOverlays()) {
      _say('Đã có quyền hiện đè lên app khác.');
      return;
    }
    await widget.reminders.requestOverlayPermission();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final android = widget.reminders.ringsNatively;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_outlined),
      tooltip: 'Tuỳ chọn',
      onSelected: (v) {
        switch (v) {
          case 'autostart':
            _toggleAutoStart();
          case 'permissions':
            _requestPermissions();
          case 'test':
            _testRing();
          case 'overlay':
            _requestOverlay();
          case 'sync':
            runSync(context);
          case 'autosync':
            toggleAutoSync(context);
        }
      },
      itemBuilder: (_) => [
        // Reachable from every tab: one cycle covers clips, việc and ghi chú.
        syncNowMenuItem(context, 'sync'),
        // What is applied on this device, not the build's own setting; locked
        // until the choice has been read.
        CheckedPopupMenuItem(
          value: 'autosync',
          checked: context.read<SyncController>().autoSyncEnabled,
          enabled: context.read<SyncSettings>().isConfigured &&
              context.read<SyncController>().settingsLoaded,
          child: const Text('Sync tự động (clip, việc, ghi chú)'),
        ),
        const PopupMenuDivider(),
        if (android) ...[
          const PopupMenuItem(
            value: 'test',
            child: Text('Nghe thử chuông'),
          ),
          const PopupMenuItem(
            value: 'permissions',
            child: Text('Cấp quyền thông báo & báo đúng giờ'),
          ),
          const PopupMenuItem(
            value: 'overlay',
            child: Text('Cho phép hiện đè lên app khác'),
          ),
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'Chuông do hệ thống giữ lịch và tự phát,\nkêu cả khi app đã tắt hoặc máy khoá.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ] else ...[
          CheckedPopupMenuItem(
            value: 'autostart',
            checked: _autoStart,
            child: const Text('Tự mở khi khởi động Windows'),
          ),
          const PopupMenuItem(
            enabled: false,
            child: Text(
              'Đóng cửa sổ (X) chỉ thu nhỏ xuống khay,\nchuông vẫn chạy nền.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
