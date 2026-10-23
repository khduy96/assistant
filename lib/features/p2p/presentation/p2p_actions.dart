import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/entities/peer.dart';
import '../domain/entities/transfer.dart';
import 'p2p_controller.dart';
import 'p2p_files.dart';

/// Android: received files are reached through the Downloads screen.
bool get isAndroidDevice => defaultTargetPlatform == TargetPlatform.android;

/// Only desktop can start the file manager by command; Android and iOS have
/// no equivalent without another plugin.
bool get canOpenFolder =>
    defaultTargetPlatform != TargetPlatform.android &&
    defaultTargetPlatform != TargetPlatform.iOS;

/// Drag and drop only exists on desktop.
bool get canDropFiles => switch (defaultTargetPlatform) {
  TargetPlatform.windows ||
  TargetPlatform.macOS ||
  TargetPlatform.linux => true,
  _ => false,
};

void say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Asks for an IP address, then tries to reach the app there.
///
/// The way out for office networks and guest Wi-Fi that drop broadcasts: the
/// two devices can still call each other, they just never find each other.
Future<void> addPeerByIp(BuildContext context) async {
  final controller = context.read<P2pController>();
  final input = await showDialog<String>(
    context: context,
    builder: (_) => const _TextPromptDialog(
      title: 'Thêm thiết bị bằng IP',
      message:
          'Mở app trên máy kia, xem dòng địa chỉ dưới tên máy ở tab "Gửi '
          'tệp" rồi gõ vào đây.',
      hintText: '172.28.0.50',
      helperText: 'Thêm :cổng nếu máy kia không dùng 45700',
      confirm: 'Nối thử',
    ),
  );
  if (input == null || input.trim().isEmpty) return;

  final error = await controller.addManualPeer(input);
  if (!context.mounted) return;
  say(context, error ?? 'Đã nối được, thiết bị nằm trong danh sách.');
}

/// Asks for a new name for this device.
Future<void> renameDevice(BuildContext context) async {
  final controller = context.read<P2pController>();
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: 'Tên hiển thị của máy này',
      initialText: controller.deviceName,
      hintText: 'Ví dụ: Máy bàn phòng khách',
      confirm: 'Lưu',
    ),
  );
  if (name != null) await controller.rename(name);
}

/// Lets the user choose the folder for received files.
Future<void> pickSaveDir(BuildContext context) async {
  final controller = context.read<P2pController>();
  final picked = await context.read<P2pFiles>().pickDirectory(
    dialogTitle: 'Chọn thư mục lưu tệp nhận được',
  );
  if (picked != null) await controller.setSaveDir(picked);
}

/// Opens [path] in the system file manager. With [select], opens its folder
/// and points at it.
Future<void> openInFileManager(
  BuildContext context,
  String path, {
  bool select = false,
}) async {
  try {
    await context.read<P2pFiles>().openInFileManager(path, select: select);
  } catch (e) {
    if (!context.mounted) return;
    say(context, 'Không mở được thư mục: $e');
  }
}

/// Opens where received files go: the folder on desktop, the Downloads
/// screen on Android.
Future<void> openSaveLocation(BuildContext context) async {
  final controller = context.read<P2pController>();
  if (isAndroidDevice) {
    if (await controller.openDownloads()) return;
    if (!context.mounted) return;
    say(
      context,
      'Máy không mở được màn hình Tải xuống. Tìm trong app Files, '
      'thư mục ${controller.saveLocationLabel}.',
    );
    return;
  }
  final path = await controller.currentSaveDir();
  if (!context.mounted || path.isEmpty) return;
  await openInFileManager(context, path);
}

/// Opens a received file with the default app (Android).
Future<void> openReceived(BuildContext context, Transfer transfer) async {
  if (transfer.savedUri == null) return;
  if (await context.read<P2pController>().openReceived(transfer)) return;
  if (!context.mounted) return;
  say(context, 'Máy chưa có app nào mở được loại tệp này.');
}

/// Lets the user pick files, then sends them to [peer].
Future<void> pickAndSend(BuildContext context, Peer peer) async {
  final controller = context.read<P2pController>();
  final files = await context.read<P2pFiles>().pickFiles(
    dialogTitle: 'Chọn tệp gửi sang ${peer.name}',
  );
  if (files.isEmpty) return;
  await controller.sendFiles(peer, files);
}

/// Sends the files dropped onto the card of [peer]. Folders are left out:
/// the receiving side only understands single files.
Future<void> sendDropped(
  BuildContext context,
  Peer peer,
  List<String> paths,
) async {
  final controller = context.read<P2pController>();
  final dropped = await context.read<P2pFiles>().filesAt(paths);
  final files = dropped.files;
  if (dropped.skipped > 0 && context.mounted) {
    say(
      context,
      files.isEmpty
          ? 'Chưa gửi được thư mục — kéo từng tệp bên trong vào.'
          : 'Đã bỏ qua ${dropped.skipped} thư mục, chỉ gửi các tệp.',
    );
  }
  if (files.isEmpty) return;
  await controller.sendFiles(peer, files);
}

/// A dialog asking for one line of text; pops it, or null when cancelled.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.confirm,
    this.message,
    this.initialText,
    this.hintText,
    this.helperText,
  });

  final String title;
  final String confirm;
  final String? message;
  final String? initialText;
  final String? hintText;
  final String? helperText;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(
        hintText: widget.hintText,
        helperText: widget.helperText,
      ),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    );
    final message = widget.message;
    return AlertDialog(
      title: Text(widget.title),
      content: message == null
          ? field
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(message), const SizedBox(height: 12), field],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}
