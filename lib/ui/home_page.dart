import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../clipboard/state/clipboard_store.dart';
import '../clipboard/ui/clip_actions.dart';
import '../clipboard/ui/clip_tabs.dart';
import '../models/reminder.dart';
import '../services/android_alarm_service.dart';
import '../services/note_store.dart';
import '../services/reminder_store.dart';
import '../services/startup_service.dart';
import '../services/todo_store.dart';
import 'deadline_card.dart';
import 'format.dart';
import 'notes_tab.dart';
import 'reminder_editor.dart';
import 'todo_editor.dart';
import 'todo_page.dart';

/// The main window: current time plus the reminders, deadlines, todos, notes
/// and the clipboard history.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.todos,
    required this.notes,
    this.notifications,
  });

  final ReminderStore store;
  final TodoStore todos;
  final NoteStore notes;

  /// Only on Android, where the OS owns the alarm schedule.
  final AndroidAlarmService? notifications;

  /// The reminder side owns the first tabs; the clipboard is the last one and
  /// splits into its four lists inside itself.
  static const _reminderTabs = 4;
  static const _clipboardTab = _reminderTabs;
  static const _tabCount = _reminderTabs + 1;

  Future<void> _add(BuildContext context, {required bool deadline}) async {
    final created = await showReminderEditor(
      context,
      newId: store.newId(),
      asDeadline: deadline,
    );
    if (created != null) await store.upsert(created);
  }

  Future<void> _addTodo(BuildContext context) async {
    final created = await showTodoEditor(context, newId: todos.newId());
    if (created != null) await todos.upsert(created);
  }

  Future<void> _edit(BuildContext context, Reminder r) async {
    final edited =
        await showReminderEditor(context, existing: r, newId: store.newId());
    if (edited != null) await store.upsert(edited);
  }

  Future<void> _confirmDelete(BuildContext context, Reminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá nhắc nhở?'),
        content: Text('"${r.title}" sẽ bị xoá khỏi danh sách.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok == true) await store.remove(r.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final reminders =
            store.reminders.where((r) => !r.isDeadline).toList();
        // Nearest deadline first; the ones already past sink to the bottom.
        final deadlines = store.reminders.where((r) => r.isDeadline).toList()
          ..sort((a, b) {
            final ap = a.timeLeft.isNegative, bp = b.timeLeft.isNegative;
            if (ap != bp) return ap ? 1 : -1;
            return a.deadlineAt.compareTo(b.deadlineAt);
          });
        final now = DateTime.now();

        // The clipboard's own bar, buttons and count follow its state, so the
        // page watches that store as well as the reminder one.
        final clips = context.watch<ClipboardStore>();
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
                        ? Row(
                            children:
                                clipboardActions(context, clipTab.section))
                        : const SizedBox.shrink(),
                  ),
                  _SettingsMenu(notifications: notifications),
                  const SizedBox(width: 8),
                ],
                bottom: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    const Tab(icon: Icon(Icons.alarm), text: 'Nhắc nhở'),
                    const Tab(
                        icon: Icon(Icons.hourglass_bottom), text: 'Deadline'),
                    const Tab(icon: Icon(Icons.checklist), text: 'Việc cần làm'),
                    const Tab(
                        icon: Icon(Icons.sticky_note_2_outlined),
                        text: 'Ghi chú'),
                    const Tab(
                        icon: Icon(Icons.content_paste_rounded),
                        text: 'Clipboard'),
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
                  1 => FloatingActionButton.extended(
                      onPressed: () => _add(context, deadline: true),
                      icon: const Icon(Icons.hourglass_top),
                      label: const Text('Thêm deadline'),
                    ),
                  2 => FloatingActionButton.extended(
                      onPressed: () => _addTodo(context),
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Thêm việc'),
                    ),
                  3 => FloatingActionButton.extended(
                      onPressed: () => createNote(context, notes),
                      icon: const Icon(Icons.note_add),
                      label: const Text('Thêm ghi chú'),
                    ),
                  _ => FloatingActionButton.extended(
                      onPressed: () => _add(context, deadline: false),
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('Thêm nhắc nhở'),
                    ),
                },
              ),
              body: TabBarView(
                children: [
                  reminders.isEmpty
                      ? const _EmptyState(
                          icon: Icons.alarm,
                          title: 'Chưa có nhắc nhở nào',
                          hint: 'Bấm "Thêm nhắc nhở" để tạo lịch báo cho '
                              'cuộc họp sắp tới.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: reminders.length,
                          itemBuilder: (context, i) => _ReminderCard(
                            reminder: reminders[i],
                            onToggle: (on) => store.setEnabled(reminders[i], on),
                            onEdit: () => _edit(context, reminders[i]),
                            onDelete: () => _confirmDelete(context, reminders[i]),
                          ),
                        ),
                  deadlines.isEmpty
                      ? const _EmptyState(
                          icon: Icons.hourglass_empty,
                          title: 'Chưa có deadline nào',
                          hint: 'Bấm "Thêm deadline" để đếm ngược tới hạn chót '
                              'của một việc.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: deadlines.length,
                          itemBuilder: (context, i) => DeadlineCard(
                            reminder: deadlines[i],
                            onEdit: () => _edit(context, deadlines[i]),
                            onDelete: () => _confirmDelete(context, deadlines[i]),
                          ),
                        ),
                  TodoListView(store: todos),
                  NotesTab(store: notes),
                  const ClipboardTab(),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}

/// App-level options: for now, whether Windows launches the app at login.
class _SettingsMenu extends StatefulWidget {
  const _SettingsMenu({this.notifications});

  final AndroidAlarmService? notifications;

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
    await widget.notifications?.requestPermissions();
    final exact = await widget.notifications?.canScheduleExactAlarms() ?? false;
    _say(exact
        ? 'Đã có quyền báo đúng giờ.'
        : 'Chưa được cấp quyền "Báo thức & nhắc nhở" — chuông có thể bị trễ.');
  }

  Future<void> _testRing() async {
    await widget.notifications?.testRing();
    _say('Đang phát thử chuông — bấm "Tắt chuông" trên thông báo để dừng.');
  }

  Future<void> _requestOverlay() async {
    if (await widget.notifications?.canDrawOverlays() ?? false) {
      _say('Đã có quyền hiện đè lên app khác.');
      return;
    }
    await widget.notifications?.requestOverlayPermission();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final android = widget.notifications != null;
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
        }
      },
      itemBuilder: (_) => [
        // Reachable from every tab: one cycle covers clips, việc and ghi chú.
        PopupMenuItem(
          value: 'sync',
          enabled: context.read<ClipboardStore>().config.isConfigured,
          child: const Text('Đồng bộ ngay (clip, việc, ghi chú)'),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Reminder reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = reminder.nextOccurrence;
    final snoozed = reminder.snoozedUntil;
    final dimmed = !reminder.enabled;

    final String status;
    if (!reminder.enabled) {
      status = reminder.isExpired && reminder.repeat == RepeatRule.once
          ? 'Đã xong'
          : 'Đang tắt';
    } else if (snoozed != null && snoozed.isAfter(DateTime.now())) {
      status = 'Báo lại ${formatCountdown(snoozed.difference(DateTime.now()))}';
    } else if (next != null) {
      status = formatCountdown(next.difference(DateTime.now()));
    } else {
      status = 'Đã qua';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatTime(reminder.time),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        describeSchedule(reminder),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _Tag(text: status, highlight: reminder.enabled),
                          if (reminder.leadMinutes > 0)
                            _Tag(text: 'Nhắc trước ${reminder.leadMinutes} phút'),
                          if (reminder.note.trim().isNotEmpty)
                            _Tag(text: reminder.note.trim()),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(value: reminder.enabled, onChanged: onToggle),
                PopupMenuButton<String>(
                  onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    PopupMenuItem(value: 'delete', child: Text('Xoá')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: highlight
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
      ),
    );
  }
}
