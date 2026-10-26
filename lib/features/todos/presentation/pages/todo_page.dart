import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/domain/result.dart';
import '../../domain/entities/linked_reminder.dart';
import '../../domain/entities/todo.dart';
import '../todo_labels.dart';
import '../todo_reminder_editor.dart';
import '../todos_controller.dart';
import 'todo_editor.dart';

/// Opens the editor for a brand new item and stores it. Lives outside the tab
/// so the home page's "Thêm việc" button can add one without reaching into
/// its state.
Future<void> addTodo(BuildContext context) async {
  final todos = context.read<TodosController>();
  final id = await todos.newId();
  if (id == null || !context.mounted) return;
  final created = await showTodoEditor(context, newId: id, now: todos.now);
  if (created != null) await todos.save(created);
}

/// The "Việc cần làm" tab: a quick-add box plus the checklist itself. Reads
/// the [TodosController] from the widget tree.
class TodoListView extends StatefulWidget {
  const TodoListView({super.key, required this.reminderEditor});

  /// Where a converted item lands: an item can be turned into a reminder or a
  /// deadline, and the tile then shows that alarm's countdown.
  final TodoReminderEditor reminderEditor;

  @override
  State<TodoListView> createState() => _TodoListViewState();
}

class _TodoListViewState extends State<TodoListView> {
  final _quickAdd = TextEditingController();
  final _quickFocus = FocusNode();

  @override
  void dispose() {
    _quickAdd.dispose();
    _quickFocus.dispose();
    super.dispose();
  }

  TodosController get _todos => context.read<TodosController>();

  Future<void> _submitQuickAdd() async {
    final text = _quickAdd.text;
    if (text.trim().isEmpty) return;
    _quickAdd.clear();
    await _todos.add(text);
    // Keep the caret in the box so several items can be typed in a row.
    if (mounted) _quickFocus.requestFocus();
  }

  Future<void> _edit(Todo todo) async {
    final todos = _todos;
    final edited = await showTodoEditor(
      context,
      existing: todo,
      now: todos.now,
    );
    if (edited != null) await todos.save(edited);
  }

  /// Carries the item across into a reminder form: same text, and the hạn
  /// hoàn thành becomes the ring time (see `DraftReminderFromTodo`).
  Future<void> _convert(Todo todo, {required bool deadline}) async {
    final todos = _todos;
    final messenger = ScaffoldMessenger.of(context);
    final draft = await todos.draftReminder(todo, deadline: deadline);
    if (draft == null || !mounted) return;
    final created = await widget.reminderEditor.createFromDraft(context, draft);
    if (created == null) return;
    await todos.linkReminder(todo, created.id);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            deadline
                ? 'Đã tạo deadline cho "${created.title}" — xem ở tab Deadline.'
                : 'Đã tạo nhắc nhở cho "${created.title}" — xem ở tab Nhắc nhở.',
          ),
        ),
      );
  }

  Future<void> _openReminder(Todo todo) async {
    final linked = (await _todos.findLinked(todo)).valueOrNull;
    if (linked == null || !mounted) return;
    await widget.reminderEditor.open(context, linked.id);
  }

  /// Drops the alarm but keeps the item on the checklist.
  Future<void> _removeReminder(Todo todo) async {
    final todos = _todos;
    final LinkedReminder linked;
    switch (await todos.findLinked(todo)) {
      case Err():
        return;
      case Ok(value: null):
        await todos.linkReminder(todo, null); // stale link, just forget it
        return;
      case Ok(value: final found?):
        linked = found;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(linked.isDeadline ? 'Bỏ deadline?' : 'Bỏ nhắc nhở?'),
        content: Text(
          '"${linked.title}" sẽ không báo nữa, việc vẫn còn '
          'trong danh sách.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Bỏ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await todos.removeReminder(todo, linked.id);
  }

  /// Ticking an item off silences its alarm; un-ticking turns it back on.
  Future<void> _toggle(Todo todo, bool done) => _todos.setDone(todo, done);

  Future<void> _confirmDelete(Todo todo) async {
    final todos = _todos;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá việc này?'),
        content: Text('"${todo.title}" sẽ bị xoá khỏi danh sách.'),
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
    if (ok == true) await todos.remove(todo.id);
  }

  Future<void> _clearDone() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await _todos.clearDone();
    if (n == 0) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Đã xoá $n việc đã xong.')));
  }

  Widget _tile(Todo todo, TodosController todos, DateTime now) => _TodoTile(
    key: ValueKey(todo.id),
    todo: todo,
    linked: todos.linkedOf(todo),
    now: now,
    onToggle: (v) => _toggle(todo, v),
    onEdit: () => _edit(todo),
    onDelete: () => _confirmDelete(todo),
    onConvert: (deadline) => _convert(todo, deadline: deadline),
    onOpenReminder: () => _openReminder(todo),
    onRemoveReminder: () => _removeReminder(todo),
  );

  @override
  Widget build(BuildContext context) {
    // The controller also notifies when linked alarms move on: a converted
    // item shows its alarm's countdown.
    final todos = context.watch<TodosController>();
    final open = todos.open;
    final done = todos.done;
    final now = todos.now();
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quickAdd,
                  focusNode: _quickFocus,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Thêm nhanh một việc rồi bấm Enter...',
                    prefixIcon: Icon(Icons.add_task),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submitQuickAdd(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Thêm',
                onPressed: _submitQuickAdd,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          ),
        ),
        if (open.isNotEmpty || done.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Text(
                  'Còn ${open.length} việc · đã xong ${done.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                if (done.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearDone,
                    icon: const Icon(
                      Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    label: const Text('Dọn việc đã xong'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: open.isEmpty && done.isEmpty
              ? _empty(theme)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                  children: [
                    for (final t in open) _tile(t, todos, now),
                    if (done.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Đã xong',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final t in done) _tile(t, todos, now),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rtl, size: 72, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('Chưa có việc nào', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Gõ vào ô trên để thêm nhanh, hoặc bấm "Thêm việc" để đặt '
            'mức ưu tiên và hạn hoàn thành.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    super.key,
    required this.todo,
    required this.linked,
    required this.now,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onConvert,
    required this.onOpenReminder,
    required this.onRemoveReminder,
  });

  final Todo todo;

  /// The alarm this item was converted into, if it still exists.
  final LinkedReminder? linked;

  /// What the deadline and countdown labels are measured against.
  final DateTime now;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// True asks for a deadline, false for a plain reminder.
  final ValueChanged<bool> onConvert;
  final VoidCallback onOpenReminder;
  final VoidCallback onRemoveReminder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = todo.dueDate;
    final highPriority = todo.priority == TodoPriority.high;
    final overdue = todo.isOverdue(now);
    final dueToday = todo.isDueToday(now);
    final alarm = alarmLabel(linked, now);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: todo.done ? 0.55 : 1,
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 4, 6),
            child: Row(
              children: [
                Checkbox(
                  value: todo.done,
                  onChanged: (v) => onToggle(v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: todo.done
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (todo.note.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          todo.note.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      ],
                      if (!todo.done &&
                          (due != null ||
                              linked != null ||
                              todo.priority != TodoPriority.normal)) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (todo.priority != TodoPriority.normal)
                              _Chip(
                                text: todo.priority.label,
                                color: highPriority
                                    ? scheme.errorContainer
                                    : scheme.surfaceContainerHighest,
                                onColor: highPriority
                                    ? scheme.onErrorContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            if (due != null)
                              _Chip(
                                text: dueLabel(todo, due, now),
                                color: overdue
                                    ? scheme.errorContainer
                                    : dueToday
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHighest,
                                onColor: overdue
                                    ? scheme.onErrorContainer
                                    : dueToday
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                            if (alarm != null)
                              _Chip(
                                text: alarm,
                                icon: linked!.isDeadline
                                    ? Icons.hourglass_bottom
                                    : Icons.alarm,
                                color: scheme.tertiaryContainer,
                                onColor: scheme.onTertiaryContainer,
                                onTap: onOpenReminder,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'edit':
                        onEdit();
                      case 'reminder':
                        onConvert(false);
                      case 'deadline':
                        onConvert(true);
                      case 'open':
                        onOpenReminder();
                      case 'unlink':
                        onRemoveReminder();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    const PopupMenuDivider(),
                    if (linked == null) ...[
                      const PopupMenuItem(
                        value: 'reminder',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add_alarm),
                          title: Text('Chuyển thành nhắc nhở'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'deadline',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.hourglass_top),
                          title: Text('Chuyển thành deadline'),
                        ),
                      ),
                    ] else ...[
                      PopupMenuItem(
                        value: 'open',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            linked!.isDeadline
                                ? Icons.hourglass_bottom
                                : Icons.alarm,
                          ),
                          title: Text(
                            linked!.isDeadline
                                ? 'Mở deadline đã tạo'
                                : 'Mở nhắc nhở đã tạo',
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'unlink',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.alarm_off),
                          title: Text(
                            linked!.isDeadline ? 'Bỏ deadline' : 'Bỏ nhắc nhở',
                          ),
                        ),
                      ),
                    ],
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'delete', child: Text('Xoá')),
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

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.color,
    required this.onColor,
    this.icon,
    this.onTap,
  });

  final String text;
  final Color color;
  final Color onColor;
  final IconData? icon;

  /// Set on the alarm chip, which opens the reminder it stands for.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor),
    );
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: icon == null
              ? label
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: onColor),
                    const SizedBox(width: 4),
                    label,
                  ],
                ),
        ),
      ),
    );
  }
}
