import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/sync/domain/entities/sync_settings.dart';
import '../../../core/sync/domain/entities/sync_status.dart';
import '../../../core/sync/presentation/sync_controller.dart';
import '../domain/entities/clip_group.dart';
import '../domain/entities/clip_item.dart';
import 'clip_labels.dart';
import 'clipboard_controller.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ),
    );
}

/// Copies a clip back onto the system clipboard.
Future<void> copyClip(BuildContext context, ClipItem item) async {
  final ok = await context.read<ClipboardController>().copyToClipboard(item);
  if (ok && context.mounted) _toast(context, 'Đã copy vào clipboard');
}

Future<void> togglePinClip(BuildContext context, ClipItem item) async {
  final wasTemp = item.isTemp;
  final ok = await context.read<ClipboardController>().togglePin(item);
  if (!ok || !context.mounted) return;
  if (item.isPinned) {
    _toast(context, 'Đã bỏ ghim');
  } else {
    _toast(context, wasTemp ? 'Đã ghim và lưu vào danh sách lưu' : 'Đã ghim');
  }
}

/// Runs a sync cycle and reports the outcome — an icon alone is easy to miss.
///
/// Goes through [SyncController.pressSyncNow]: a press while
/// [SyncController.manualSyncLocked] does nothing and shows nothing.
Future<void> runSync(BuildContext context) async {
  final sync = context.read<SyncController>();
  final status = await sync.pressSyncNow();
  if (status == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  if (status.state == SyncState.error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Đồng bộ lỗi: ${status.message}'),
        duration: const Duration(seconds: 6),
      ),
    );
  } else {
    _toast(
      context,
      'Đã đồng bộ — đẩy ${status.pushed}, nhận ${status.pulled} mục',
    );
  }
}

/// The "Đồng bộ ngay" entry of a menu, picked as [value]; the caller runs
/// [runSync] for it. Read when the menu opens, so a menu left open while the
/// lock runs out stays locked until it is opened again.
PopupMenuItem<T> syncNowMenuItem<T>(BuildContext context, T value) =>
    PopupMenuItem<T>(
      value: value,
      enabled:
          context.read<SyncSettings>().isConfigured &&
          !context.read<SyncController>().manualSyncLocked,
      child: const Text('Đồng bộ ngay (clip, việc, ghi chú)'),
    );

/// Bottom sheet with every per-clip action.
Future<void> showClipActions(BuildContext context, ClipItem item) async {
  final store = context.read<ClipboardController>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final group = store.groupById(item.groupId);
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  item.preview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Copy vào clipboard'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  copyClip(context, item);
                },
              ),
              ListTile(
                leading: Icon(
                  item.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                ),
                title: Text(item.isPinned ? 'Bỏ ghim' : 'Ghim'),
                subtitle: item.isTemp
                    ? const Text('Ghim sẽ tự lưu clip này lại')
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  togglePinClip(context, item);
                },
              ),
              if (!item.isSaved)
                ListTile(
                  leading: const Icon(Icons.bookmark_add_outlined),
                  title: const Text('Lưu vào danh sách lưu'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await store.saveClip(item);
                    if (ok && context.mounted) _toast(context, 'Đã lưu');
                  },
                ),
              if (item.isSaved && !item.isPinned)
                ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined),
                  title: const Text('Bỏ lưu (trả về mục tạm)'),
                  subtitle: const Text('Sẽ tự xoá sau 1 ngày'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final ok = await store.unsaveClip(item);
                    if (ok && context.mounted) {
                      _toast(context, 'Đã trả về mục tạm');
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Chọn nhóm'),
                subtitle: Text(group?.name ?? 'Chưa phân nhóm'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  pickGroupForClip(context, item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Sửa nội dung'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  editClip(context, item);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  'Xoá',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final ok = await store.deleteClip(item);
                  if (ok && context.mounted) _toast(context, 'Đã xoá');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Group picker; choosing a group also saves the clip out of the temp list.
Future<void> pickGroupForClip(BuildContext context, ClipItem item) async {
  final store = context.read<ClipboardController>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text(
              'Chọn nhóm',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('Chưa phân nhóm'),
            trailing: item.groupId == null
                ? const Icon(Icons.check_rounded)
                : null,
            onTap: () async {
              Navigator.pop(sheetContext);
              await store.assignGroup(item, null);
            },
          ),
          for (final group in store.groups)
            ListTile(
              leading: Icon(Icons.folder_rounded, color: group.materialColor),
              title: Text(group.name),
              trailing: item.groupId == group.id
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () async {
                Navigator.pop(sheetContext);
                final ok = await store.assignGroup(item, group.id);
                if (ok && context.mounted) {
                  _toast(context, 'Đã thêm vào nhóm ${group.name}');
                }
              },
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Tạo nhóm mới…'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final created = await showGroupEditor(context);
              if (created != null) await store.assignGroup(item, created.id);
            },
          ),
        ],
      ),
    ),
  );
}

/// Create or rename a group. Returns the saved group, or null when cancelled
/// or when it could not be stored.
Future<ClipGroup?> showGroupEditor(
  BuildContext context, {
  ClipGroup? group,
}) async {
  final store = context.read<ClipboardController>();
  final picked = await showDialog<({String name, int color})>(
    context: context,
    builder: (_) => _GroupEditorDialog(group: group),
  );
  if (picked == null || picked.name.isEmpty) return null;

  if (group == null) return store.createGroup(picked.name, picked.color);
  return store.renameGroup(group, picked.name, picked.color);
}

/// Name and colour of a group. Pops with both when saved, with nothing when
/// cancelled. Owns its text controller, so the field outlives the closing
/// animation.
class _GroupEditorDialog extends StatefulWidget {
  const _GroupEditorDialog({this.group});

  final ClipGroup? group;

  @override
  State<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends State<_GroupEditorDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.group?.name ?? '',
  );
  late int _color = widget.group?.color ?? ClipGroup.palette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() =>
      Navigator.pop(context, (name: _name.text.trim(), color: _color));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.group == null ? 'Tạo nhóm' : 'Sửa nhóm'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Tên nhóm'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final option in ClipGroup.palette)
                GestureDetector(
                  onTap: () => setState(() => _color = option),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color(option),
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 3,
                        color: _color == option
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}

/// Editor for an existing clip, or for a brand new manual entry.
Future<void> editClip(
  BuildContext context,
  ClipItem? item, {
  String? groupId,
}) async {
  final store = context.read<ClipboardController>();
  final content = await showDialog<String>(
    context: context,
    builder: (_) => _ClipEditorDialog(item: item),
  );
  if (content == null || content.isEmpty) return;

  final ok = item == null
      ? await store.addManual(content, groupId: groupId) != null
      : await store.updateContent(item, content);
  if (ok && context.mounted) _toast(context, 'Đã lưu');
}

/// The content of a clip. Pops with it, trimmed, when saved, with nothing
/// when cancelled. Owns its text controller, so the field outlives the
/// closing animation.
class _ClipEditorDialog extends StatefulWidget {
  const _ClipEditorDialog({this.item});

  final ClipItem? item;

  @override
  State<_ClipEditorDialog> createState() => _ClipEditorDialogState();
}

class _ClipEditorDialogState extends State<_ClipEditorDialog> {
  late final TextEditingController _content = TextEditingController(
    text: widget.item?.content ?? '',
  );

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.item == null ? 'Thêm clip' : 'Sửa nội dung'),
      content: SizedBox(
        // Full-width dialogs overflow on phones; 460 is the desktop comfort cap.
        width: math.min(460, MediaQuery.sizeOf(context).width),
        child: TextField(
          controller: _content,
          autofocus: true,
          maxLines: 10,
          minLines: 4,
          decoration: const InputDecoration(hintText: 'Nội dung…'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _content.text.trim()),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}
