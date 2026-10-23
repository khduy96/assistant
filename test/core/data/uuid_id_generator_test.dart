import 'package:event_notice/core/data/uuid_id_generator.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('sinh id dạng uuid v4 như các id đã lưu', () {
    const IdGenerator ids = UuidIdGenerator();
    expect(ids.newId(), matches(uuidV4));
  });

  test('mỗi lần gọi ra một id khác', () {
    const IdGenerator ids = UuidIdGenerator();
    final seen = {for (var i = 0; i < 1000; i++) ids.newId()};
    expect(seen, hasLength(1000));
  });
}
