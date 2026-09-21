import 'package:flutter/material.dart';

import '../../models/clip_item.dart';
import 'clip_card.dart';

/// Responsive list of clips as a sliver, so the pages that host it can let
/// their app bar and search field scroll away on phones.
///
/// One column on phones, a grid once the viewport is wide enough.
class ClipSliver extends StatelessWidget {
  const ClipSliver({
    super.key,
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
  });

  final List<ClipItem> items;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(icon: emptyIcon, title: emptyTitle, hint: emptyHint),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 380).floor().clamp(1, 4);
    final padding = EdgeInsets.fromLTRB(
      12,
      4,
      12,
      96 + MediaQuery.paddingOf(context).bottom,
    );

    if (columns == 1) {
      return SliverPadding(
        padding: padding,
        sliver: SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, index) => ClipCard(item: items[index]),
        ),
      );
    }

    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 118,
        ),
        itemCount: items.length,
        itemBuilder: (_, index) => ClipCard(item: items[index]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
