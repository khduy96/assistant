import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../services/todo_store.dart';
import 'format.dart';
import 'todo_editor.dart';

/// The "Việc cần làm" tab: a quick-add box plus the checklist itself.
class TodoListView extends StatefulWidget {
  const TodoListView({super.key, required this.store});

  final TodoStore store;

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

  Future<void> _submitQuickAdd() async {
    final text = _quickAdd.text;
    if (text.trim().isEmpty) return;
    _quickAdd.clear();
    await widget.store.add(text);
    // Keep the caret in the box so several items can be typed in a row.
    _quickFocus.requestFocus();
  }

  Future<void> _edit(Todo todo) async {
    final edited = await showTodoEditor(
      context,
      existing: todo,
      newId: widget.store.newId(),
    );
    if (edited != null) await widget.store.upsert(edited);
  }

  Future<void> _confirmDelete(Todo todo) async {
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
    if (ok == true) await widget.store.remove(todo.id);
  }

  Future<void> _clearDone() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = await widget.store.clearDone();
    if (n == 0) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Đã xoá $n việc đã xong.')));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final open = widget.store.open;
        final done = widget.store.done;
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const Spacer(),
                    if (done.isNotEmpty)
                      TextButton.icon(
                        onPressed: _clearDone,
                        icon: const Icon(
                            Icons.cleaning_services_outlined,
                            size: 18),
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
                        for (final t in open)
                          _TodoTile(
                            todo: t,
                            onToggle: (v) => widget.store.setDone(t, v),
                            onEdit: () => _edit(t),
                            onDelete: () => _confirmDelete(t),
                          ),
                        if (done.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Đã xong',
                            style: theme.textTheme.labelLarge
                                ?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 6),
                          for (final t in done)
                            _TodoTile(
                              todo: t,
                              onToggle: (v) => widget.store.setDone(t, v),
                              onEdit: () => _edit(t),
                              onDelete: () => _confirmDelete(t),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checklist_rtl,
                  size: 72, color: theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text('Chưa có việc nào', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Gõ vào ô trên để thêm nhanh, hoặc bấm "Thêm việc" để đặt '
                'mức ưu tiên và hạn hoàn thành.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
}

/// Text of the deadline chip: the clock is only shown when one was picked.
String _dueLabel(Todo todo, DateTime due) {
  final time = todo.hasDueTime ? ' ${two(due.hour)}:${two(due.minute)}' : '';
  if (todo.isOverdue) return 'Quá hạn ${formatDate(due)}$time';
  if (todo.isDueToday) return todo.hasDueTime ? 'Hôm nay$time' : 'Hôm nay';
  return 'Hạn ${formatDate(due)}$time';
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.todo,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Todo todo;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = todo.dueDate;
    final highPriority = todo.priority == TodoPriority.high;

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
                          decoration:
                              todo.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (todo.note.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          todo.note.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.outline),
                        ),
                      ],
                      if (!todo.done &&
                          (due != null ||
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
                                text: _dueLabel(todo, due),
                                color: todo.isOverdue
                                    ? scheme.errorContainer
                                    : todo.isDueToday
                                        ? scheme.primaryContainer
                                        : scheme.surfaceContainerHighest,
                                onColor: todo.isOverdue
                                    ? scheme.onErrorContainer
                                    : todo.isDueToday
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
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

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color, required this.onColor});

  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}
