import 'package:flutter/material.dart';

import '../p2p_actions.dart';
import '../p2p_controller.dart';

/// This device: its name, where it can be reached, the on/off switch and the
/// options menu, then any error and where received files go.
class P2pStatusCard extends StatelessWidget {
  const P2pStatusCard({super.key, required this.controller});

  final P2pController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = controller.isRunning;
    final subtitle = switch (true) {
      _ when controller.isStarting => 'Đang bật…',
      _ when !running => 'Đang tắt',
      _ when controller.localAddress.isEmpty =>
        'Đang chờ trên cổng ${controller.port}',
      _ => '${controller.localAddress}:${controller.port}',
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
                      Text(
                        controller.deviceName,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: controller.enabled,
                  onChanged: controller.isStarting
                      ? null
                      : (v) => controller.setEnabled(v),
                ),
                _OptionsMenu(controller: controller),
              ],
            ),
            if (controller.error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
                    child: Text(
                      'Tệp nhận được lưu ở: ${controller.saveLocationLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: isAndroidDevice
                      ? 'Mở màn hình Tải xuống'
                      : 'Mở thư mục này',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.folder_open, size: 20),
                  onPressed: () => openSaveLocation(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionsMenu extends StatelessWidget {
  const _OptionsMenu({required this.controller});

  final P2pController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Tuỳ chọn truyền tệp',
      onSelected: (v) {
        switch (v) {
          case 'rename':
            renameDevice(context);
          case 'auto':
            controller.setAutoAccept(!controller.autoAccept);
          case 'dir':
            pickSaveDir(context);
          case 'reset-dir':
            controller.setSaveDir(null);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Đổi tên máy này')),
        CheckedPopupMenuItem(
          value: 'auto',
          checked: controller.autoAccept,
          child: const Text('Tự nhận, không hỏi'),
        ),
        if (canOpenFolder) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'dir', child: Text('Chọn thư mục lưu…')),
          if (controller.saveDir != null)
            const PopupMenuItem(
              value: 'reset-dir',
              child: Text('Dùng thư mục mặc định'),
            ),
        ],
      ],
    );
  }
}
