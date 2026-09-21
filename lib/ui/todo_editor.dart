import 'package:flutter/material.dart';

import '../models/todo.dart';
import 'format.dart';

/// Below this width the form takes the whole screen instead of sitting in a
/// dialog, the same rule the reminder editor follows.
const _compactWidth = 600.0;

/// Opens the create/edit form. Returns the edited todo, or null if cancelled.
Future<Todo?> showTodoEditor(
  BuildContext context, {
  Todo? existing,
  required String newId,
}) {
  final editor = _TodoEditor(existing: existing, newId: newId);
  if (MediaQuery.sizeOf(context).width < _compactWidth) {
    return Navigator.of(context).push<Todo>(
      MaterialPageRoute(builder: (_) => editor, fullscreenDialog: true),
    );
  }
  return showDialog<Todo>(context: context, builder: (_) => editor);
}

class _TodoEditor extends StatefulWidget {
  const _TodoEditor({this.existing, required this.newId});

  final Todo? existing;
  final String newId;

  @override
  State<_TodoEditor> createState() => _TodoEditorState();
}

class _TodoEditorState extends State<_TodoEditor> {
  late final _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _noteCtrl =
      TextEditingController(text: widget.existing?.note ?? '');
  late TodoPriority _priority =
      widget.existing?.priority ?? TodoPriority.normal;
  late DateTime? _due = widget.existing?.dueDate;
  String? _error;

  bool get _isNew => widget.existing == null;

  /// Midnight means no clock time was picked, matching [Todo.hasDueTime].
  bool get _hasTime {
    final due = _due;
    return due != null && (due.hour != 0 || due.minute != 0);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Hãy nhập việc cần làm.');
      return;
    }
    final existing = widget.existing;
    Navigator.of(context).pop(Todo(
      id: existing?.id ?? widget.newId,
      title: title,
      note: _noteCtrl.text.trim(),
      done: existing?.done ?? false,
      priority: _priority,
      dueDate: _due,
      completedAt: existing?.completedAt,
      createdAt: existing?.createdAt,
    ));
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final current = _due;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Chọn hạn hoàn thành',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (picked != null) {
      // Keep whatever time was already set; midnight means "cả ngày".
      setState(() => _due = DateTime(picked.year, picked.month, picked.day,
          current?.hour ?? 0, current?.minute ?? 0));
    }
  }

  /// Picks the hour and minute of the deadline, defaulting the day to today
  /// when none has been chosen yet.
  Future<void> _pickDueTime() async {
    final now = DateTime.now();
    final day = _due ?? now;
    final picked = await showTimePicker(
      context: context,
      initialTime: _hasTime
          ? TimeOfDay(hour: day.hour, minute: day.minute)
          : TimeOfDay(hour: now.hour, minute: now.minute),
      helpText: 'Chọn giờ hết hạn',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (picked != null) {
      setState(() => _due = DateTime(
          day.year, day.month, day.day, picked.hour, picked.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < _compactWidth;
    final title = _isNew ? 'Thêm việc cần làm' : 'Sửa việc cần làm';

    if (!compact) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: _form()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(onPressed: _submit, child: const Text('Lưu')),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(onPressed: _submit, child: const Text('LƯU')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [_form()],
        ),
      ),
    );
  }

  Widget _form() {
    final theme = Theme.of(context);
    final due = _due;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          autofocus: _isNew,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Việc cần làm',
            hintText: 'VD: Gửi báo giá cho khách',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Ghi chú (tuỳ chọn)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 22),
        Text('Mức ưu tiên', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<TodoPriority>(
            segments: [
              for (final p in TodoPriority.values)
                ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_priority},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
        ),
        const SizedBox(height: 18),
        Text('Hạn hoàn thành', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDue,
                icon: const Icon(Icons.event_outlined),
                label: Text(due == null ? 'Không đặt hạn' : formatDate(due)),
              ),
            ),
            if (due != null) ...[
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDueTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(_hasTime
                      ? '${two(due.hour)}:${two(due.minute)}'
                      : 'Cả ngày'),
                ),
              ),
              IconButton(
                tooltip: 'Bỏ hạn',
                onPressed: () => setState(() => _due = null),
                icon: const Icon(Icons.clear),
              ),
            ],
          ],
        ),
        if (_hasTime) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => setState(() => _due =
                    DateTime(due!.year, due.month, due.day)),
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Bỏ giờ'),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}
