import 'package:flutter/material.dart';

import '../domain/entities/transfer.dart';

/// What the user reads about a [TransferProblem].
extension TransferProblemLabel on TransferProblem {
  String get label => switch (this) {
    TransferProblem.cancelled => 'Đã huỷ',
    TransferProblem.declined => 'Đã từ chối',
    TransferProblem.offerExpired => 'Hết giờ chờ trả lời',
    TransferProblem.rejectedByPeer => 'Thiết bị kia đã từ chối nhận',
    TransferProblem.unreachable =>
      'Không nối được tới thiết bị kia (cùng Wi-Fi? tường lửa?)',
    TransferProblem.failed => 'Lỗi',
  };
}

/// Why [transfer] did not go through, in words; null when it has no
/// [Transfer.problem]. A [TransferProblem.failed] says what went wrong when
/// it is known.
String? describeProblem(Transfer transfer) => switch (transfer.problem) {
  null => null,
  TransferProblem.failed =>
    transfer.problemDetail ?? TransferProblem.failed.label,
  final problem => problem.label,
};

/// The status line of a transfer in the list: who it went to or came from,
/// why it stopped, or how far along it is.
String describeTransfer(Transfer transfer) {
  final sending = transfer.direction == TransferDirection.send;
  return switch (transfer.state) {
    TransferState.done =>
      sending
          ? 'Đã gửi tới ${transfer.peerName}'
          : 'Đã nhận từ ${transfer.peerName}',
    TransferState.failed => describeProblem(transfer) ?? 'Lỗi',
    TransferState.cancelled => describeProblem(transfer) ?? 'Đã huỷ',
    _ =>
      '${sending ? 'Đang gửi tới' : 'Đang nhận từ'} ${transfer.peerName} — '
          '${formatBytes(transfer.transferred)} / ${formatBytes(transfer.size)}',
  };
}

/// Icon of a device by its platform tag ('windows', 'android', ...).
IconData platformIcon(String platform) => switch (platform) {
  'android' || 'ios' => Icons.smartphone,
  'windows' || 'linux' || 'macos' => Icons.computer,
  _ => Icons.devices_other,
};

/// "12,3 MB" — null is an unknown size.
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
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} ${units[unit]}';
}
