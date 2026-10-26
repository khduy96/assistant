import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';
import '../clip_db.dart';

/// The clipboard's two `SyncCollection`s over the real SQLite schema; the
/// same cases the GĐ4 collections were held to.
void main() {
  useFfiSqlite();

  late ClipDb db;
  late FakeClock clock;
  late ClipLocalDataSource source;
  late ClipboardRepositoryImpl repo;
  late ClipSyncCollection clips;
  late ClipGroupSyncCollection groups;

  setUp(() async {
    db = await ClipDb.open();
    clock = FakeClock(DateTime(2026, 10, 22, 9));
    source = ClipLocalDataSource(db.db);
    repo = ClipboardRepositoryImpl(source, clock);
    clips = ClipSyncCollection(repo, clock);
    groups = ClipGroupSyncCollection(repo, clock);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  ClipItem clip(
    String id, {
    String? content,
    bool isSaved = true,
    String? groupId,
    String? note,
  }) => ClipItem(
    id: id,
    content: content ?? 'nội dung $id',
    type: ClipItem.detectType(content ?? 'nội dung $id'),
    createdAt: clock.now(),
    updatedAt: clock.now(),
    isSaved: isSaved,
    groupId: groupId,
    note: note,
  );

  ClipGroup clipGroup(String id, {String name = 'Nhóm', int sortOrder = 0}) =>
      ClipGroup(
        id: id,
        name: name,
        color: 0xFF5B8DEF,
        createdAt: clock.now(),
        updatedAt: clock.now(),
        sortOrder: sortOrder,
      );

  Future<void> save(ClipItem item) async =>
      expect((await repo.saveClip(item)).isOk, isTrue);

  Future<void> saveGroup(ClipGroup group) async =>
      expect((await repo.saveGroup(group)).isOk, isTrue);

  test('tên lớp là Clip và ClipGroup', () {
    expect(clips.className, 'Clip');
    expect(groups.className, 'ClipGroup');
  });

  group('ClipSyncCollection', () {
    test('clip tạm không bao giờ vào dirtyRecords', () async {
      await repo.saveClip(clip('tam', isSaved: false), share: false);
      await save(clip('luu'));
      await save(clip('ghim', isSaved: false).copyWith(isPinned: true));

      final records = await clips.dirtyRecords();

      expect((await source.clipById('tam'))!.dirty, isTrue);
      expect(records.map((r) => r.localId).toSet(), {'luu', 'ghim'});
    });

    test('record mang field của Clip, không có space', () async {
      await save(clip('a', content: 'xin chào'));
      final record = (await clips.dirtyRecords()).single;

      expect(record.remoteId, isNull);
      expect(record.fields, {
        'localId': 'a',
        'content': 'xin chào',
        'kind': 'text',
        'clipCreatedAt': clock.now().millisecondsSinceEpoch,
        'clipUpdatedAt': clock.now().millisecondsSinceEpoch,
        'isSaved': true,
        'isPinned': false,
        'groupLocalId': null,
        'note': null,
        'copyCount': 0,
      });
    });

    test('syncedIds chỉ gồm clip đã có remoteId và không dirty', () async {
      await save(clip('a'));
      await save(clip('b'));
      await save(clip('c'));
      await clips.markSynced('a', 'obj-a');
      await clips.markSynced('b', 'obj-b');
      // b is edited again after its push.
      await save(clip('b', content: 'b sửa'));

      expect(await clips.syncedIds(), {'a'});
    });

    test('pendingDeletes chỉ lấy dòng chờ của lớp mình', () async {
      await source.queueDelete('obj-c', 'Clip', clock.now());
      await source.queueDelete('obj-g', 'ClipGroup', clock.now());

      expect(await clips.pendingDeletes(), ['obj-c']);
      expect(await groups.pendingDeletes(), ['obj-g']);

      await clips.clearPendingDelete('obj-c');
      expect(await clips.pendingDeletes(), isEmpty);
      expect(await groups.pendingDeletes(), ['obj-g']);
    });

    test('markSynced chỉ cập nhật remote_id và dirty', () async {
      await save(clip('a', content: 'bản đẩy đi'));
      // Edited while the push was in flight.
      await save(clip('a', content: 'sửa trong lúc đẩy', note: 'ghi chú'));

      await clips.markSynced('a', 'obj-1');

      final stored = (await source.clipById('a'))!;
      expect(stored.remoteId, 'obj-1');
      expect(stored.dirty, isFalse);
      expect(stored.content, 'sửa trong lúc đẩy');
      expect(stored.note, 'ghi chú');
    });

    test('markSynced với clip đã bị xoá thì không tạo lại', () async {
      await save(clip('a'));
      await repo.deleteClips(['a']);

      await clips.markSynced('a', 'obj-1');

      expect(await source.clips(), isEmpty);
    });

    Map<String, Object?> remote(
      String localId, {
      required DateTime updatedAt,
      String content = 'từ máy kia',
    }) => {
      'objectId': 'obj-$localId',
      'space': 'nha',
      'localId': localId,
      'content': content,
      'kind': 'text',
      'clipCreatedAt': updatedAt.millisecondsSinceEpoch,
      'clipUpdatedAt': updatedAt.millisecondsSinceEpoch,
      'isSaved': true,
      'isPinned': false,
      'copyCount': 0,
    };

    test('applyRemote giữ copiedAt của bản local', () async {
      await save(clip('a', content: 'bản cũ'));
      final copiedAt = clock.now().add(const Duration(minutes: 1));
      await repo.recordCopy(
        clip('a').copyWith(copiedAt: copiedAt, copyCount: 1),
      );
      await clips.markSynced('a', 'obj-a');

      final later = clock.now().add(const Duration(minutes: 5));
      final applied = await clips.applyRemote(
        remote('a', updatedAt: later, content: 'bản mới'),
      );

      expect(applied, isTrue);
      final stored = (await source.clipById('a'))!;
      expect(stored.content, 'bản mới');
      expect(stored.copiedAt, copiedAt);
      expect(stored.dirty, isFalse);
      expect(stored.remoteId, 'obj-a');
    });

    test('bản local có sửa chưa đẩy thì thắng', () async {
      await save(clip('a', content: 'chưa đẩy'));
      final later = clock.now().add(const Duration(minutes: 5));

      expect(await clips.applyRemote(remote('a', updatedAt: later)), isFalse);
      expect((await source.clipById('a'))!.content, 'chưa đẩy');
    });

    test('bản local mới hơn thì thắng', () async {
      await save(clip('a', content: 'mới hơn'));
      await clips.markSynced('a', 'obj-a');
      final earlier = clock.now().subtract(const Duration(minutes: 5));

      expect(await clips.applyRemote(remote('a', updatedAt: earlier)), isFalse);
      expect((await source.clipById('a'))!.content, 'mới hơn');
    });

    test('clip mới từ server được thêm, giờ thiếu thì lấy từ Clock', () async {
      final applied = await clips.applyRemote({
        'objectId': 'obj-x',
        'localId': 'x',
        'content': 'thiếu giờ',
        'isSaved': true,
      });

      expect(applied, isTrue);
      final stored = (await source.clipById('x'))!;
      expect(stored.createdAt, clock.now());
      expect(stored.updatedAt, clock.now());
      expect(stored.remoteId, 'obj-x');
      expect(await clips.syncedIds(), {'x'});
    });

    test('thiếu localId thì bỏ qua', () async {
      final json = remote('x', updatedAt: DateTime(2026, 10, 22))
        ..remove('localId');
      expect(await clips.applyRemote(json), isFalse);
      expect(await source.clips(), isEmpty);
    });

    test('removeLocalOnly xoá dòng mà không xếp lệnh xoá', () async {
      await save(clip('a'));
      await clips.markSynced('a', 'obj-1');

      await clips.removeLocalOnly('a');

      expect(await source.clips(), isEmpty);
      expect(await clips.pendingDeletes(), isEmpty);
    });
  });

  group('ClipGroupSyncCollection', () {
    test('dirtyRecords mang field của ClipGroup, không có space', () async {
      await saveGroup(clipGroup('g1', name: 'Công việc', sortOrder: 2));
      final record = (await groups.dirtyRecords()).single;

      expect(record.localId, 'g1');
      expect(record.remoteId, isNull);
      expect(record.fields, {
        'localId': 'g1',
        'name': 'Công việc',
        'color': 0xFF5B8DEF,
        'groupCreatedAt': clock.now().millisecondsSinceEpoch,
        'groupUpdatedAt': clock.now().millisecondsSinceEpoch,
        'sortOrder': 2,
      });
    });

    test('markSynced nhóm không làm clip rơi khỏi nhóm', () async {
      await saveGroup(clipGroup('g1'));
      await save(clip('a', groupId: 'g1'));

      await groups.markSynced('g1', 'obj-g');

      final stored = (await source.groupById('g1'))!;
      expect(stored.remoteId, 'obj-g');
      expect(stored.dirty, isFalse);
      expect((await source.clipById('a'))!.groupId, 'g1');
    });

    test('applyRemote cập nhật nhóm có sẵn mà clip vẫn trong nhóm', () async {
      await saveGroup(clipGroup('g1', name: 'Cũ'));
      await save(clip('a', groupId: 'g1'));
      await groups.markSynced('g1', 'obj-g');
      final later = clock.now().add(const Duration(minutes: 1));

      final applied = await groups.applyRemote({
        'objectId': 'obj-g',
        'localId': 'g1',
        'name': 'Mới',
        'color': 0xFF00B894,
        'groupCreatedAt': clock.now().millisecondsSinceEpoch,
        'groupUpdatedAt': later.millisecondsSinceEpoch,
        'sortOrder': 0,
      });

      expect(applied, isTrue);
      expect((await source.groupById('g1'))!.name, 'Mới');
      expect((await source.clipById('a'))!.groupId, 'g1');
    });

    test('bản local có sửa chưa đẩy hoặc mới hơn thì thắng', () async {
      await saveGroup(clipGroup('g1', name: 'Chưa đẩy'));
      final json = {
        'objectId': 'obj-g',
        'localId': 'g1',
        'name': 'Từ máy kia',
        'groupUpdatedAt': clock
            .now()
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      };
      expect(await groups.applyRemote(json), isFalse);

      await groups.markSynced('g1', 'obj-g');
      json['groupUpdatedAt'] = clock
          .now()
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(await groups.applyRemote(json), isFalse);
      expect((await source.groupById('g1'))!.name, 'Chưa đẩy');

      expect(await groups.applyRemote({'name': 'x'}), isFalse);
    });

    test('syncedIds chỉ gồm nhóm đã đẩy và không dirty', () async {
      await saveGroup(clipGroup('a'));
      await saveGroup(clipGroup('b', sortOrder: 1));
      await groups.markSynced('a', 'obj-a');

      expect(await groups.syncedIds(), {'a'});

      await groups.removeLocalOnly('a');
      expect(await groups.syncedIds(), isEmpty);
      expect(await groups.pendingDeletes(), isEmpty);
    });
  });

  group('localChanges', () {
    test('clip tạm mới và lần copy không cần đẩy; copy lại clip đã lưu thì '
        'cần', () async {
      var clipPushes = 0;
      final sub = clips.localChanges.listen((_) => clipPushes++);
      addTearDown(sub.cancel);

      await repo.saveClip(clip('tam', isSaved: false), share: false);
      await repo.recordCopy(clip('tam', isSaved: false));
      await Future<void>.delayed(Duration.zero);
      expect(clipPushes, 0);

      await save(clip('luu'));
      await Future<void>.delayed(Duration.zero);
      expect(clipPushes, 1);
    });

    test('nhóm chỉ báo qua localChanges của ClipGroupSyncCollection', () async {
      var clipPushes = 0;
      var groupPushes = 0;
      final subs = [
        clips.localChanges.listen((_) => clipPushes++),
        groups.localChanges.listen((_) => groupPushes++),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });

      await saveGroup(clipGroup('g1'));
      await repo.deleteGroup('g1');
      await Future<void>.delayed(Duration.zero);

      expect(groupPushes, 2);
      expect(clipPushes, 0);
    });
  });

  test('mọi clip trả về từ dirtyRecords đọc lại được bằng ClipModel', () async {
    await save(clip('a', content: 'https://example.com'));
    final record = (await clips.dirtyRecords()).single;
    final back = ClipModel.fromParse(record.fields, now: clock.now());

    expect(back.type, ClipType.link);
    expect(back.content, 'https://example.com');
    expect(await repo.getClips(), isA<Ok<List<ClipItem>>>());
  });
}
