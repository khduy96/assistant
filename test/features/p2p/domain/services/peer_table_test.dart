import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:event_notice/features/p2p/domain/services/peer_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  test('nghe thấy thì thêm vào, nghe lại thì cập nhật', () {
    var table = PeerTable.record(const {}, PeerSighting(peer: peer('phone')));
    expect(table.keys, ['phone@45700']);

    final later = peer(
      'phone',
      name: 'Điện thoại mới',
      seenAt: seen.add(const Duration(seconds: 3)),
    );
    table = PeerTable.record(table, PeerSighting(peer: later));
    expect(table.values.single, later);
  });

  test('gói chào tạm biệt loại thiết bị ngay', () {
    final table = PeerTable.record(const {}, PeerSighting(peer: peer('phone')));
    final after = PeerTable.record(
      table,
      PeerSighting(peer: peer('phone'), left: true),
    );
    expect(after, isEmpty);
    // Bảng cũ không bị sửa.
    expect(table, hasLength(1));
  });

  test('hai bản app cùng máy (trùng id, khác cổng) là hai mục', () {
    var table = PeerTable.record(const {}, PeerSighting(peer: peer('me')));
    table = PeerTable.record(
      table,
      PeerSighting(peer: peer('me', port: 45701)),
    );
    expect(table, hasLength(2));
  });

  test('dọn các thiết bị đã im quá 15 giây', () {
    final table = {
      for (final p in [
        peer('old', seenAt: seen),
        peer('fresh', seenAt: seen.add(const Duration(seconds: 10))),
      ])
        p.key: p,
    };
    final pruned = PeerTable.prune(
      table,
      seen.add(const Duration(seconds: 20)),
    );
    expect(pruned.keys, ['fresh@45700']);
    expect(table, hasLength(2));
  });

  test('danh sách hiển thị bỏ thiết bị đã cũ và xếp theo tên', () {
    final now = seen.add(const Duration(seconds: 5));
    final list = PeerTable.visible([
      peer('b', name: 'banana'),
      peer('a', name: 'Apple'),
      peer('c', name: 'cherry', seenAt: DateTime(2000)),
    ], now);
    expect(list.map((p) => p.name), ['Apple', 'banana']);
  });
}
