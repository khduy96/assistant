import 'dart:math';

import 'package:event_notice/features/clipboard/data/clip_id_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';

void main() {
  final at = DateTime.utc(2026, 10, 22, 9, 0, 0, 123, 456);

  test('id có dạng <micro base36>-<rand base36>, phần đầu lấy từ Clock', () {
    final ids = ClipIdGenerator(FakeClock(at));

    final id = ids.newId();

    expect(id, matches(RegExp(r'^[0-9a-z]+-[0-9a-z]+$')));
    final [stamp, salt] = id.split('-');
    expect(int.parse(stamp, radix: 36), at.microsecondsSinceEpoch);
    expect(stamp, at.microsecondsSinceEpoch.toRadixString(36));
    expect(int.parse(salt, radix: 36), lessThan(0x7fffffff));
  });

  test('đồng hồ chạy thì phần đầu chạy theo', () {
    final clock = FakeClock(at);
    final ids = ClipIdGenerator(clock);

    final first = ids.newId().split('-').first;
    clock.current = at.add(const Duration(microseconds: 1));
    final second = ids.newId().split('-').first;

    expect(int.parse(second, radix: 36) - int.parse(first, radix: 36), 1);
  });

  test('phần ngẫu nhiên lấy từ Random được truyền vào', () {
    final a = ClipIdGenerator(FakeClock(at), random: Random(7));
    final b = ClipIdGenerator(FakeClock(at), random: Random(7));
    final salt = Random(7).nextInt(0x7fffffff).toRadixString(36);

    expect(a.newId(), b.newId());
    expect(
      ClipIdGenerator(FakeClock(at), random: Random(7)).newId(),
      '${at.microsecondsSinceEpoch.toRadixString(36)}-$salt',
    );
  });

  test('cùng một thời điểm vẫn ra id khác nhau', () {
    final ids = ClipIdGenerator(FakeClock(at));
    expect({for (var i = 0; i < 50; i++) ids.newId()}, hasLength(50));
  });
}
