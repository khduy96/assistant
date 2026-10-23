import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/services/clip_filter.dart';
import 'package:event_notice/features/clipboard/domain/services/clip_lists.dart';
import 'package:event_notice/features/clipboard/domain/services/clip_ordering.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

ClipItem _clip(
  String id, {
  String? content,
  ClipType type = ClipType.text,
  String? note,
  bool saved = false,
  bool pinned = false,
  String? groupId,
  int createdMin = 0,
  int updatedMin = 0,
}) => ClipItem(
  id: id,
  content: content ?? id,
  type: type,
  note: note,
  isSaved: saved,
  isPinned: pinned,
  groupId: groupId,
  createdAt: _min(createdMin),
  updatedAt: _min(updatedMin),
);

ClipGroup _group(String id, String name, int order) => ClipGroup(
  id: id,
  name: name,
  color: ClipGroup.palette.first,
  createdAt: _t0,
  updatedAt: _t0,
  sortOrder: order,
);

List<String> _ids(Iterable<ClipItem> clips) => [for (final c in clips) c.id];

void main() {
  group('ClipFilter', () {
    final clips = [
      _clip('a', content: 'Họp KHÁCH hàng lúc 9h'),
      _clip('b', content: 'mã giảm giá', note: 'Gửi cho Khách'),
      _clip('c', content: 'https://example.com', type: ClipType.link),
      _clip('d', content: 'không liên quan'),
    ];

    test('không có điều kiện thì cho qua tất cả, giữ thứ tự', () {
      expect(_ids(ClipFilter.none.apply(clips)), ['a', 'b', 'c', 'd']);
      expect(_ids(const ClipFilter(query: '   ').apply(clips)), [
        'a',
        'b',
        'c',
        'd',
      ]);
    });

    test('tìm trong nội dung hoặc ghi chú, không phân biệt hoa thường', () {
      expect(_ids(const ClipFilter(query: 'khách').apply(clips)), ['a', 'b']);
      expect(_ids(const ClipFilter(query: '  KHÁCH ').apply(clips)), [
        'a',
        'b',
      ]);
    });

    test('lọc theo loại', () {
      expect(_ids(const ClipFilter(type: ClipType.link).apply(clips)), ['c']);
    });

    test('loại và từ khoá cùng phải khớp', () {
      expect(
        _ids(
          const ClipFilter(query: 'example', type: ClipType.link).apply(clips),
        ),
        ['c'],
      );
      expect(
        _ids(
          const ClipFilter(query: 'khách', type: ClipType.link).apply(clips),
        ),
        isEmpty,
      );
    });
  });

  group('ClipOrdering', () {
    test('danh sách đã lưu: clip ghim trước, rồi theo updatedAt giảm dần', () {
      final sorted = [
        _clip('old', saved: true, updatedMin: 1),
        _clip('pinOld', pinned: true, saved: true, updatedMin: 2),
        _clip('new', saved: true, updatedMin: 30),
        _clip('pinNew', pinned: true, saved: true, updatedMin: 20),
      ]..sort(ClipOrdering.saved);

      expect(_ids(sorted), ['pinNew', 'pinOld', 'new', 'old']);
    });

    test('mới nhất trước và cũ nhất trước theo createdAt', () {
      final clips = [
        _clip('b', createdMin: 2),
        _clip('a', createdMin: 1),
        _clip('c', createdMin: 3),
      ];
      expect(_ids(clips.toList()..sort(ClipOrdering.newestFirst)), [
        'c',
        'b',
        'a',
      ]);
      expect(_ids(clips.toList()..sort(ClipOrdering.oldestFirst)), [
        'a',
        'b',
        'c',
      ]);
    });

    test('nhóm theo sortOrder, cùng vị trí thì theo tên', () {
      final groups = [
        _group('g3', 'Zeta', 1),
        _group('g2', 'Beta', 1),
        _group('g1', 'Alpha', 2),
        _group('g0', 'Omega', 0),
      ]..sort(ClipOrdering.groups);

      expect([for (final g in groups) g.id], ['g0', 'g2', 'g3', 'g1']);
    });
  });

  group('ClipLists', () {
    final clips = [
      _clip('temp1', createdMin: 1),
      _clip('temp2', content: 'tìm tôi', createdMin: 5),
      _clip('saved', saved: true, updatedMin: 10),
      _clip('pinned', saved: true, pinned: true, updatedMin: 1),
      _clip('inG', saved: true, groupId: 'g1', updatedMin: 20),
      _clip('pinInG', saved: true, pinned: true, groupId: 'g1'),
    ];

    test('clip tạm: mới nhất trước', () {
      expect(_ids(ClipLists.temp(clips)), ['temp2', 'temp1']);
    });

    test('đã lưu: ghim trước rồi theo updatedAt giảm dần', () {
      expect(_ids(ClipLists.saved(clips)), [
        'pinned',
        'pinInG',
        'inG',
        'saved',
      ]);
    });

    test('đã ghim', () {
      expect(_ids(ClipLists.pinned(clips)), ['pinned', 'pinInG']);
    });

    test('theo nhóm và chưa phân nhóm', () {
      expect(_ids(ClipLists.ofGroup(clips, 'g1')), ['pinInG', 'inG']);
      expect(_ids(ClipLists.ungroupedSaved(clips)), ['pinned', 'saved']);
    });

    test('áp bộ lọc trước khi cắt danh sách', () {
      expect(_ids(ClipLists.temp(clips, const ClipFilter(query: 'TÌM'))), [
        'temp2',
      ]);
      expect(ClipLists.saved(clips, const ClipFilter(query: 'tìm')), isEmpty);
    });
  });
}
