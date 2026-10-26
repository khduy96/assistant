import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/models/clip_group_model.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../clip_db.dart';

void main() {
  useFfiSqlite();

  late ClipDb db;
  late ClipLocalDataSource source;

  setUp(() async {
    db = await ClipDb.open();
    source = ClipLocalDataSource(db.db);
  });

  tearDown(() => db.close());

  final at = DateTime(2026, 10, 22, 9);

  ClipModel clip(
    String id, {
    String? content,
    String? groupId,
    String? remoteId,
    bool dirty = true,
    DateTime? createdAt,
  }) => ClipModel(
    id: id,
    content: content ?? 'nội dung $id',
    type: ClipType.text,
    createdAt: createdAt ?? at,
    updatedAt: at,
    isSaved: true,
    groupId: groupId,
    remoteId: remoteId,
    dirty: dirty,
  );

  ClipGroupModel group(String id, {String name = 'Nhóm', String? remoteId}) =>
      ClipGroupModel(
        id: id,
        name: name,
        color: 0xFF5B8DEF,
        createdAt: at,
        updatedAt: at,
        remoteId: remoteId,
        dirty: remoteId == null,
      );

  test('clips xếp theo created_at giảm dần; tìm theo id và nội dung', () async {
    await source.upsertClip(clip('a', createdAt: at));
    await source.upsertClip(
      clip('b', createdAt: at.add(const Duration(minutes: 1))),
    );

    expect((await source.clips()).map((c) => c.id), ['b', 'a']);
    expect((await source.clipById('a'))!.content, 'nội dung a');
    expect(await source.clipById('x'), isNull);
    expect((await source.clipByContent('nội dung b'))!.id, 'b');
    expect(await source.clipByContent('nội dung'), isNull);
  });

  test('upsertClip với keepRemoteId giữ remote_id đang lưu', () async {
    await source.upsertClip(clip('a', remoteId: 'obj-a', dirty: false));

    await source.upsertClip(
      clip('a', content: 'đã sửa', remoteId: null),
      keepRemoteId: true,
    );

    final stored = (await source.clipById('a'))!;
    expect(stored.content, 'đã sửa');
    expect(stored.remoteId, 'obj-a');
    expect(stored.dirty, isTrue);
  });

  test('upsertClip không có keepRemoteId thì ghi đúng như model', () async {
    await source.upsertClip(clip('a', remoteId: 'obj-a', dirty: false));

    await source.upsertClip(clip('a', remoteId: 'obj-b', dirty: false));

    expect((await source.clipById('a'))!.remoteId, 'obj-b');
  });

  test('updateCopy chỉ đổi copied_at và copy_count', () async {
    await source.upsertClip(clip('a', remoteId: 'obj-a', dirty: false));
    final copied = at.add(const Duration(hours: 1));

    await source.updateCopy('a', copiedAt: copied, copyCount: 5);

    final stored = (await source.clipById('a'))!;
    expect(stored.copiedAt, copied);
    expect(stored.copyCount, 5);
    expect(stored.dirty, isFalse);
    expect(stored.remoteId, 'obj-a');
    expect(stored.updatedAt, at);
  });

  test('clipsByIds và deleteClips chia nhỏ danh sách id dài', () async {
    final raw = await db.raw;
    final batch = raw.batch();
    for (var i = 0; i < 1200; i++) {
      batch.insert('clips', clip('c$i').toMap());
    }
    await batch.commit(noResult: true);
    final ids = [for (var i = 0; i < 1100; i++) 'c$i', 'khong-co'];

    expect(await source.clipsByIds(ids), hasLength(1100));

    await source.deleteClips(ids);
    expect(await source.clips(), hasLength(100));
  });

  test('upsertGroup cập nhật tại chỗ, clip vẫn ở trong nhóm', () async {
    await source.upsertGroup(group('g1', remoteId: 'obj-g1'));
    await source.upsertClip(clip('a', groupId: 'g1'));

    await source.upsertGroup(group('g1', name: 'Đổi tên'), keepRemoteId: true);

    expect((await source.groupById('g1'))!.name, 'Đổi tên');
    expect((await source.groupById('g1'))!.remoteId, 'obj-g1');
    expect((await source.clipById('a'))!.groupId, 'g1');
  });

  test(
    'deleteGroup: clip còn trong nhóm mất liên kết qua khoá ngoại',
    () async {
      await source.upsertGroup(group('g1'));
      await source.upsertClip(clip('a', groupId: 'g1'));

      await source.deleteGroup('g1');

      expect(await source.groups(), isEmpty);
      expect((await source.clipById('a'))!.groupId, isNull);
    },
  );

  test('syncedIds và markSynced cho cả hai bảng', () async {
    await source.upsertClip(clip('a'));
    await source.upsertClip(clip('b', remoteId: 'obj-b', dirty: true));
    await source.upsertGroup(group('g1'));

    await source.markSynced(ClipLocalDataSource.clipsTable, 'a', 'obj-a');
    await source.markSynced(ClipLocalDataSource.groupsTable, 'g1', 'obj-g1');

    expect(await source.syncedIds(ClipLocalDataSource.clipsTable), {'a'});
    expect(await source.syncedIds(ClipLocalDataSource.groupsTable), {'g1'});
    expect((await source.dirtyClips()).map((c) => c.id), ['b']);
    expect(await source.dirtyGroups(), isEmpty);
  });

  test(
    'pending_deletes: lọc theo lớp, cũ trước, xếp lại thì dời giờ',
    () async {
      await source.queueDelete('obj-1', 'Clip', at);
      await source.queueDelete('obj-g', 'ClipGroup', at);
      await source.queueDelete(
        'obj-2',
        'Clip',
        at.add(const Duration(seconds: 1)),
      );
      await source.queueDelete(
        'obj-1',
        'Clip',
        at.add(const Duration(seconds: 2)),
      );

      expect(await source.pendingDeletes('Clip'), ['obj-2', 'obj-1']);
      expect(await source.pendingDeletes('ClipGroup'), ['obj-g']);

      await source.cancelDelete('obj-2');
      expect(await source.pendingDeletes('Clip'), ['obj-1']);
      expect((await (await db.raw).query('pending_deletes')).first.keys, [
        'remote_id',
        'class_name',
        'queued_at',
      ]);
    },
  );
}
