import 'package:flutter/material.dart';

import '../../domain/entities/transfer.dart';
import '../p2p_actions.dart';
import '../p2p_controller.dart';
import '../p2p_labels.dart';

/// One transfer in the list: file, status line, progress while it runs, and
/// cancel / open buttons.
class TransferTile extends StatelessWidget {
  const TransferTile({
    super.key,
    required this.controller,
    required this.transfer,
  });

  final P2pController controller;
  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sending = transfer.direction == TransferDirection.send;

    final (IconData icon, Color color) = switch (transfer.state) {
      TransferState.done => (Icons.check_circle, Colors.green),
      TransferState.failed => (Icons.error_outline, theme.colorScheme.error),
      TransferState.cancelled => (Icons.block, theme.colorScheme.outline),
      _ => (
        sending ? Icons.north_east : Icons.south_west,
        theme.colorScheme.primary,
      ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    describeTransfer(transfer),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  if (transfer.isActive) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: transfer.progress),
                    ),
                  ],
                ],
              ),
            ),
            if (transfer.isActive)
              IconButton(
                tooltip: 'Huỷ',
                icon: const Icon(Icons.close),
                onPressed: () => controller.cancel(transfer),
              )
            else if (transfer.savedUri != null)
              IconButton(
                tooltip: 'Mở tệp',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => openReceived(context, transfer),
              )
            else if (transfer.savedPath case final path? when canOpenFolder)
              IconButton(
                tooltip: 'Mở thư mục chứa tệp',
                icon: const Icon(Icons.folder_open),
                onPressed: () => openInFileManager(context, path, select: true),
              ),
          ],
        ),
      ),
    );
  }
}
