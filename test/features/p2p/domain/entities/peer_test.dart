import 'package:event_notice/features/p2p/domain/entities/peer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

void main() {
  group('isStale', () {
    test('còn mới trong vòng 15 giây kể từ lần nghe thấy', () {
      final p = peer('phone');
      expect(p.isStale(seen), isFalse);
      expect(p.isStale(seen.add(const Duration(seconds: 15))), isFalse);
    });

    test('im quá 15 giây thì coi như đã rời mạng', () {
      final p = peer('phone');
      expect(
        p.isStale(seen.add(const Duration(seconds: 15, milliseconds: 1))),
        isTrue,
      );
    });

    test('chỉ phụ thuộc thời điểm truyền vào', () {
      final old = peer('phone', seenAt: DateTime(2000));
      expect(old.isStale(DateTime(2000, 1, 1, 0, 0, 10)), isFalse);
      expect(old.isStale(DateTime(2000, 1, 1, 0, 1)), isTrue);
    });
  });

  test('khoá gồm id và cổng: hai bản app cùng máy không đè nhau', () {
    expect(peer('me', port: 45700).key, 'me@45700');
    expect(peer('me', port: 45701).key, isNot(peer('me').key));
  });

  test('uri trỏ tới server HTTP của thiết bị', () {
    final p = peer('pc', address: '172.28.0.50', port: 45701);
    expect(p.uri('/upload'), Uri.parse('http://172.28.0.50:45701/upload'));
  });

  test('copyWith giữ id, thay các trường được truyền', () {
    final later = seen.add(const Duration(seconds: 3));
    final p = peer('pc').copyWith(name: 'Máy mới', seenAt: later);
    expect(p.id, 'pc');
    expect(p.name, 'Máy mới');
    expect(p.seenAt, later);
    expect(p.address, '192.168.1.20');
    expect(peer('pc').copyWith(), peer('pc'));
  });

  test('so sánh bằng theo giá trị', () {
    expect(peer('pc'), peer('pc'));
    expect(peer('pc').hashCode, peer('pc').hashCode);
    expect(peer('pc'), isNot(peer('pc', port: 1)));
    expect(
      PeerSighting(peer: peer('pc'), left: true),
      PeerSighting(peer: peer('pc'), left: true),
    );
    expect(PeerSighting(peer: peer('pc')).left, isFalse);
  });
}
