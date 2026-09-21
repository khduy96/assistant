import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/clip_item.dart';
import '../../state/clipboard_store.dart';
import '../clip_actions.dart';
import '../format.dart';

/// One clipboard entry. Tapping it copies the content back to the clipboard.
///
/// On narrow screens the card drops its overflow button (long-press and swipe
/// cover the same actions) and gains swipe gestures: right to save/unsave,
/// left to delete with undo.
class ClipCard extends StatelessWidget {
  const ClipCard({super.key, required this.item});

  final ClipItem item;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selecting = context.select<ClipboardStore, bool>((s) => s.isSelecting);
    final card = _CardBody(item: item, compact: compact);
    // Swiping would fight the checkboxes while picking several clips.
    if (!compact || selecting) return card;

    return Dismissible(
      key: ValueKey(item.id),
      // Actions run here and the list rebuilds from the store, so the card is
      // never actually dismissed from the tree.
      confirmDismiss: (direction) async {
        final store = context.read<ClipboardStore>();
        if (direction == DismissDirection.startToEnd) {
          if (item.isSaved) {
            await store.unsaveClip(item);
            if (context.mounted) _toast(context, 'Đã trả về mục tạm');
          } else {
            await store.saveClip(item);
            if (context.mounted) _toast(context, 'Đã lưu');
          }
        } else {
          await store.deleteClip(item);
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(
                content: const Text('Đã xoá clip'),
                action: SnackBarAction(
                  label: 'Hoàn tác',
                  onPressed: () => store.restoreClip(item),
                ),
              ));
          }
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: Theme.of(context).colorScheme.primaryContainer,
        icon: item.isSaved
            ? Icons.bookmark_remove_outlined
            : Icons.bookmark_add_outlined,
        label: item.isSaved ? 'Bỏ lưu' : 'Lưu',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: Theme.of(context).colorScheme.errorContainer,
        icon: Icons.delete_outline,
        label: 'Xoá',
      ),
      child: card,
    );
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1400),
      ));
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.item, required this.compact});

  final ClipItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = context.watch<ClipboardStore>();
    final group = store.groupById(item.groupId);
    final selecting = store.isSelecting;
    final selected = store.isSelected(item.id);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? theme.colorScheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        // While selecting, a tap picks instead of copying.
        onTap: () {
          HapticFeedback.selectionClick();
          if (selecting) {
            store.toggleSelection(item.id);
          } else {
            copyClip(context, item);
          }
        },
        // Long press starts multi-select, the way phone galleries do.
        onLongPress: () {
          HapticFeedback.mediumImpact();
          store.toggleSelection(item.id);
        },
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, 10, compact ? 8 : 6, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: selecting
                        ? Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 18,
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                          )
                        : Icon(item.type.icon,
                            size: 18, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.preview,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFamily:
                            item.type == ClipType.code ? 'monospace' : null,
                        height: 1.35,
                      ),
                    ),
                  ),
                  // Per-item buttons step aside during multi-select.
                  if (!selecting) ...[
                    IconButton(
                      tooltip: item.isPinned ? 'Bỏ ghim' : 'Ghim',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: Icon(
                        item.isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        size: 18,
                        color: item.isPinned ? theme.colorScheme.primary : null,
                      ),
                      onPressed: () => togglePinClip(context, item),
                    ),
                    IconButton(
                      tooltip: 'Tuỳ chọn',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 36, height: 36),
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      onPressed: () => showClipActions(context, item),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 28, right: 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Meta(text: formatRelative(item.createdAt)),
                    if (!compact) _Meta(text: '${item.content.length} ký tự'),
                    if (item.isTemp)
                      _Meta(
                        text: formatRemaining(item.remaining),
                        color: theme.colorScheme.tertiary,
                        icon: Icons.schedule_rounded,
                      ),
                    if (group != null)
                      _Meta(
                        text: group.name,
                        color: group.materialColor,
                        icon: Icons.folder_rounded,
                      ),
                    if (item.copyCount > 0)
                      _Meta(
                        text: compact
                            ? '${item.copyCount}×'
                            : 'đã dùng ${item.copyCount} lần',
                        icon: Icons.replay_rounded,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.text, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: tone),
          const SizedBox(width: 3),
        ],
        Text(text, style: theme.textTheme.labelSmall?.copyWith(color: tone)),
      ],
    );
  }
}
