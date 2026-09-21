import 'package:flutter/material.dart';

import '../models/note.dart';

/// Below this width the form takes the whole screen instead of sitting in a
/// dialog: on a phone a cramped dialog is worse than a normal page.
const _compactWidth = 600.0;

/// Background tint for each [NoteColor], picked to stay readable in both the
/// light and the dark theme.
Color? noteColorOf(NoteColor color, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (color) {
    NoteColor.none => null,
    NoteColor.yellow => dark ? const Color(0xFF4A3F14) : const Color(0xFFFEF3C7),
    NoteColor.green => dark ? const Color(0xFF16402C) : const Color(0xFFD1FAE5),
    NoteColor.blue => dark ? const Color(0xFF17334F) : const Color(0xFFDBEAFE),
    NoteColor.pink => dark ? const Color(0xFF4A1F2E) : const Color(0xFFFCE7F3),
    NoteColor.purple => dark ? const Color(0xFF32224F) : const Color(0xFFEDE9FE),
  };
}

/// Opens the create/edit form. Returns the edited note, or null if cancelled.
Future<Note?> showNoteEditor(
  BuildContext context, {
  Note? existing,
  required String newId,
}) {
  final editor = _NoteEditor(existing: existing, newId: newId);
  if (MediaQuery.sizeOf(context).width < _compactWidth) {
    return Navigator.of(context).push<Note>(
      MaterialPageRoute(builder: (_) => editor, fullscreenDialog: true),
    );
  }
  return showDialog<Note>(context: context, builder: (_) => editor);
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({this.existing, required this.newId});

  final Note? existing;
  final String newId;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final _titleCtrl =
      TextEditingController(text: widget.existing?.title ?? '');
  late final _bodyCtrl =
      TextEditingController(text: widget.existing?.body ?? '');

  late bool _pinned = widget.existing?.pinned ?? false;
  late NoteColor _color = widget.existing?.color ?? NoteColor.none;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty && body.isEmpty) {
      setState(() => _error = 'Hãy nhập tiêu đề hoặc nội dung.');
      return;
    }
    Navigator.of(context).pop(Note(
      id: widget.existing?.id ?? widget.newId,
      title: title,
      body: body,
      pinned: _pinned,
      color: _color,
      createdAt: widget.existing?.createdAt,
      updatedAt: widget.existing?.updatedAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < _compactWidth;
    final title = _isNew ? 'Thêm ghi chú' : 'Sửa ghi chú';

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
          TextButton(onPressed: _submit, child: const Text('LƯU')),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          autofocus: _isNew,
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Tiêu đề (tuỳ chọn)',
            hintText: 'VD: Ý tưởng cho buổi họp',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyCtrl,
          // On a phone the page scrolls, so the field can grow; in the dialog
          // it is capped and scrolls inside itself.
          minLines: compact ? 8 : 6,
          maxLines: compact ? null : 12,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Nội dung',
            hintText: 'Gõ bất cứ thứ gì bạn muốn nhớ...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 18),
        Text('Màu nhãn', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in NoteColor.values)
              _ColorDot(
                color: c,
                selected: c == _color,
                onTap: () => setState(() => _color = c),
              ),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _pinned,
          onChanged: (v) => setState(() => _pinned = v),
          title: const Text('Ghim lên đầu danh sách'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }
}

/// One swatch in the colour row; "none" shows as an outlined blank circle.
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final NoteColor color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = noteColorOf(color, scheme) ?? scheme.surface;
    return Tooltip(
      message: color.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == NoteColor.none
              ? Icon(Icons.format_color_reset_outlined,
                  size: 18, color: scheme.outline)
              : null,
        ),
      ),
    );
  }
}
