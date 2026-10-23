import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/usecases/create_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_clip_groups.dart';
import 'package:event_notice/features/clipboard/domain/usecases/update_clip_group.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

final _now = DateTime(2026, 10, 22, 14, 30);
final _before = DateTime(2026, 10, 20, 9);

ClipGroup _group(String id, {String? name, int order = 0}) => ClipGroup(
  id: id,
  name: name ?? id,
  color: ClipGroup.palette.first,
  createdAt: _before,
  updatedAt: _before,
  sortOrder: order,
);

ClipItem _clip(String id, {String? groupId, bool pinned = false}) => ClipItem(
  id: id,
  content: id,
  type: ClipType.text,
  createdAt: _before,
  updatedAt: _before,
  isSaved: true,
  isPinned: pinned,
  groupId: groupId,
);

void main() {
  const storageFailure = StorageFailure('disk');
  late FakeClock clock;
  late SequentialIdGenerator ids;

  setUp(() {
    clock = FakeClock(_now);
    ids = SequentialIdGenerator();
  });

  test('GetClipGroups: theo sortOrder rồi theo tên', () async {
    final repo = InMemoryClipboardRepository(
      groups: [
        _group('b', name: 'Beta', order: 1),
        _group('z', name: 'Zeta', order: 0),
        _group('a', name: 'Alpha', order: 1),
      ],
    );

    final result = await GetClipGroups(repo)(const NoParams());

    expect([for (final g in result.valueOrNull!) g.id], ['z', 'a', 'b']);
  });

  group('CreateClipGroup', () {
    test('thêm vào cuối danh sách, tên đã cắt khoảng trắng', () async {
      final repo = InMemoryClipboardRepository(
        groups: [_group('g1'), _group('g2', order: 1)],
      );

      final group = (await CreateClipGroup(repo, ids, clock)((
        name: '  Công việc ',
        color: 0xFFE17055,
      ))).valueOrNull!;

      expect(group.id, 'id-1');
      expect(group.name, 'Công việc');
      expect(group.color, 0xFFE17055);
      expect(group.sortOrder, 2);
      expect(group.createdAt, _now);
      expect(group.updatedAt, _now);
      expect(repo.group('id-1'), group);
      expect(repo.log, ['saveGroup(id-1, share)']);
    });

    test('đọc nhóm lỗi thì không tạo', () async {
      final repo = InMemoryClipboardRepository()..failure = storageFailure;
      expect(
        await CreateClipGroup(repo, ids, clock)((name: 'x', color: 0)),
        const Err<ClipGroup>(storageFailure),
      );
      expect(repo.log, isEmpty);
    });
  });

  test('UpdateClipGroup đổi tên và màu, đóng dấu sửa lúc này', () async {
    final repo = InMemoryClipboardRepository(groups: [_group('g1', order: 3)]);

    final group = (await UpdateClipGroup(repo, clock)((
      group: repo.group('g1')!,
      name: 'Nhà',
      color: 0xFF6C7A89,
    ))).valueOrNull!;

    expect(group.id, 'g1');
    expect(group.name, 'Nhà');
    expect(group.color, 0xFF6C7A89);
    expect(group.sortOrder, 3);
    expect(group.createdAt, _before);
    expect(group.updatedAt, _now);
    expect(repo.group('g1'), group);
    expect(repo.log, ['saveGroup(g1, share)']);
  });

  group('DeleteClipGroup', () {
    test('giữ các clip của nhóm, bỏ nhóm và đánh dấu chúng dirty', () async {
      final repo = InMemoryClipboardRepository(
        groups: [_group('g1'), _group('g2')],
        clips: [
          _clip('a', groupId: 'g1'),
          _clip('b', groupId: 'g1', pinned: true),
          _clip('other', groupId: 'g2'),
          _clip('loose'),
        ],
      );

      final result = await DeleteClipGroup(repo, clock)(repo.group('g1')!);

      final ungrouped = result.valueOrNull!;
      expect([for (final c in ungrouped) c.id], unorderedEquals(['a', 'b']));
      for (final id in ['a', 'b']) {
        final clip = repo.clip(id)!;
        expect(clip.groupId, isNull, reason: id);
        expect(clip.isSaved, isTrue, reason: id);
        expect(clip.updatedAt, _now, reason: id);
      }
      expect(repo.clip('b')!.isPinned, isTrue);
      expect(repo.dirty, unorderedEquals(['a', 'b']));
      expect(repo.clip('other')!.groupId, 'g2');
      expect(repo.clip('loose')!.updatedAt, _before);
      expect(repo.group('g1'), isNull);
      expect(repo.group('g2'), isNotNull);
      // Clips leave the group before it goes.
      expect(repo.log.last, 'deleteGroup(g1, share)');
      expect(
        repo.log.take(2),
        unorderedEquals(['saveClip(a, share)', 'saveClip(b, share)']),
      );
    });

    test('nhóm rỗng thì chỉ xoá nhóm', () async {
      final repo = InMemoryClipboardRepository(groups: [_group('g1')]);

      final result = await DeleteClipGroup(repo, clock)(repo.group('g1')!);

      expect(result.valueOrNull, isEmpty);
      expect(repo.log, ['deleteGroup(g1, share)']);
    });

    test('đọc clip lỗi thì nhóm vẫn còn', () async {
      final repo = InMemoryClipboardRepository(groups: [_group('g1')])
        ..failure = storageFailure;

      expect(
        await DeleteClipGroup(repo, clock)(_group('g1')),
        const Err<List<ClipItem>>(storageFailure),
      );
      repo.failure = null;
      expect(repo.group('g1'), isNotNull);
      expect(repo.log, isEmpty);
    });
  });
}
