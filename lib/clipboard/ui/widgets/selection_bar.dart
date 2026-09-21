import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/clip_item.dart';
import '../../state/clipboard_store.dart';
import '../clip_actions.dart';

/// Pieces of the app bar shown while clips are selected.
///
/// Kept as parts rather than a widget so the phone layout can drop them into a
/// `SliverAppBar` and the desktop layout into a plain `AppBar`.
class SelectionBar {
  const SelectionBar(this.visibleItems);

  /// Clips currently on screen — what "chọn tất cả" applies to.
  final List<ClipItem> visibleItems;

  Widget leading(BuildContext context) {
    final store = context.read<ClipboardStore>();
    return IconButton(
      tooltip: 'Bỏ chọn',
      icon: const Icon(Icons.close_rounded),
      onPressed: store.clearSelection,
    );
  }

  Widget title(BuildContext context) =>
      Text('Đã chọn ${context.watch<ClipboardStore>().selectedCount}');

  List<Widget> actions(BuildContext context) {
    final store = context.watch<ClipboardStore>();
    final scheme = Theme.of(context).colorScheme;
    final allSelected =
        visibleItems.isNotEmpty &&
        visibleItems.every((c) => store.isSelected(c.id));

    return [
      IconButton(
        tooltip: 'Copy tất cả mục đã chọn',
        icon: const Icon(Icons.copy_all_rounded),
        onPressed: () async {
          final count = await store.copySelected();
          if (context.mounted) {
            _toast(context, 'Đã copy $count clip vào clipboard');
          }
        },
      ),
      IconButton(
        tooltip: 'Ghim / bỏ ghim',
        icon: const Icon(Icons.push_pin_outlined),
        onPressed: () async {
          final (count, pinned) = await store.togglePinSelected();
          if (context.mounted) {
            _toast(
              context,
              pinned ? 'Đã ghim và lưu $count clip' : 'Đã bỏ ghim $count clip',
            );
          }
        },
      ),
      PopupMenuButton<String>(
        tooltip: 'Thao tác hàng loạt',
        onSelected: (value) => _run(context, store, value),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'save',
            child: ListTile(
              leading: Icon(Icons.bookmark_add_outlined),
              title: Text('Lưu tất cả'),
            ),
          ),
          const PopupMenuItem(
            value: 'unsave',
            child: ListTile(
              leading: Icon(Icons.bookmark_remove_outlined),
              title: Text('Bỏ lưu (về mục tạm)'),
            ),
          ),
          const PopupMenuItem(
            value: 'group',
            child: ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('Đưa vào nhóm…'),
            ),
          ),
          PopupMenuItem(
            value: allSelected ? 'none' : 'all',
            child: ListTile(
              leading: Icon(
                allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              ),
              title: Text(allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả'),
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              title: Text('Xoá', style: TextStyle(color: scheme.error)),
            ),
          ),
        ],
      ),
      const SizedBox(width: 4),
    ];
  }

  Future<void> _run(
    BuildContext context,
    ClipboardStore store,
    String action,
  ) async {
    switch (action) {
      case 'save':
        final count = await store.saveSelected();
        if (context.mounted) _toast(context, 'Đã lưu $count clip');
      case 'unsave':
        final count = await store.unsaveSelected();
        if (context.mounted) _toast(context, 'Đã trả $count clip về mục tạm');
      case 'group':
        await _pickGroup(context, store);
      case 'all':
        store.selectAll(visibleItems);
      case 'none':
        store.clearSelection();
      case 'delete':
        final removed = await store.deleteSelected();
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Đã xoá ${removed.length} clip'),
                action: SnackBarAction(
                  label: 'Hoàn tác',
                  onPressed: () => store.restoreClips(removed),
                ),
              ),
            );
        }
    }
  }

  Future<void> _pickGroup(BuildContext context, ClipboardStore store) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Đưa các clip đã chọn vào nhóm',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: const Text('Bỏ khỏi nhóm'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final count = await store.assignGroupSelected(null);
                if (context.mounted) {
                  _toast(context, 'Đã bỏ nhóm cho $count clip');
                }
              },
            ),
            for (final group in store.groups)
              ListTile(
                leading: Icon(Icons.folder_rounded, color: group.materialColor),
                title: Text(group.name),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final count = await store.assignGroupSelected(group.id);
                  if (context.mounted) {
                    _toast(context, 'Đã thêm $count clip vào ${group.name}');
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Tạo nhóm mới…'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final created = await showGroupEditor(context);
                if (created == null) return;
                final count = await store.assignGroupSelected(created.id);
                if (context.mounted) {
                  _toast(context, 'Đã thêm $count clip vào ${created.name}');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }
}
