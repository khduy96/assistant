import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../p2p_actions.dart';
import '../p2p_controller.dart';
import '../p2p_files.dart';
import '../widgets/offer_card.dart';
import '../widgets/p2p_section.dart';
import '../widgets/peer_tiles.dart';
import '../widgets/status_card.dart';
import '../widgets/transfer_tile.dart';

/// The "Gửi tệp" tab: any device seen on the network can be sent files
/// straight away.
///
/// Reads the [P2pController] from the tree. [files] reaches this machine's
/// files and file manager; it is handed down to the tab's actions.
class P2pTab extends StatelessWidget {
  const P2pTab({super.key, required this.files});

  final P2pFiles files;

  @override
  Widget build(BuildContext context) {
    return Provider<P2pFiles>.value(value: files, child: const _P2pList());
  }
}

class _P2pList extends StatelessWidget {
  const _P2pList();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<P2pController>();
    if (!controller.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final running = controller.isRunning;
    final peers = controller.peers;
    final transfers = controller.history;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        P2pStatusCard(controller: controller),
        for (final offer in controller.pendingOffers) ...[
          const SizedBox(height: 10),
          OfferCard(
            key: ValueKey(offer.id),
            controller: controller,
            offer: offer,
          ),
        ],
        const SizedBox(height: 18),
        P2pSectionTitle(
          title: 'Thiết bị trong mạng',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Thêm thiết bị bằng IP',
                icon: const Icon(Icons.add_link),
                onPressed: running ? () => addPeerByIp(context) : null,
              ),
              IconButton(
                tooltip: 'Tìm lại (có quét từng địa chỉ trong dải)',
                icon: const Icon(Icons.refresh),
                onPressed: running ? controller.refresh : null,
              ),
            ],
          ),
        ),
        for (final entry in controller.manualEntries)
          ManualPeerTile(
            key: ValueKey('manual $entry'),
            controller: controller,
            entry: entry,
          ),
        if (!running)
          const P2pHint(
            icon: Icons.wifi_off,
            text:
                'Đang tắt. Bật công tắc ở trên để thiết bị khác nhìn thấy '
                'máy này.',
          )
        else if (peers.isEmpty)
          const P2pHint(
            icon: Icons.search,
            text:
                'Chưa tự tìm thấy thiết bị nào. Mở app trên máy kia, bật '
                'truyền tệp, và bảo đảm hai máy cùng một mạng. Mạng công ty '
                'hay Wi-Fi khách thường chặn gói dò tìm — khi đó dùng nút 🔗 '
                'để thêm thẳng bằng IP.',
          )
        else
          for (final peer in peers)
            PeerTile(key: ValueKey(peer.key), peer: peer),
        const SizedBox(height: 18),
        P2pSectionTitle(
          title: 'Lượt truyền',
          trailing: TextButton(
            onPressed: transfers.any((t) => !t.isActive)
                ? controller.clearHistory
                : null,
            child: const Text('Xoá lịch sử'),
          ),
        ),
        if (transfers.isEmpty)
          const P2pHint(
            icon: Icons.swap_vert,
            text: 'Chưa có tệp nào được gửi hay nhận.',
          )
        else
          for (final transfer in transfers)
            TransferTile(
              key: ValueKey(transfer.id),
              controller: controller,
              transfer: transfer,
            ),
      ],
    );
  }
}
