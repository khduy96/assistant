import 'dart:async';

import 'package:event_notice/core/data/app_database.dart';
import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clip.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';
import '../clip_db.dart';

void main() {
  useFfiSqlite();

  late ClipDb db;
  late FakeClock clock;
  late ClipLocalDataSource source;
  late ClipboardRepositoryImpl repo;
  late ClipSyncCollection clipSync;
  late ClipGroupSyncCollection groupSync;

  late int remote;
  late int clipPushes;
  late int groupPushes;
  late List<StreamSubscription<void>> subs;

  setUp(() async {
    db = await ClipDb.open();
    clock = FakeClock(DateTime(2026, 10, 22, 9));
    source = ClipLocalDataSource(db.db);
    repo = ClipboardRepositoryImpl(source, clock);
    clipSync = ClipSyncCollection(repo, clock);
    groupSync = ClipGroupSyncCollection(repo, clock);
    remote = 0;
    clipPushes = 0;
    groupPushes = 0;
    subs = [
      repo.remoteChanges.listen((_) => remote++),
      repo.localClipChanges.listen((_) => clipPushes++),
      repo.localGroupChanges.listen((_) => groupPushes++),
    ];
  });

  tearDown(() async {
    for (final sub in subs) {
      await sub.cancel();
    }
    await repo.dispose();
    await db.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  T ok<T>(Result<T> result) => switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => fail('$failure'),
  };

  ClipItem clip(
    String id, {
    String? content,
    bool isSaved = true,
    String? groupId,
  }) => ClipItem(
    id: id,
    content: content ?? 'nội dung $id',
    type: ClipType.text,
    createdAt: clock.now(),
    updatedAt: clock.now(),
    isSaved: isSaved,
    groupId: groupId,
  );

  ClipGroup clipGroup(String id, {String name = 'Nhóm'}) => ClipGroup(
    id: id,
    name: name,
    color: 0xFF5B8DEF,
    createdAt: clock.now(),
    updatedAt: clock.now(),
  );

  /// Saves [item] and pretends a push reached the server.
  Future<void> pushed(ClipItem item) async {
    ok(await repo.saveClip(item));
    await repo.markClipSynced(item.id, 'obj-${item.id}');
  }

  Future<List<String>> pendingClipDeletes() => clipSync.pendingDeletes();

  group('đọc', () {
    test('getClips trả entity; findClipByContent so khớp nguyên văn', () async {
      ok(await repo.saveClip(clip('a')));
      ok(await repo.saveClip(clip('b', content: 'B')));

      expect(ok(await repo.getClips()).map((c) => c.id).toSet(), {'a', 'b'});
      expect(ok(await repo.findClipByContent('B'))!.id, 'b');
      expect(ok(await repo.findClipByContent('b')), isNull);
    });

    test('lỗi IO trả về StorageFailure, không ném', () async {
      // A folder where the database file should be: it cannot be opened.
      final broken = ClipboardRepositoryImpl(
        ClipLocalDataSource(AppDatabase.atPath(db.dir.path)),
        clock,
      );
      addTearDown(broken.dispose);

      final result = await broken.getClips();

      expect(result.failureOrNull, isA<StorageFailure>());
      expect((await broken.saveClip(clip('a'))).isErr, isTrue);
    });
  });

  group('saveClip', () {
    test('thêm mới: dirty, chưa có remoteId, xin đẩy', () async {
      ok(await repo.saveClip(clip('a')));
      await settle();

      final record = (await clipSync.dirtyRecords()).single;
      expect(record.localId, 'a');
      expect(record.remoteId, isNull);
      expect(clipPushes, 1);
      expect(remote, 0);
    });

    test('share: false vẫn đánh dấu dirty nhưng không xin đẩy', () async {
      ok(await repo.saveClip(clip('t', isSaved: false), share: false));
      await settle();

      expect((await source.clipById('t'))!.dirty, isTrue);
      expect(clipPushes, 0);
    });

    test('sửa clip đã đẩy: giữ remoteId để lần đẩy sau cập nhật', () async {
      await pushed(clip('a'));

      ok(await repo.saveClip(clip('a', content: 'đã sửa')));

      final record = (await clipSync.dirtyRecords()).single;
      expect(record.remoteId, 'obj-a');
      expect(record.fields['content'], 'đã sửa');
    });
  });

  test('recordCopy chỉ ghi copiedAt và copyCount, không dirty, không xin '
      'đẩy', () async {
    await pushed(clip('a'));
    await settle();
    clipPushes = 0;
    final copiedAt = clock.now().add(const Duration(hours: 1));

    ok(
      await repo.recordCopy(
        clip(
          'a',
          content: 'không được ghi',
        ).copyWith(copiedAt: copiedAt, copyCount: 3),
      ),
    );
    ok(await repo.recordCopy(clip('khong-co')));
    await settle();

    final stored = (await source.clipById('a'))!;
    expect(stored.copiedAt, copiedAt);
    expect(stored.copyCount, 3);
    expect(stored.content, 'nội dung a');
    expect(stored.dirty, isFalse);
    expect(clipPushes, 0);
  });

  group('detachFromServer', () {
    test('clip đã đẩy: xếp lệnh xoá trên server, quên remoteId', () async {
      await pushed(clip('a'));
      await settle();
      clipPushes = 0;

      ok(await repo.detachFromServer('a'));
      await settle();

      expect(await pendingClipDeletes(), ['obj-a']);
      expect((await source.clipById('a'))!.remoteId, isNull);
      expect(clipPushes, 0);
    });

    test('clip chưa đẩy hoặc id lạ thì không làm gì', () async {
      ok(await repo.saveClip(clip('a')));

      ok(await repo.detachFromServer('a'));
      ok(await repo.detachFromServer('khong-co'));

      expect(await pendingClipDeletes(), isEmpty);
    });

    test('qua UnsaveClip: clip thành clip tạm, không còn được đẩy, server '
        'object chờ xoá', () async {
      await pushed(clip('a', groupId: null).copyWith(isPinned: true));
      clock.current = clock.current.add(const Duration(hours: 2));

      final unsaved = ok(await UnsaveClip(repo, clock)(clip('a')));

      final stored = (await source.clipById('a'))!;
      expect(stored.isTemp, isTrue);
      expect(stored.remoteId, isNull);
      expect(stored.dirty, isTrue);
      expect(stored.createdAt, clock.now());
      expect(unsaved.isTemp, isTrue);
      expect(await clipSync.dirtyRecords(), isEmpty);
      expect(await pendingClipDeletes(), ['obj-a']);
    });
  });

  group('deleteClips và restoreClip', () {
    test(
      'xoá: dòng mất, chỉ clip đã đẩy mới xếp lệnh xoá, id lạ bỏ qua',
      () async {
        await pushed(clip('a'));
        ok(await repo.saveClip(clip('b')));
        await settle();
        clipPushes = 0;

        ok(await repo.deleteClips(['a', 'b', 'khong-co']));
        await settle();

        expect(ok(await repo.getClips()), isEmpty);
        expect(await pendingClipDeletes(), ['obj-a']);
        expect(clipPushes, 1);
      },
    );

    test('share: false thì không xin đẩy', () async {
      ok(await repo.saveClip(clip('t', isSaved: false), share: false));

      ok(await repo.deleteClips(['t'], share: false));
      await settle();

      expect(clipPushes, 0);
      expect(remote, 0);
    });

    test('hoàn tác: gắn lại remoteId, huỷ lệnh xoá đang chờ, dirty', () async {
      await pushed(clip('a'));
      final original = ok(await repo.getClips()).single;
      ok(await repo.deleteClips(['a']));
      await settle();
      clipPushes = 0;

      ok(await repo.restoreClip(original));
      await settle();

      expect(ok(await repo.getClips()).single, original);
      expect(await pendingClipDeletes(), isEmpty);
      final record = (await clipSync.dirtyRecords()).single;
      expect(record.remoteId, 'obj-a');
      expect(clipPushes, 1);
    });

    test('hoàn tác clip chưa từng đẩy thì vẫn chưa có remoteId', () async {
      ok(await repo.saveClip(clip('a')));
      final original = ok(await repo.getClips()).single;
      ok(await repo.deleteClips(['a']));

      ok(await repo.restoreClip(original));

      expect((await source.clipById('a'))!.remoteId, isNull);
      expect(await pendingClipDeletes(), isEmpty);
    });

    test('lệnh xoá của clip khác vẫn còn khi hoàn tác một clip', () async {
      await pushed(clip('a'));
      await pushed(clip('b'));
      final a = (ok(await repo.getClips())).firstWhere((c) => c.id == 'a');
      ok(await repo.deleteClips(['a', 'b']));

      ok(await repo.restoreClip(a));

      expect(await pendingClipDeletes(), ['obj-b']);
    });
  });

  group('nhóm', () {
    test('saveGroup thêm rồi sửa: giữ remoteId, clip vẫn trong nhóm, xin đẩy '
        'nhóm', () async {
      ok(await repo.saveGroup(clipGroup('g1')));
      await repo.markGroupSynced('g1', 'obj-g1');
      ok(await repo.saveClip(clip('a', groupId: 'g1')));

      ok(await repo.saveGroup(clipGroup('g1', name: 'Đổi tên')));
      await settle();

      expect(ok(await repo.getGroups()).single.name, 'Đổi tên');
      final record = (await groupSync.dirtyRecords()).single;
      expect(record.remoteId, 'obj-g1');
      expect((await source.clipById('a'))!.groupId, 'g1');
      expect(groupPushes, 2);
    });

    test('getGroups theo sortOrder rồi tên', () async {
      ok(
        await repo.saveGroup(clipGroup('g1', name: 'B').copyWith(sortOrder: 1)),
      );
      ok(await repo.saveGroup(clipGroup('g2', name: 'C')));
      ok(
        await repo.saveGroup(clipGroup('g3', name: 'A').copyWith(sortOrder: 1)),
      );

      expect(ok(await repo.getGroups()).map((g) => g.id), ['g2', 'g3', 'g1']);
    });

    test('deleteGroup: xếp lệnh xoá nếu đã đẩy; id lạ không làm gì', () async {
      ok(await repo.saveGroup(clipGroup('g1')));
      await repo.markGroupSynced('g1', 'obj-g1');
      await settle();
      groupPushes = 0;

      ok(await repo.deleteGroup('g1'));
      ok(await repo.deleteGroup('khong-co'));
      await settle();

      expect(ok(await repo.getGroups()), isEmpty);
      expect(await groupSync.pendingDeletes(), ['obj-g1']);
      expect(await pendingClipDeletes(), isEmpty);
      expect(groupPushes, 1);
    });

    test(
      'qua DeleteClipGroup: clip của nhóm vẫn lưu, mất nhóm và dirty',
      () async {
        ok(await repo.saveGroup(clipGroup('g1')));
        await repo.markGroupSynced('g1', 'obj-g1');
        await pushed(clip('a', groupId: 'g1'));
        await pushed(clip('b'));
        clock.current = clock.current.add(const Duration(minutes: 5));

        final ungrouped = ok(
          await DeleteClipGroup(repo, clock)(clipGroup('g1')),
        );

        expect(ungrouped.map((c) => c.id), ['a']);
        final a = (await source.clipById('a'))!;
        expect(a.isSaved, isTrue);
        expect(a.groupId, isNull);
        expect(a.dirty, isTrue);
        expect(a.remoteId, 'obj-a');
        expect(a.updatedAt, clock.now());
        expect((await source.clipById('b'))!.dirty, isFalse);
        expect(await groupSync.pendingDeletes(), ['obj-g1']);
      },
    );
  });

  test('ghi do sync chỉ bắn remoteChanges, không xin đẩy', () async {
    ok(await repo.saveClip(clip('a')));
    ok(await repo.saveGroup(clipGroup('g1')));
    await settle();
    clipPushes = 0;
    groupPushes = 0;

    await clipSync.markSynced('a', 'obj-a');
    await groupSync.markSynced('g1', 'obj-g1');
    await clipSync.applyRemote({
      'objectId': 'obj-b',
      'localId': 'b',
      'content': 'từ máy kia',
      'clipCreatedAt': 1,
      'clipUpdatedAt': 1,
      'isSaved': true,
    });
    await groupSync.applyRemote({'objectId': 'obj-g2', 'localId': 'g2'});
    await clipSync.removeLocalOnly('b');
    await groupSync.removeLocalOnly('g2');
    await settle();

    expect(remote, 6);
    expect(clipPushes, 0);
    expect(groupPushes, 0);
  });

  test('ghi của người dùng không bắn remoteChanges', () async {
    ok(await repo.saveClip(clip('a')));
    ok(await repo.recordCopy(clip('a')));
    ok(await repo.detachFromServer('a'));
    ok(await repo.deleteClips(['a']));
    ok(await repo.restoreClip(clip('a')));
    ok(await repo.saveGroup(clipGroup('g1')));
    ok(await repo.deleteGroup('g1'));
    await settle();

    expect(remote, 0);
  });

  test('sau dispose thì không bắn sự kiện nữa và không lỗi', () async {
    final other = ClipboardRepositoryImpl(source, clock);
    await other.dispose();

    expect((await other.saveClip(clip('a'))).isOk, isTrue);
    await other.markClipSynced('a', 'obj-a');
  });
}
