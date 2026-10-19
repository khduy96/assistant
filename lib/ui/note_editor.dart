import 'package:flutter/material.dart';

import '../models/note.dart';
import 'note_markdown.dart';

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
  final _bodyFocus = FocusNode();

  late bool _pinned = widget.existing?.pinned ?? false;
  late bool _markdown = widget.existing?.markdown ?? false;
  late NoteColor _color = widget.existing?.color ?? NoteColor.none;

  /// Markdown notes can flip between writing and seeing the rendered result.
  bool _preview = false;

  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  /// Wraps the selection (or drops a placeholder) with [action]'s syntax and
  /// leaves the cursor where the user is going to keep typing.
  void _insert(_MdAction action) {
    final text = _bodyCtrl.text;
    final sel = _bodyCtrl.selection.isValid
        ? _bodyCtrl.selection
        : TextSelection.collapsed(offset: text.length);

    final selected = sel.textInside(text);
    final content = selected.isEmpty ? action.placeholder : selected;

    // A block snippet has to start on a line of its own.
    var before = action.before;
    if (action.block &&
        sel.start > 0 &&
        !text.substring(0, sel.start).endsWith('\n')) {
      before = '\n$before';
    }

    final inserted = '$before$content${action.after}';
    final start = sel.start + before.length;

    _bodyCtrl.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, inserted),
      // Nothing was selected and there is a placeholder: select it so the next
      // keystroke replaces it. Otherwise just sit after what was inserted.
      selection: selected.isEmpty && content.isNotEmpty
          ? TextSelection(baseOffset: start, extentOffset: start + content.length)
          : TextSelection.collapsed(offset: sel.start + inserted.length),
    );
    _bodyFocus.requestFocus();
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
      markdown: _markdown,
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
        Row(
          children: [
            Expanded(
              child: Text('Nội dung', style: theme.textTheme.labelLarge),
            ),
            if (_markdown)
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Soạn'),
                    icon: Icon(Icons.edit_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Xem trước'),
                    icon: Icon(Icons.visibility_outlined, size: 16),
                  ),
                ],
                selected: {_preview},
                onSelectionChanged: (s) => setState(() => _preview = s.first),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_markdown && !_preview) ...[
          _MarkdownToolbar(onInsert: _insert),
          const SizedBox(height: 8),
        ],
        if (_markdown && _preview)
          _PreviewBox(
            data: _bodyCtrl.text.trim(),
            minHeight: compact ? 220 : 180,
          )
        else
          TextField(
            controller: _bodyCtrl,
            focusNode: _bodyFocus,
            // On a phone the page scrolls, so the field can grow; in the dialog
            // it is capped and scrolls inside itself.
            minLines: compact ? 8 : 6,
            maxLines: compact ? null : 12,
            keyboardType: TextInputType.multiline,
            textCapitalization: _markdown
                ? TextCapitalization.none
                : TextCapitalization.sentences,
            style: _markdown
                ? const TextStyle(fontFamily: 'monospace', fontSize: 14)
                : null,
            decoration: InputDecoration(
              hintText: _markdown
                  ? '# Tiêu đề\n\n- Gạch đầu dòng\n[Liên kết](https://example.com)'
                  : 'Gõ bất cứ thứ gì bạn muốn nhớ...',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _markdown,
          onChanged: (v) => setState(() {
            _markdown = v;
            if (!v) _preview = false;
          }),
          title: const Text('Viết bằng Markdown'),
          subtitle: const Text('Bảng, liên kết, tiêu đề, danh sách, code...'),
        ),
        const SizedBox(height: 12),
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

/// One button on the Markdown toolbar: what to put around the selection.
class _MdAction {
  const _MdAction({
    required this.icon,
    required this.tooltip,
    this.before = '',
    this.after = '',
    this.placeholder = '',
    this.block = false,
  });

  final IconData icon;
  final String tooltip;

  /// Text put in front of the selection, and after it.
  final String before;
  final String after;

  /// Dropped in when nothing is selected, and left selected so it can be typed
  /// over straight away.
  final String placeholder;

  /// True for snippets that must start on their own line (table, list, quote).
  final bool block;
}

const _mdActions = <_MdAction>[
  _MdAction(
    icon: Icons.format_bold,
    tooltip: 'Đậm',
    before: '**',
    after: '**',
    placeholder: 'chữ đậm',
  ),
  _MdAction(
    icon: Icons.format_italic,
    tooltip: 'Nghiêng',
    before: '*',
    after: '*',
    placeholder: 'chữ nghiêng',
  ),
  _MdAction(
    icon: Icons.title,
    tooltip: 'Tiêu đề',
    before: '## ',
    placeholder: 'Tiêu đề',
    block: true,
  ),
  _MdAction(
    icon: Icons.link,
    tooltip: 'Liên kết',
    before: '[',
    after: '](https://)',
    placeholder: 'tên liên kết',
  ),
  _MdAction(
    icon: Icons.table_chart_outlined,
    tooltip: 'Bảng',
    before: '| Cột 1 | Cột 2 |\n| --- | --- |\n| A | B |\n',
    block: true,
  ),
  _MdAction(
    icon: Icons.format_list_bulleted,
    tooltip: 'Danh sách',
    before: '- ',
    placeholder: 'mục',
    block: true,
  ),
  _MdAction(
    icon: Icons.format_list_numbered,
    tooltip: 'Danh sách đánh số',
    before: '1. ',
    placeholder: 'mục',
    block: true,
  ),
  _MdAction(
    icon: Icons.check_box_outlined,
    tooltip: 'Ô tích',
    before: '- [ ] ',
    placeholder: 'việc cần làm',
    block: true,
  ),
  _MdAction(
    icon: Icons.format_quote,
    tooltip: 'Trích dẫn',
    before: '> ',
    placeholder: 'trích dẫn',
    block: true,
  ),
  _MdAction(
    icon: Icons.code,
    tooltip: 'Code',
    before: '`',
    after: '`',
    placeholder: 'code',
  ),
  _MdAction(
    icon: Icons.data_object,
    tooltip: 'Khối code',
    before: '```\n',
    after: '\n```\n',
    placeholder: 'code',
    block: true,
  ),
  _MdAction(
    icon: Icons.horizontal_rule,
    tooltip: 'Đường kẻ',
    before: '\n---\n',
    block: true,
  ),
];

/// The row of formatting buttons above the body field.
class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({required this.onInsert});

  final void Function(_MdAction) onInsert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final a in _mdActions)
              IconButton(
                icon: Icon(a.icon, size: 20),
                tooltip: a.tooltip,
                visualDensity: VisualDensity.compact,
                onPressed: () => onInsert(a),
              ),
          ],
        ),
      ),
    );
  }
}

/// The rendered body, shown in place of the text field while previewing.
class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.data, required this.minHeight});

  final String data;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight, maxHeight: 420),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: data.isEmpty
            ? Text(
                'Chưa có gì để xem trước.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              )
            : NoteMarkdown(data: data, selectable: false),
      ),
    );
  }
}
