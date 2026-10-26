import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/presentation/format.dart';
import '../../domain/entities/note.dart';
import '../note_color_label.dart';
import '../notes_controller.dart';
import '../widgets/note_markdown.dart';
import 'note_editor.dart';

/// Opens the read-only page for [note]. Editing, pinning and deleting all
/// happen through the [NotesController] in [context], so the page stays in
/// sync with the list behind it.
Future<void> showNoteView(BuildContext context, Note note) {
  final notes = context.read<NotesController>();
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      // Handed on explicitly so the page works wherever the provider sits.
      builder: (_) => ChangeNotifierProvider<NotesController>.value(
        value: notes,
        child: NoteViewPage(id: note.id),
      ),
    ),
  );
}

/// A single note, shown the way it was written: Markdown notes are rendered,
/// plain ones keep their line breaks. Nothing here is editable — the pencil
/// opens the editor instead.
class NoteViewPage extends StatelessWidget {
  const NoteViewPage({super.key, required this.id});

  /// Looked up on every build so an edit elsewhere shows up here too.
  final String id;

  Future<void> _edit(BuildContext context, Note note) async {
    final notes = context.read<NotesController>();
    final edited = await showNoteEditor(context, note: note);
    if (edited != null) await notes.save(edited);
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
    final notes = context.read<NotesController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xoá ghi chú?'),
        content: Text('"${note.displayTitle}" sẽ bị xoá khỏi danh sách.'),
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
    if (ok != true) return;
    await notes.delete(note.id);
    // The note is gone; the build below pops, but do it here as well so the
    // page never flashes its empty state.
    if (context.mounted) Navigator.of(context).maybePop();
  }

  Future<void> _copy(BuildContext context, Note note) async {
    await Clipboard.setData(ClipboardData(text: note.body));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép nội dung ghi chú')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NotesController>();
    final note = notes.noteById(id);
    // Deleted from somewhere else (or by the button below): close the page
    // rather than show a blank one.
    if (note == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final theme = Theme.of(context);
    final tint = noteColorOf(note.color, theme.colorScheme);
    final body = note.body.trim();

    return Scaffold(
      backgroundColor: tint,
      appBar: AppBar(
        backgroundColor: tint,
        title: const Text('Ghi chú'),
        actions: [
          IconButton(
            icon: Icon(note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
            color: note.pinned ? theme.colorScheme.primary : null,
            tooltip: note.pinned ? 'Bỏ ghim' : 'Ghim lên đầu',
            onPressed: () => notes.setPinned(note, !note.pinned),
          ),
          IconButton(
            icon: const Icon(Icons.copy_all_outlined),
            tooltip: 'Sao chép nội dung',
            onPressed: () => _copy(context, note),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Sửa ghi chú',
            onPressed: () => _edit(context, note),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Xoá ghi chú',
            onPressed: () => _confirmDelete(context, note),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SelectableText(
              note.displayTitle,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  'Sửa lần cuối ${formatDateTime(note.updatedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (note.markdown) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.article_outlined,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'Markdown',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            if (body.isEmpty)
              Text(
                'Ghi chú này chưa có nội dung.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              )
            else if (note.markdown)
              NoteMarkdown(data: body)
            else
              SelectableText(body, style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, note),
        tooltip: 'Sửa ghi chú',
        child: const Icon(Icons.edit),
      ),
    );
  }
}
