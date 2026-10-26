import 'package:event_notice/features/clipboard/data/mappers/clip_group_mapper.dart';
import 'package:event_notice/features/clipboard/data/mappers/clip_mapper.dart';
import 'package:event_notice/features/clipboard/data/models/clip_group_model.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 10, 22, 9);

  group('ClipMapper', () {
    final clip = ClipItem(
      id: 'c1',
      content: 'xin chào',
      type: ClipType.text,
      createdAt: at,
      updatedAt: at.add(const Duration(minutes: 1)),
      copiedAt: at.add(const Duration(minutes: 2)),
      isSaved: true,
      isPinned: true,
      groupId: 'g1',
      note: 'ghi chú',
      copyCount: 3,
    );

    test('entity -> model -> entity giữ nguyên dữ liệu', () {
      expect(ClipMapper.toEntity(ClipMapper.toModel(clip)), clip);
    });

    test('toModel đánh dấu dirty và giữ remoteId được truyền vào', () {
      final model = ClipMapper.toModel(clip, remoteId: 'obj-1');
      expect(model.dirty, isTrue);
      expect(model.remoteId, 'obj-1');
      expect(ClipMapper.toModel(clip).remoteId, isNull);
    });

    test('toEntity bỏ lại trạng thái sync', () {
      final model = ClipModel(
        id: 'c1',
        content: 'x',
        type: ClipType.code,
        createdAt: at,
        updatedAt: at,
        remoteId: 'obj-1',
        dirty: false,
      );
      final entity = ClipMapper.toEntity(model);
      expect(entity.id, 'c1');
      expect(entity.type, ClipType.code);
      expect(entity.isTemp, isTrue);
    });
  });

  group('ClipGroupMapper', () {
    final group = ClipGroup(
      id: 'g1',
      name: 'Công việc',
      color: 0xFF5B8DEF,
      createdAt: at,
      updatedAt: at.add(const Duration(hours: 1)),
      sortOrder: 2,
    );

    test('entity -> model -> entity giữ nguyên dữ liệu', () {
      expect(ClipGroupMapper.toEntity(ClipGroupMapper.toModel(group)), group);
    });

    test('toModel đánh dấu dirty và giữ remoteId được truyền vào', () {
      final model = ClipGroupMapper.toModel(group, remoteId: 'obj-g');
      expect(model.dirty, isTrue);
      expect(model.remoteId, 'obj-g');
    });

    test('toEntity bỏ lại trạng thái sync', () {
      final model = ClipGroupModel(
        id: 'g1',
        name: 'Công việc',
        color: 0xFF5B8DEF,
        createdAt: at,
        updatedAt: at.add(const Duration(hours: 1)),
        sortOrder: 2,
        remoteId: 'obj-g',
        dirty: false,
      );
      expect(ClipGroupMapper.toEntity(model), group);
    });
  });
}
