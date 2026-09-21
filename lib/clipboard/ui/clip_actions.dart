import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/clip_group.dart';
import '../models/clip_item.dart';
import '../state/clipboard_store.dart';
import '../sync/sync_service.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1400),
    ));
}

/// Copies a clip back onto the system clipboard.
Future<void> copyClip(BuildContext context, ClipItem item) async {
  await context.read<ClipboardStore>().copyToClipboard(item);
  if (context.mounted) _toast(context, 'Đã copy vào clipboard');
}

Future<void> togglePinClip(BuildContext context, ClipItem item) async {
  final wasTemp = item.isTemp;
  await context.read<ClipboardStore>().togglePin(item);
  if (!context.mounted) return;
  if (item.isPinned) {
    _toast(context, 'Đã bỏ ghim');
  } else {
    _toast(context, wasTemp ? 'Đã ghim và lưu vào danh sách lưu' : 'Đã ghim');
  }
}

/// Runs a sync cycle and reports the outcome — an icon alone is easy to miss.
Future<void> runSync(BuildContext context) async {
  final store = context.read<ClipboardStore>();
  final status = await store.syncNow();
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  if (status.state == SyncState.error) {
    messenger.showSnackBar(SnackBar(
      content: Text('Đồng bộ lỗi: ${status.message}'),
      duration: const Duration(seconds: 6),
    ));
  } else {
    _toast(context,
        'Đã đồng bộ — đẩy ${status.pushed}, nhận ${status.pulled} mục');
  }
}

/// Bottom sheet with every per-clip action.
Future<void> showClipActions(BuildContext context, ClipItem item) async {
  final store = context.read<ClipboardStore>();
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
                leading: Icon(item.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined),
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
                    await store.saveClip(item);
                    if (context.mounted) _toast(context, 'Đã lưu');
                  },
                ),
              if (item.isSaved && !item.isPinned)
                ListTile(
                  leading: const Icon(Icons.bookmark_remove_outlined),
                  title: const Text('Bỏ lưu (trả về mục tạm)'),
                  subtitle: const Text('Sẽ tự xoá sau 1 ngày'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await store.unsaveClip(item);
                    if (context.mounted) _toast(context, 'Đã trả về mục tạm');
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
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(sheetContext).colorScheme.error),
                title: Text('Xoá',
                    style: TextStyle(
                        color: Theme.of(sheetContext).colorScheme.error)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await store.deleteClip(item);
                  if (context.mounted) _toast(context, 'Đã xoá');
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
  final store = context.read<ClipboardStore>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title:
                Text('Chọn nhóm', style: TextStyle(fontWeight: FontWeight.w600)),
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
                await store.assignGroup(item, group.id);
                if (context.mounted) {
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

/// Create or rename a group. Returns the saved group, or null when cancelled.
Future<ClipGroup?> showGroupEditor(BuildContext context,
    {ClipGroup? group}) async {
  final store = context.read<ClipboardStore>();
  final controller = TextEditingController(text: group?.name ?? '');
  var color = group?.color ?? ClipGroup.palette.first;

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(group == null ? 'Tạo nhóm' : 'Sửa nhóm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Tên nhóm'),
              onSubmitted: (_) => Navigator.pop(dialogContext, true),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final option in ClipGroup.palette)
                  GestureDetector(
                    onTap: () => setState(() => color = option),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(option),
                        shape: BoxShape.circle,
                        border: Border.all(
                          width: 3,
                          color: color == option
                              ? Theme.of(dialogContext).colorScheme.onSurface
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
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    ),
  );

  final name = controller.text.trim();
  controller.dispose();
  if (saved != true || name.isEmpty) return null;

  if (group == null) return store.createGroup(name, color);
  await store.renameGroup(group, name, color);
  return group.copyWith(name: name, color: color);
}

/// Editor for an existing clip, or for a brand new manual entry.
Future<void> editClip(BuildContext context, ClipItem? item,
    {String? groupId}) async {
  final store = context.read<ClipboardStore>();
  final controller = TextEditingController(text: item?.content ?? '');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(item == null ? 'Thêm clip' : 'Sửa nội dung'),
      content: SizedBox(
        // Full-width dialogs overflow on phones; 460 is the desktop comfort cap.
        width: math.min(460, MediaQuery.sizeOf(dialogContext).width),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 10,
          minLines: 4,
          decoration: const InputDecoration(hintText: 'Nội dung…'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Lưu'),
        ),
      ],
    ),
  );

  final content = controller.text.trim();
  controller.dispose();
  if (confirmed != true || content.isEmpty) return;

  if (item == null) {
    await store.addManual(content, groupId: groupId);
  } else {
    await store.updateContent(item, content);
  }
  if (context.mounted) _toast(context, 'Đã lưu');
}
