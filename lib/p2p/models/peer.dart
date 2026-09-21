/// Một thiết bị khác đang chạy app trong cùng mạng LAN.
class Peer {
  Peer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.seenAt,
  });

  /// Id cố định của thiết bị, sinh một lần rồi lưu lại trên máy đó.
  final String id;
  final String name;

  /// 'windows', 'android', ... — chỉ để chọn icon cho dễ nhìn.
  final String platform;

  /// IPv4 nhìn thấy trong gói UDP, cùng cổng HTTP mà thiết bị đó đang mở.
  final String address;
  final int port;

  /// Lần cuối nghe thấy thiết bị này; quá [staleAfter] thì coi như đã rời mạng.
  final DateTime seenAt;

  static const staleAfter = Duration(seconds: 15);

  bool get isStale => DateTime.now().difference(seenAt) > staleAfter;

  Uri uri(String path) => Uri.parse('http://$address:$port$path');

  Peer copyWith({
    String? name,
    String? platform,
    String? address,
    int? port,
    DateTime? seenAt,
  }) =>
      Peer(
        id: id,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        address: address ?? this.address,
        port: port ?? this.port,
        seenAt: seenAt ?? this.seenAt,
      );
}
