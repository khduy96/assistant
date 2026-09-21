import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/clipboard_store.dart';
import 'clip_actions.dart';
import 'widgets/clip_list.dart';

/// All clips that belong to one group.
class GroupDetailPage extends StatelessWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final group = store.groupById(groupId);

    // The group can disappear while this page is open (deleted from here).
    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.folder_off_outlined,
          title: 'Nhóm đã bị xoá',
          hint: 'Các clip của nhóm vẫn nằm trong danh sách lưu.',
        ),
      );
    }

    final items = store.clipsOfGroup(groupId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.folder_rounded, color: group.materialColor),
            const SizedBox(width: 10),
            Expanded(child: Text(group.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sửa nhóm',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showGroupEditor(context, group: group),
          ),
          IconButton(
            tooltip: 'Xoá nhóm',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text('Xoá nhóm "${group.name}"?'),
                  content: const Text(
                      'Các clip bên trong vẫn được giữ lại trong danh sách lưu.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Huỷ'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Xoá'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await store.deleteGroup(group);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Thêm clip vào nhóm',
        onPressed: () => editClip(context, null, groupId: groupId),
        child: const Icon(Icons.add_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          ClipSliver(
            items: items,
            emptyIcon: Icons.folder_open_rounded,
            emptyTitle: 'Nhóm này chưa có clip',
            emptyHint:
                'Mở một clip bất kỳ, chọn "Chọn nhóm" rồi đưa nó vào nhóm này.',
          ),
        ],
      ),
    );
  }
}
