import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/peer.dart';
import '../p2p_actions.dart';
import '../p2p_controller.dart';
import '../p2p_labels.dart';

/// A device heard on the LAN, with a button to send it files. On desktop,
/// files dropped onto it are sent as well.
class PeerTile extends StatelessWidget {
  const PeerTile({super.key, required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    return PeerDropZone(
      peer: peer,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(platformIcon(peer.platform)),
          title: Text(peer.name),
          subtitle: Text('${peer.address}:${peer.port}'),
          trailing: SendButton(peer: peer),
        ),
      ),
    );
  }
}

/// A device the user added by IP: always listed, with whether it answers.
class ManualPeerTile extends StatelessWidget {
  const ManualPeerTile({
    super.key,
    required this.controller,
    required this.entry,
  });

  final P2pController controller;

  /// The saved `host:port`.
  final String entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = controller.manualPeer(entry);
    final online = peer != null;

    final card = Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          online ? platformIcon(peer.platform) : Icons.link_off,
          color: online ? null : theme.colorScheme.outline,
        ),
        title: Text(online ? peer.name : entry),
        subtitle: Text(
          online ? '$entry — thêm bằng IP' : 'Không nối được — thêm bằng IP',
          style: online
              ? null
              : theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (online) SendButton(peer: peer),
            IconButton(
              tooltip: 'Bỏ khỏi danh sách',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => controller.removeManualPeer(entry),
            ),
          ],
        ),
      ),
    );
    if (!online) return card;
    return PeerDropZone(peer: peer, child: card);
  }
}

/// Picks files and sends them to [peer].
class SendButton extends StatelessWidget {
  const SendButton({super.key, required this.peer});

  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.tonalIcon(
      onPressed: () => pickAndSend(context, peer),
      icon: const Icon(Icons.upload_file),
      label: const Text('Gửi tệp'),
    );
    if (!canDropFiles) return button;
    return Tooltip(
      message: 'Chọn tệp, hoặc kéo thả tệp vào thẻ này',
      child: button,
    );
  }
}

/// Wraps a device card so files dropped onto it are sent to [peer]; lights up
/// while files are dragged over it. Only on desktop.
class PeerDropZone extends StatefulWidget {
  const PeerDropZone({super.key, required this.peer, required this.child});

  final Peer peer;
  final Widget child;

  @override
  State<PeerDropZone> createState() => _PeerDropZoneState();
}

class _PeerDropZoneState extends State<PeerDropZone> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!canDropFiles) return widget.child;
    final scheme = Theme.of(context).colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (details) {
        setState(() => _hovering = false);
        sendDropped(context, widget.peer, [
          for (final item in details.files) item.path,
        ]);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.92),
                    border: Border.all(color: scheme.primary, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        color: scheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Thả để gửi sang ${widget.peer.name}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
