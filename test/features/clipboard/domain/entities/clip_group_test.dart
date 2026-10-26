import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 22, 8);

ClipGroup _group({String name = 'Công việc', int sortOrder = 0}) => ClipGroup(
  id: 'g1',
  name: name,
  color: 0xFF00B894,
  createdAt: _created,
  updatedAt: _created,
  sortOrder: sortOrder,
);

void main() {
  test('màu là giá trị ARGB kiểu int', () {
    expect(_group().color, 0xFF00B894);
  });

  test('bảng màu giữ nguyên 8 màu cũ, theo đúng thứ tự', () {
    expect(ClipGroup.palette, const [
      0xFF5B8DEF,
      0xFF00B894,
      0xFFE17055,
      0xFFA55EEA,
      0xFFF9A825,
      0xFFEF5DA8,
      0xFF20BFA9,
      0xFF6C7A89,
    ]);
  });

  test('copyWith đổi field được truyền, giữ id và createdAt', () {
    final later = DateTime(2026, 10, 22, 9);
    final copy = _group().copyWith(
      name: 'Nhà',
      color: 0xFF6C7A89,
      sortOrder: 3,
      updatedAt: later,
    );

    expect(copy.id, 'g1');
    expect(copy.createdAt, _created);
    expect(copy.name, 'Nhà');
    expect(copy.color, 0xFF6C7A89);
    expect(copy.sortOrder, 3);
    expect(copy.updatedAt, later);
    expect(_group().copyWith(), _group());
  });

  test('so bằng theo giá trị', () {
    expect(_group(), _group());
    expect(_group().hashCode, _group().hashCode);
    expect(_group(), isNot(_group(name: 'Khác')));
  });
}
