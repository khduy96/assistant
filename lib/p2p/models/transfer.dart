/// Chiều của một lượt truyền: máy này gửi đi hay nhận về.
enum TransferDirection { send, receive }

enum TransferState {
  /// Bên nhận đang chờ người dùng bấm "Nhận" (chỉ có ở chiều receive).
  pending,

  /// Đang nối máy / đang chạy dở.
  running,
  done,
  failed,

  /// Người dùng bấm huỷ, hoặc từ chối một lời mời nhận.
  cancelled,
}

/// Một tệp đang (hoặc đã) được truyền. Đối tượng này bị sửa tại chỗ trong lúc
/// truyền; [P2pStore] là nơi gọi notifyListeners nên UI chỉ cần nghe store.
class TransferTask {
  TransferTask({
    required this.id,
    required this.direction,
    required this.fileName,
    required this.peerName,
    this.peerId,
    this.size,
    this.state = TransferState.running,
  }) : startedAt = DateTime.now();

  final String id;
  final TransferDirection direction;
  final String fileName;
  final String peerName;
  final String? peerId;

  /// Tổng số byte, null khi bên gửi không khai báo được kích thước.
  final int? size;
  final DateTime startedAt;

  int transferred = 0;
  TransferState state;
  String? error;

  /// Đường dẫn tệp đã ghi xong (chiều nhận).
  String? savedPath;

  /// `content://...` của tệp sau khi đưa ra Download (chỉ Android), dùng để mở
  /// lại bằng app mặc định.
  String? savedUri;

  /// Cờ huỷ: vòng lặp đọc/ghi kiểm tra cờ này sau mỗi khối dữ liệu.
  bool cancelRequested = false;

  bool get isActive =>
      state == TransferState.running || state == TransferState.pending;

  /// 0..1, hoặc null khi không biết tổng dung lượng (thanh chạy vô định).
  double? get progress {
    final total = size;
    if (total == null || total <= 0) return null;
    return (transferred / total).clamp(0.0, 1.0);
  }
}
