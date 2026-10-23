import 'package:flutter/material.dart';

import '../../domain/entities/transfer.dart';
import '../p2p_controller.dart';
import '../p2p_labels.dart';

/// An incoming file waiting for the user to accept or decline it.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.controller, required this.offer});

  final P2pController controller;
  final Transfer offer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${offer.peerName} muốn gửi cho bạn',
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 2),
            Text(
              offer.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            Text(
              formatBytes(offer.size),
              style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => controller.respond(offer, accept: false),
                  child: const Text('Từ chối'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => controller.respond(offer, accept: true),
                  child: const Text('Nhận'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
