import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/note.dart';
import '../services/note_store.dart';
import 'format.dart';
import 'note_editor.dart';
import 'note_markdown.dart';

/// Opens the read-only page for [note]. Editing, pinning and deleting all
/// happen through [store], so the page stays in sync with the list behind it.
Future<void> showNoteView(
  BuildContext context,
  NoteStore store,
  Note note,
) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => NoteViewPage(store: store, id: note.id)),
  );
}

/// A single note, shown the way it was written: Markdown notes are rendered,
/// plain ones keep their line breaks. Nothing here is editable — the pencil
/// opens the editor instead.
class NoteViewPage extends StatelessWidget {
  const NoteViewPage({super.key, required this.store, required this.id});

  final NoteStore store;

  /// Looked up on every build so an edit elsewhere shows up here too.
  final String id;

  Future<void> _edit(BuildContext context, Note note) async {
    final edited = await showNoteEditor(
      context,
      existing: note,
      newId: store.newId(),
    );
    if (edited != null) await store.upsert(edited);
  }

  Future<void> _confirmDelete(BuildContext context, Note note) async {
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
    await store.remove(note.id);
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
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final note = store.notes.where((n) => n.id == id).firstOrNull;
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
                icon: Icon(
                    note.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                color: note.pinned ? theme.colorScheme.primary : null,
                tooltip: note.pinned ? 'Bỏ ghim' : 'Ghim lên đầu',
                onPressed: () => store.setPinned(note, !note.pinned),
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
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (note.markdown) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.article_outlined,
                          size: 14, color: theme.colorScheme.outline),
                      const SizedBox(width: 3),
                      Text(
                        'Markdown',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                if (body.isEmpty)
                  Text(
                    'Ghi chú này chưa có nội dung.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
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
      },
    );
  }
}
