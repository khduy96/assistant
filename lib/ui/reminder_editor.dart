import 'package:flutter/material.dart';

import '../models/reminder.dart';
import 'format.dart';

/// Below this width the form takes the whole screen instead of sitting in a
/// dialog: on a phone a cramped dialog is worse than a normal page.
const _compactWidth = 600.0;

/// Opens the create/edit form. Returns the edited reminder, or null if cancelled.
///
/// [draft] fills the form in without turning it into an edit: it is how a
/// todo becomes a reminder, carrying its text and deadline across while the
/// form still reads "Thêm".
Future<Reminder?> showReminderEditor(
  BuildContext context, {
  Reminder? existing,
  Reminder? draft,
  required String newId,
  bool asDeadline = false,
}) {
  final editor = _ReminderEditor(
    existing: existing,
    draft: draft,
    newId: newId,
    asDeadline: asDeadline,
  );
  if (MediaQuery.sizeOf(context).width < _compactWidth) {
    return Navigator.of(context).push<Reminder>(
      MaterialPageRoute(builder: (_) => editor, fullscreenDialog: true),
    );
  }
  return showDialog<Reminder>(context: context, builder: (_) => editor);
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({
    this.existing,
    this.draft,
    required this.newId,
    this.asDeadline = false,
  });

  final Reminder? existing;

  /// Starting values for a brand new entry; ignored when [existing] is set.
  final Reminder? draft;
  final String newId;

  /// Creating a deadline instead of a repeating reminder.
  final bool asDeadline;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  static const _leadOptions = [0, 5, 10, 15, 30];
  static const _snoozeOptions = [1, 3, 5, 10, 15];
  static const _everyOptions = [30, 60, 90, 120, 180, 240];

  /// Where the form's starting values come from: the entry being edited, or
  /// the draft a conversion handed over.
  Reminder? get _source => widget.existing ?? widget.draft;

  late final _titleCtrl = TextEditingController(text: _source?.title ?? '');
  late final _noteCtrl = TextEditingController(text: _source?.note ?? '');

  late RepeatRule _repeat = _source?.repeat ?? RepeatRule.once;
  late DateTime _date = _source?.date ?? DateTime.now();
  late TimeOfDay _time = _source?.time ??
      TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  late final Set<int> _weekdays = {...?_source?.weekdays};
  late int _every = _source?.repeatEveryMinutes ?? 0;
  late TimeOfDay _endTime =
      _source?.endTime ?? const TimeOfDay(hour: 22, minute: 0);
  late final bool _isDeadline = _source?.isDeadline ?? widget.asDeadline;
  late int _lead = _source?.leadMinutes ?? (widget.asDeadline ? 60 : 0);
  late int _snooze = _source?.snoozeMinutes ?? 5;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Hãy nhập tên sự kiện.');
      return;
    }
    if (!_isDeadline && _repeat == RepeatRule.weekly && _weekdays.isEmpty) {
      setState(() => _error = 'Hãy chọn ít nhất một thứ trong tuần.');
      return;
    }
    if (!_isDeadline && _every > 0) {
      final start = _time.hour * 60 + _time.minute;
      final end = _endTime.hour * 60 + _endTime.minute;
      if (end <= start) {
        setState(() => _error = 'Giờ kết thúc phải sau giờ bắt đầu.');
        return;
      }
    }
    Navigator.of(context).pop(Reminder(
      id: widget.existing?.id ?? widget.newId,
      title: title,
      note: _noteCtrl.text.trim(),
      enabled: true,
      repeat: _repeat,
      date: DateTime(_date.year, _date.month, _date.day),
      time: _time,
      weekdays: _weekdays,
      repeatEveryMinutes: _isDeadline ? 0 : _every,
      endTime: !_isDeadline && _every > 0 ? _endTime : null,
      leadMinutes: _lead,
      snoozeMinutes: _snooze,
      isDeadline: _isDeadline,
      createdAt: widget.existing?.createdAt,
    ));
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? now : _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'Chọn ngày',
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<TimeOfDay?> _pickTimeOfDay(TimeOfDay initial) => showTimePicker(
        context: context,
        initialTime: initial,
        helpText: 'Chọn giờ',
        cancelText: 'Huỷ',
        confirmText: 'Chọn',
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );

  Future<void> _pickStartTime() async {
    final picked = await _pickTimeOfDay(_time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await _pickTimeOfDay(_endTime);
    if (picked != null) setState(() => _endTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < _compactWidth;
    final title = _isDeadline
        ? (_isNew ? 'Thêm deadline' : 'Sửa deadline')
        : (_isNew ? 'Thêm nhắc nhở' : 'Sửa nhắc nhở');

    if (!compact) {
      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(child: _form(compact: false)),
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
          TextButton(
            onPressed: _submit,
            child: const Text('LƯU'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [_form(compact: true)],
        ),
      ),
    );
  }

  Widget _form({required bool compact}) {
    final theme = Theme.of(context);
    // On a phone every control takes the full width: two-up rows make the
    // targets too small to hit comfortably.
    Widget pair(Widget first, Widget second) => compact
        ? Column(children: [first, const SizedBox(height: 12), second])
        : Row(children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          autofocus: _isNew,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: _isDeadline ? 'Việc cần hoàn thành' : 'Tên sự kiện',
            hintText: _isDeadline
                ? 'VD: Nộp báo cáo quý III'
                : 'VD: Họp online với khách hàng',
            border: const OutlineInputBorder(),
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
            hintText: 'VD: link Zoom, phòng họp...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 22),
        if (_isDeadline)
          Text('Hạn chót', style: theme.textTheme.labelLarge)
        else ...[
          Text('Lặp lại', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<RepeatRule>(
              segments: [
                for (final m in RepeatRule.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_repeat},
              showSelectedIcon: !compact,
              onSelectionChanged: (s) => setState(() => _repeat = s.first),
            ),
          ),
          if (_repeat == RepeatRule.weekly) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in weekdayShortNames.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: _weekdays.contains(entry.key),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _weekdays.add(entry.key);
                      } else {
                        _weekdays.remove(entry.key);
                      }
                    }),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 18),
        if (_isDeadline || _repeat == RepeatRule.once)
          pair(
            _PickerTile(
              icon: Icons.event,
              label: 'Ngày',
              value: formatDate(_date),
              onTap: _pickDate,
            ),
            _PickerTile(
              icon: Icons.schedule,
              label: 'Giờ',
              value: formatTime(_time),
              onTap: _pickStartTime,
            ),
          )
        else
          _PickerTile(
            icon: Icons.schedule,
            label: 'Giờ',
            value: formatTime(_time),
            onTap: _pickStartTime,
          ),
        if (_isDeadline) ...[
          const SizedBox(height: 10),
          Text(
            'App sẽ đếm ngược tới mốc này và rung chuông khi tới hạn.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ] else ...[
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _every > 0,
            title: const Text('Lặp lại trong ngày'),
            subtitle: const Text(
              'Nhắc lại nhiều lần trong ngày rồi dừng',
              style: TextStyle(fontSize: 12),
            ),
            onChanged: (on) => setState(() => _every = on ? 120 : 0),
          ),
          if (_every > 0) ...[
            const SizedBox(height: 4),
            pair(
              _MinutesField(
                label: 'Nhắc lại mỗi',
                value: _every,
                presets: _everyOptions,
                onChanged: (v) => setState(() => _every = v),
              ),
              _PickerTile(
                icon: Icons.stop_circle_outlined,
                label: 'Dừng lúc',
                value: formatTime(_endTime),
                onTap: _pickEndTime,
              ),
            ),
          ],
        ],
        const SizedBox(height: 18),
        pair(
          _MinutesField(
            label: _isDeadline ? 'Báo trước hạn' : 'Nhắc trước',
            value: _lead,
            presets: _leadOptions,
            allowZero: true,
            onChanged: (v) => setState(() => _lead = v),
          ),
          _MinutesField(
            label: 'Báo lại sau',
            value: _snooze,
            presets: _snoozeOptions,
            onChanged: (v) => setState(() => _snooze = v),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (compact) ...[
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check),
              label: Text(_isNew
                  ? (_isDeadline ? 'Thêm deadline' : 'Thêm nhắc nhở')
                  : 'Lưu thay đổi'),
            ),
          ),
        ],
      ],
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Minutes picker with presets plus a "Khác…" entry for any value the user
/// types, so the presets never become a ceiling.
class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.label,
    required this.value,
    required this.presets,
    required this.onChanged,
    this.allowZero = false,
  });

  final String label;
  final int value;
  final List<int> presets;
  final ValueChanged<int> onChanged;
  final bool allowZero;

  static const _customValue = -1;

  String _text(int minutes) =>
      minutes == 0 && allowZero ? 'Không' : formatEvery(minutes);

  Future<void> _askCustom(BuildContext context) async {
    final controller = TextEditingController(text: value > 0 ? '$value' : '');
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Số phút',
            hintText: 'VD: 45',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (t) => Navigator.of(ctx).pop(int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(controller.text.trim())),
            child: const Text('Chọn'),
          ),
        ],
      ),
    );
    if (minutes == null) return;
    // A day is the practical ceiling for these fields.
    onChanged(minutes.clamp(allowZero ? 0 : 1, 24 * 60));
  }

  @override
  Widget build(BuildContext context) {
    final values = {...presets, if (value > 0 || allowZero) value}.toList()
      ..sort();
    return DropdownButtonFormField<int>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final m in values)
          DropdownMenuItem(value: m, child: Text(_text(m))),
        const DropdownMenuItem(value: _customValue, child: Text('Khác…')),
      ],
      onChanged: (v) {
        if (v == null) return;
        if (v == _customValue) {
          _askCustom(context);
        } else {
          onChanged(v);
        }
      },
    );
  }
}
