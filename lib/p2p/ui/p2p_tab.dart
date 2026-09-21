import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/peer.dart';
import '../models/transfer.dart';
import '../services/file_sender.dart';
import '../services/public_files.dart';
import '../state/p2p_store.dart';

/// Tab "Gửi tệp": thấy máy nào trong mạng thì bấm gửi thẳng sang máy đó.
class P2pTab extends StatelessWidget {
  const P2pTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<P2pStore>();
    if (!store.isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    final offers = store.pendingOffers;
    final peers = store.peers;
    final transfers = store.transfers
        .where((t) => t.state != TransferState.pending)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        _StatusCard(store: store),
        for (final offer in offers) ...[
          const SizedBox(height: 10),
          _OfferCard(store: store, task: offer),
        ],
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'Thiết bị trong mạng',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Thêm thiết bị bằng IP',
                icon: const Icon(Icons.add_link),
                onPressed:
                    store.isRunning ? () => _addByIp(context, store) : null,
              ),
              IconButton(
                tooltip: 'Tìm lại (có quét từng địa chỉ trong dải)',
                icon: const Icon(Icons.refresh),
                onPressed: store.isRunning ? store.refresh : null,
              ),
            ],
          ),
        ),
        for (final entry in store.manualEntries)
          _ManualTile(store: store, entry: entry),
        if (!store.isRunning)
          const _Hint(
            icon: Icons.wifi_off,
            text: 'Đang tắt. Bật công tắc ở trên để thiết bị khác nhìn thấy '
                'máy này.',
          )
        else if (peers.isEmpty)
          const _Hint(
            icon: Icons.search,
            text: 'Chưa tự tìm thấy thiết bị nào. Mở app trên máy kia, bật '
                'truyền tệp, và bảo đảm hai máy cùng một mạng. Mạng công ty '
                'hay Wi-Fi khách thường chặn gói dò tìm — khi đó dùng nút 🔗 '
                'để thêm thẳng bằng IP.',
          )
        else
          for (final peer in peers) _PeerTile(store: store, peer: peer),
        const SizedBox(height: 18),
        _SectionTitle(
          title: 'Lượt truyền',
          trailing: TextButton(
            onPressed: transfers.any((t) => !t.isActive)
                ? store.clearHistory
                : null,
            child: const Text('Xoá lịch sử'),
          ),
        ),
        if (transfers.isEmpty)
          const _Hint(
            icon: Icons.swap_vert,
            text: 'Chưa có tệp nào được gửi hay nhận.',
          )
        else
          for (final task in transfers) _TransferTile(store: store, task: task),
      ],
    );
  }
}

/// Hỏi địa chỉ IP rồi thử nối thẳng tới máy đó.
///
/// Lối thoát cho mạng công ty hoặc Wi-Fi khách chặn gói broadcast: hai máy vẫn
/// gọi nhau được, chỉ là không tự tìm thấy nhau.
Future<void> _addByIp(BuildContext context, P2pStore store) async {
  final controller = TextEditingController();
  final input = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Thêm thiết bị bằng IP'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mở app trên máy kia, xem dòng địa chỉ dưới tên máy ở tab "Gửi '
            'tệp" rồi gõ vào đây.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '172.28.0.50',
              helperText: 'Thêm :cổng nếu máy kia không dùng 45700',
            ),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Nối thử'),
        ),
      ],
    ),
  );
  if (input == null || input.trim().isEmpty) return;

  final error = await store.addManualPeer(input);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(error ?? 'Đã nối được, thiết bị nằm trong danh sách.'),
    ));
}

/// Chỉ desktop mới gọi được trình quản lý tệp bằng lệnh; Android/iOS không có
/// đường nào tương đương mà không kéo thêm thư viện.
final canOpenFolder = !Platform.isAndroid && !Platform.isIOS;

/// Mở [path] trong trình quản lý tệp của hệ điều hành. Với [select] là true thì
/// mở thư mục cha và trỏ sẵn vào tệp đó.
Future<void> openInFileManager(
  BuildContext context,
  String path, {
  bool select = false,
}) async {
  try {
    if (Platform.isWindows) {
      // explorer.exe trả mã thoát khác 0 cả khi mở thành công, nên chỉ bắt
      // ngoại lệ chứ không xét exitCode.
      await Process.run(
          'explorer.exe', select ? ['/select,', path] : [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', select ? ['-R', path] : [path]);
    } else {
      await Process.run(
          'xdg-open', [select ? File(path).parent.path : path]);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Không mở được thư mục: $e')));
  }
}

/// Mở chỗ đang cất tệp nhận được: thư mục trên desktop, màn hình Tải xuống
/// trên Android.
Future<void> _openSaveLocation(BuildContext context, P2pStore store) async {
  if (Platform.isAndroid) {
    if (await PublicFiles.openDownloads()) return;
    if (!context.mounted) return;
    _say(context, 'Máy không mở được màn hình Tải xuống. Tìm trong app Files, '
        'thư mục ${store.saveLocationLabel}.');
    return;
  }
  final path = await store.currentSaveDir();
  if (!context.mounted || path.isEmpty) return;
  await openInFileManager(context, path);
}

/// Mở tệp vừa nhận bằng app mặc định (Android).
Future<void> _openReceived(BuildContext context, TransferTask task) async {
  final uri = task.savedUri;
  if (uri == null) return;
  if (await PublicFiles.openFile(uri, task.fileName)) return;
  if (!context.mounted) return;
  _say(context, 'Máy chưa có app nào mở được loại tệp này.');
}

void _say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Chọn tệp rồi gửi sang [peer].
Future<void> _pickAndSend(
  BuildContext context,
  P2pStore store,
  Peer peer,
) async {
  final picked = await FilePicker.pickFiles(
    dialogTitle: 'Chọn tệp gửi sang ${peer.name}',
  );
  if (picked.isEmpty) return;

  final files = <OutgoingFile>[];
  for (final file in picked) {
    files.add(OutgoingFile(
      name: file.name,
      size: file.lengthSync() ?? await file.length(),
      open: file.readAsByteStream,
    ));
  }
  await store.sendFiles(peer, files);
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.store});

  final P2pStore store;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: store.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tên hiển thị của máy này'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ví dụ: Máy bàn phòng khách'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (name != null) await store.rename(name);
  }

  Future<void> _pickSaveDir(BuildContext context) async {
    final picked = await FilePicker.getDirectoryPath(
      dialogTitle: 'Chọn thư mục lưu tệp nhận được',
    );
    if (picked != null) await store.setSaveDir(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = store.isRunning;
    final subtitle = switch (true) {
      _ when store.isStarting => 'Đang bật…',
      _ when !running => 'Đang tắt',
      _ when store.localAddress.isEmpty => 'Đang chờ trên cổng ${store.port}',
      _ => '${store.localAddress}:${store.port}',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                  color: running
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.deviceName, style: theme.textTheme.titleMedium),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: store.enabled,
                  onChanged: store.isStarting
                      ? null
                      : (v) => store.setEnabled(v),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Tuỳ chọn truyền tệp',
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _rename(context);
                      case 'auto':
                        store.setAutoAccept(!store.autoAccept);
                      case 'dir':
                        _pickSaveDir(context);
                      case 'reset-dir':
                        store.setSaveDir(null);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Text('Đổi tên máy này'),
                    ),
                    CheckedPopupMenuItem(
                      value: 'auto',
                      checked: store.autoAccept,
                      child: const Text('Tự nhận, không hỏi'),
                    ),
                    if (canOpenFolder) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'dir',
                        child: Text('Chọn thư mục lưu…'),
                      ),
                      if (store.saveDir != null)
                        const PopupMenuItem(
                          value: 'reset-dir',
                          child: Text('Dùng thư mục mặc định'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
            if (store.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  store.error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                    child: Text(
                      'Tệp nhận được lưu ở: ${store.saveLocationLabel}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: Platform.isAndroid
                      ? 'Mở màn hình Tải xuống'
                      : 'Mở thư mục này',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_open, size: 20),
                  onPressed: () => _openSaveLocation(context, store),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lời mời nhận tệp đang chờ trả lời.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.store, required this.task});

  final P2pStore store;
  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${task.peerName} muốn gửi cho bạn',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 2),
            Text(
              task.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
            Text(
              formatBytes(task.size),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onPrimaryContainer),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => store.respond(task, accept: false),
                  child: const Text('Từ chối'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => store.respond(task, accept: true),
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

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.store, required this.peer});

  final P2pStore store;
  final Peer peer;

  static IconData _icon(String platform) => switch (platform) {
        'android' || 'ios' => Icons.smartphone,
        'windows' || 'linux' || 'macos' => Icons.computer,
        _ => Icons.devices_other,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_icon(peer.platform)),
        title: Text(peer.name),
        subtitle: Text('${peer.address}:${peer.port}'),
        trailing: FilledButton.tonalIcon(
          onPressed: () => _pickAndSend(context, store, peer),
          icon: const Icon(Icons.upload_file),
          label: const Text('Gửi tệp'),
        ),
      ),
    );
  }
}

/// Thiết bị người dùng tự khai bằng IP: luôn nằm trong danh sách, kèm trạng
/// thái nối được hay không.
class _ManualTile extends StatelessWidget {
  const _ManualTile({required this.store, required this.entry});

  final P2pStore store;
  final String entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = store.manualPeer(entry);
    final online = peer != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          online ? _PeerTile._icon(peer.platform) : Icons.link_off,
          color: online ? null : theme.colorScheme.outline,
        ),
        title: Text(online ? peer.name : entry),
        subtitle: Text(
          online ? '$entry — thêm bằng IP' : 'Không nối được — thêm bằng IP',
          style: online
              ? null
              : theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (online)
              FilledButton.tonalIcon(
                onPressed: () => _pickAndSend(context, store, peer),
                icon: const Icon(Icons.upload_file),
                label: const Text('Gửi tệp'),
              ),
            IconButton(
              tooltip: 'Bỏ khỏi danh sách',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => store.removeManualPeer(entry),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferTile extends StatelessWidget {
  const _TransferTile({required this.store, required this.task});

  final P2pStore store;
  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sending = task.direction == TransferDirection.send;

    final (IconData icon, Color color) = switch (task.state) {
      TransferState.done => (Icons.check_circle, Colors.green),
      TransferState.failed => (Icons.error_outline, theme.colorScheme.error),
      TransferState.cancelled => (Icons.block, theme.colorScheme.outline),
      _ => (
          sending ? Icons.north_east : Icons.south_west,
          theme.colorScheme.primary
        ),
    };

    final status = switch (task.state) {
      TransferState.done => sending
          ? 'Đã gửi tới ${task.peerName}'
          : 'Đã nhận từ ${task.peerName}',
      TransferState.failed => task.error ?? 'Lỗi',
      TransferState.cancelled => task.error ?? 'Đã huỷ',
      _ =>
        '${sending ? 'Đang gửi tới' : 'Đang nhận từ'} ${task.peerName} — '
            '${formatBytes(task.transferred)} / ${formatBytes(task.size)}',
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
                    task.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (task.isActive) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: task.progress),
                    ),
                  ],
                ],
              ),
            ),
            if (task.isActive)
              IconButton(
                tooltip: 'Huỷ',
                icon: const Icon(Icons.close),
                onPressed: () => store.cancel(task),
              )
            else if (task.savedUri != null)
              IconButton(
                tooltip: 'Mở tệp',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openReceived(context, task),
              )
            else if (task.savedPath != null && canOpenFolder)
              IconButton(
                tooltip: 'Mở thư mục chứa tệp',
                icon: const Icon(Icons.folder_open),
                onPressed: () =>
                    openInFileManager(context, task.savedPath!, select: true),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        ?trailing,
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// "12,3 MB" — null là chưa biết dung lượng.
String formatBytes(int? bytes) {
  if (bytes == null) return '?';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}
