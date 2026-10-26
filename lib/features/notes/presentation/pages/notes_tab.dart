import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/presentation/format.dart';
import '../../domain/entities/note.dart';
import '../note_color_label.dart';
import '../notes_controller.dart';
import 'note_editor.dart';
import 'note_view_page.dart';

/// Opens the editor for a brand new note and stores it. Lives outside the tab
/// so the home page's button can create one without reaching into its state.
Future<void> createNote(BuildContext context) async {
  final notes = context.read<NotesController>();
  final blank = await notes.newNote();
  if (blank == null || !context.mounted) return;
  final created = await showNoteEditor(context, note: blank, isNew: true);
  if (created != null) await notes.save(created);
}

/// The notes tab: a search box over a list of note cards. Reads the
/// [NotesController] from the widget tree.
class NotesTab extends StatefulWidget {
  const NotesTab({super.key});

  @override
  State<NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<NotesTab> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    // Starts from the controller's query so the box never hides a filter that
    // is still applied to the list.
    _searchCtrl = TextEditingController(
      text: context.read<NotesController>().query,
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _edit(Note note) async {
    final notes = context.read<NotesController>();
    final edited = await showNoteEditor(context, note: note);
    if (edited != null) await notes.save(edited);
  }

  Future<void> _confirmDelete(Note note) async {
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
    if (ok == true) await notes.delete(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotesController>();
    final query = controller.query;
    final notes = controller.results;
    final empty = controller.count == 0;

    return Column(
      children: [
        if (!empty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: controller.setQuery,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Tìm trong ghi chú...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Xoá tìm kiếm',
                        onPressed: () {
                          _searchCtrl.clear();
                          controller.setQuery('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        Expanded(
          child: empty
              ? const _NotesEmptyState(
                  icon: Icons.sticky_note_2_outlined,
                  title: 'Chưa có ghi chú nào',
                  hint:
                      'Bấm "Thêm ghi chú" để lưu lại một ý tưởng, '
                      'mật khẩu wifi hay việc cần nhớ.',
                )
              : notes.isEmpty
              ? _NotesEmptyState(
                  icon: Icons.search_off,
                  title: 'Không tìm thấy ghi chú',
                  hint: 'Không có ghi chú nào chứa "$query".',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: notes.length,
                  itemBuilder: (context, i) => _NoteCard(
                    note: notes[i],
                    onOpen: () => showNoteView(context, notes[i]),
                    onEdit: () => _edit(notes[i]),
                    onDelete: () => _confirmDelete(notes[i]),
                    onTogglePin: () =>
                        controller.setPinned(notes[i], !notes[i].pinned),
                  ),
                ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  final Note note;

  /// Tapping the card reads the note; editing is a deliberate second step.
  final VoidCallback onOpen;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = noteColorOf(note.color, theme.colorScheme);
    final body = note.preview;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: tint,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (note.markdown) ...[
                          Icon(
                            Icons.article_outlined,
                            size: 15,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            note.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Sửa lần cuối ${formatDateTime(note.updatedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                color: note.pinned ? theme.colorScheme.primary : null,
                tooltip: note.pinned ? 'Bỏ ghim' : 'Ghim lên đầu',
                onPressed: onTogglePin,
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
    );
  }
}

/// Same look as the home page's empty state, kept local so the notes tab can
/// show a different message when a search comes back empty.
class _NotesEmptyState extends StatelessWidget {
  const _NotesEmptyState({
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
