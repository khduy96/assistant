import 'dart:async';
import 'dart:io';

import 'package:event_notice/features/notes/data/datasources/note_local_data_source.dart';
import 'package:event_notice/features/notes/data/models/note_model.dart';
import 'package:event_notice/features/notes/data/repositories/note_repository_impl.dart';
import 'package:event_notice/features/notes/data/sync/note_sync_collection.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

/// A `NoteItem` object as Back4App returns it.
Map<String, Object?> _remote(
  String localId, {
  String objectId = 'obj-r',
  String body = 'từ máy khác',
  DateTime? updatedAt,
}) => {
  'objectId': objectId,
  'localId': localId,
  'title': '',
  'body': body,
  'pinned': false,
  'markdown': false,
  'color': 'none',
  'noteCreatedAt': _t0.millisecondsSinceEpoch,
  'noteUpdatedAt': (updatedAt ?? _t0).millisecondsSinceEpoch,
  'space': 'nha',
};

void main() {
  late Directory dir;
  late FakeClock clock;
  late NoteRepositoryImpl repo;
  late NoteSyncCollection collection;
  late StreamSubscription<void> sub;
  late int localChanges;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('note_sync_test');
    clock = FakeClock(_min(60));
    repo = NoteRepositoryImpl(
      NoteLocalDataSource(clock, path: '${dir.path}/notes.json'),
    );
    collection = NoteSyncCollection(repo, clock);
    await repo.init();
    localChanges = 0;
    sub = collection.localChanges.listen((_) => localChanges++);
  });

  tearDown(() async {
    await sub.cancel();
    await repo.dispose();
    await dir.delete(recursive: true);
  });

  /// Saves [id] as the user would, then as already pushed when [remoteId] is
  /// given.
  Future<void> local(
    String id, {
    String body = 'ở máy này',
    DateTime? updatedAt,
    String? remoteId,
  }) async {
    final at = updatedAt ?? _t0;
    await repo.save(Note(id: id, body: body, createdAt: _t0, updatedAt: at));
    if (remoteId != null) await collection.markSynced(id, remoteId);
  }

  NoteModel? model(String id) =>
      repo.models.where((n) => n.id == id).firstOrNull;

  /// Waits for queued events, then reports how many local changes fired since
  /// the last call.
  Future<int> takeLocalChanges() async {
    await Future<void>.delayed(Duration.zero);
    final n = localChanges;
    localChanges = 0;
    return n;
  }

  test('className là NoteItem', () {
    expect(collection.className, 'NoteItem');
  });

  group('đẩy', () {
    test(
      'dirtyRecords chỉ gồm ghi chú dirty, với đúng field của NoteItem',
      () async {
        await local('a', remoteId: 'obj-a');
        await local('b', body: 'mới');

        final record = (await collection.dirtyRecords()).single;
        expect(record.localId, 'b');
        expect(record.remoteId, isNull);
        expect(record.fields, {
          'localId': 'b',
          'title': '',
          'body': 'mới',
          'pinned': false,
          'markdown': false,
          'color': 'none',
          'noteCreatedAt': _t0.millisecondsSinceEpoch,
          'noteUpdatedAt': _t0.millisecondsSinceEpoch,
        });
      },
    );

    test('sửa ghi chú đã đẩy thì record mang remoteId cũ', () async {
      await local('a', remoteId: 'obj-a');
      await local('a', body: 'đã sửa');
      final record = (await collection.dirtyRecords()).single;
      expect(record.remoteId, 'obj-a');
      expect(record.fields['body'], 'đã sửa');
    });

    test(
      'markSynced ghi remoteId, xoá dirty, không bắn localChanges',
      () async {
        await local('a');
        // The user's own save is what schedules the push.
        expect(await takeLocalChanges(), 1);

        await collection.markSynced('a', 'obj-a');
        expect(model('a')!.remoteId, 'obj-a');
        expect(model('a')!.dirty, isFalse);
        expect(await collection.dirtyRecords(), isEmpty);
        expect(await takeLocalChanges(), 0);
      },
    );

    test('markSynced với id không có thì bỏ qua', () async {
      await collection.markSynced('không-có', 'obj-x');
      expect(repo.models, isEmpty);
    });

    test(
      'syncedIds gồm mọi ghi chú đã có remoteId, kể cả đang dirty',
      () async {
        await local('a', remoteId: 'obj-a');
        await local('b', remoteId: 'obj-b');
        await local('b', body: 'sửa sau khi đẩy');
        await local('c');
        expect(await collection.syncedIds(), {'a', 'b'});
      },
    );

    test(
      'pendingDeletes trả remoteId của tombstone, clearPendingDelete xoá theo remoteId',
      () async {
        await local('a', remoteId: 'obj-a');
        await repo.delete('a');
        await takeLocalChanges();

        expect(await collection.pendingDeletes(), ['obj-a']);

        await collection.clearPendingDelete('obj-a');
        expect(await collection.pendingDeletes(), isEmpty);
        expect(await takeLocalChanges(), 0);
      },
    );
  });

  group('applyRemote', () {
    test(
      'ghi chú mới từ server được thêm vào, sạch, không bắn localChanges',
      () async {
        expect(await collection.applyRemote(_remote('r1')), isTrue);

        final m = model('r1')!;
        expect(m.body, 'từ máy khác');
        expect(m.remoteId, 'obj-r');
        expect(m.dirty, isFalse);
        expect(await collection.dirtyRecords(), isEmpty);
        expect(await takeLocalChanges(), 0);
      },
    );

    test('thiếu localId thì bỏ qua', () async {
      final json = _remote('r1')..remove('localId');
      expect(await collection.applyRemote(json), isFalse);
      expect(repo.models, isEmpty);
    });

    test('bản local có sửa chưa đẩy thì thắng', () async {
      await local('a', remoteId: 'obj-a');
      await local('a', body: 'sửa chưa đẩy');

      final applied = await collection.applyRemote(
        _remote('a', objectId: 'obj-a', updatedAt: _min(30)),
      );
      expect(applied, isFalse);
      expect(model('a')!.body, 'sửa chưa đẩy');
      expect(model('a')!.dirty, isTrue);
    });

    test('bản local có updatedAt mới hơn thì thắng', () async {
      await local('a', updatedAt: _min(10), remoteId: 'obj-a');

      final applied = await collection.applyRemote(
        _remote('a', objectId: 'obj-a', updatedAt: _min(5)),
      );
      expect(applied, isFalse);
      expect(model('a')!.body, 'ở máy này');
    });

    test('bản server mới hơn thì thay bản local đã sạch', () async {
      await local('a', updatedAt: _min(5), remoteId: 'obj-a');
      await takeLocalChanges();

      final applied = await collection.applyRemote(
        _remote('a', objectId: 'obj-a', updatedAt: _min(10)),
      );
      expect(applied, isTrue);
      expect(model('a')!.body, 'từ máy khác');
      expect(model('a')!.updatedAt, _min(10));
      expect(model('a')!.dirty, isFalse);
      expect(repo.models, hasLength(1));
      expect(await takeLocalChanges(), 0);
    });

    test('cùng updatedAt thì lấy bản server', () async {
      await local('a', updatedAt: _min(5), remoteId: 'obj-a');
      final applied = await collection.applyRemote(
        _remote('a', objectId: 'obj-a', updatedAt: _min(5)),
      );
      expect(applied, isTrue);
      expect(model('a')!.body, 'từ máy khác');
    });

    test(
      'ghi chú đã xoá local mà tombstone còn chờ thì không kéo về lại',
      () async {
        await local('a', remoteId: 'obj-a');
        await repo.delete('a');

        final applied = await collection.applyRemote(
          _remote('a', objectId: 'obj-a', updatedAt: _min(30)),
        );
        expect(applied, isFalse);
        expect(repo.models, isEmpty);
        expect((await collection.pendingDeletes()).single, 'obj-a');
      },
    );

    test('thiếu mốc thời gian thì lấy giờ của Clock', () async {
      final json = _remote('r1')
        ..remove('noteCreatedAt')
        ..remove('noteUpdatedAt');
      await collection.applyRemote(json);
      expect(model('r1')!.createdAt, _min(60));
      expect(model('r1')!.updatedAt, _min(60));
    });

    test('bản áp vào được ghi xuống file', () async {
      await collection.applyRemote(_remote('r1'));
      final reopened = NoteRepositoryImpl(
        NoteLocalDataSource(clock, path: '${dir.path}/notes.json'),
      );
      await reopened.init();
      expect(reopened.models.single.remoteId, 'obj-r');
      expect(reopened.models.single.dirty, isFalse);
      await reopened.dispose();
    });
  });

  group('removeLocalOnly', () {
    test(
      'ghi chú đã xoá trên server thì xoá local mà không tạo tombstone',
      () async {
        await local('a', remoteId: 'obj-a');
        await takeLocalChanges();

        await collection.removeLocalOnly('a');
        expect(repo.models, isEmpty);
        expect(await collection.pendingDeletes(), isEmpty);
        expect(await takeLocalChanges(), 0);
      },
    );
  });

  group('khoá theo remoteId và chờ nạp file', () {
    test('clearPendingDelete với localId thì không xoá tombstone nào', () async {
      await local('a', remoteId: 'obj-a');
      await repo.delete('a');

      await collection.clearPendingDelete('a');
      expect(await collection.pendingDeletes(), ['obj-a']);
    });

    test('đọc khi repository chưa nạp thì chờ nạp xong', () async {
      await local('a', remoteId: 'obj-a');
      await local('b');
      await repo.delete('a');

      final reopened = NoteRepositoryImpl(
        NoteLocalDataSource(clock, path: '${dir.path}/notes.json'),
      );
      addTearDown(reopened.dispose);
      final fresh = NoteSyncCollection(reopened, clock);

      expect((await fresh.dirtyRecords()).single.localId, 'b');
      expect(await fresh.pendingDeletes(), ['obj-a']);
      expect(await fresh.syncedIds(), isEmpty);
    });
  });
}
