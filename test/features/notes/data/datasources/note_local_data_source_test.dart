import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/data/app_paths.dart';
import 'package:event_notice/core/data/json_file_store.dart';
import 'package:event_notice/core/sync/domain/sync_collection.dart';
import 'package:event_notice/features/notes/data/datasources/note_local_data_source.dart';
import 'package:event_notice/features/notes/data/models/note_model.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

const _fixtures = 'test/features/notes/data/fixtures';

final _now = DateTime(2026, 10, 22, 8);

/// Puts the app's files in a test directory instead of the real one.
class _TempPaths extends AppPaths {
  const _TempPaths(this.dir);

  final String dir;

  @override
  Future<String> supportFile(String fileName) async => '$dir/$fileName';
}

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('note_data_test');
    path = '${dir.path}/notes.json';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Copies a fixture to the test file, so the original is never written.
  Future<void> useFixture(String name) => File('$_fixtures/$name').copy(path);

  NoteLocalDataSource source() =>
      NoteLocalDataSource(FakeClock(_now), path: path);

  group('JsonFileStore', () {
    test('không có file thì rỗng', () async {
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.items, isEmpty);
      expect(saved.deleted, isEmpty);
    });

    test('đọc bare list', () async {
      await useFixture('notes_bare_list.json');
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.items.map((e) => e['id']), ['old-1', 'old-2', 'old-3']);
      expect(saved.deleted, isEmpty);
    });

    test('đọc dạng {items, deleted}', () async {
      await useFixture('notes_items_deleted.json');
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.items.map((e) => e['id']), ['n1', 'n2']);
      expect(saved.deleted.single.localId, 'gone-1');
      expect(saved.deleted.single.remoteId, 'obj-gone-1');
    });

    test('file hỏng thì rỗng', () async {
      await useFixture('notes_corrupt.json');
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.items, isEmpty);
      expect(saved.deleted, isEmpty);
    });

    test('items không phải list thì coi là file hỏng', () async {
      await File(path).writeAsString('{"items": 3, "deleted": []}');
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.items, isEmpty);
    });

    test('bỏ tombstone thiếu remoteId', () async {
      await File(path).writeAsString(
        jsonEncode({
          'items': [],
          'deleted': [
            {'id': 'a'},
            {'id': 'b', 'remoteId': 'obj-b'},
          ],
        }),
      );
      final saved = await JsonFileStore('x.json', path: path).load();
      expect(saved.deleted.single.localId, 'b');
    });

    test('ghi ra {items, deleted}, thụt lề hai dấu cách', () async {
      await JsonFileStore('x.json', path: path).save(
        [
          {'id': 'a'},
        ],
        [const SyncTombstone(localId: 'b', remoteId: 'obj-b')],
      );
      expect(
        await File(path).readAsString(),
        '{\n'
        '  "items": [\n'
        '    {\n'
        '      "id": "a"\n'
        '    }\n'
        '  ],\n'
        '  "deleted": [\n'
        '    {\n'
        '      "id": "b",\n'
        '      "remoteId": "obj-b"\n'
        '    }\n'
        '  ]\n'
        '}',
      );
    });

    test('hai lần ghi liền nhau thì bản sau thắng', () async {
      final store = JsonFileStore('x.json', path: path);
      await Future.wait([
        store.save([
          {'id': 'first'},
        ], const []),
        store.save([
          {'id': 'second'},
        ], const []),
      ]);
      final saved = await store.load();
      expect(saved.items.single['id'], 'second');
    });

    test(
      'không truyền path thì nằm trong thư mục support theo tên file',
      () async {
        final store = JsonFileStore('notes.json', paths: _TempPaths(dir.path));
        await store.save(const [], const []);
        expect(await File('${dir.path}/notes.json').exists(), isTrue);
      },
    );
  });

  group('NoteLocalDataSource', () {
    test('tên file là notes.json', () async {
      final source = NoteLocalDataSource(
        FakeClock(_now),
        paths: _TempPaths(dir.path),
      );
      await source.save(const [], const []);
      expect(await File('${dir.path}/notes.json').exists(), isTrue);
    });

    test('bare list cũ không mất ghi chú nào', () async {
      await useFixture('notes_bare_list.json');
      final saved = await source().load();

      expect(saved.items.map((n) => n.id), ['old-1', 'old-2', 'old-3']);
      expect(saved.deleted, isEmpty);

      final [a, b, c] = saved.items;
      expect(a.title, 'Wifi');
      expect(a.body, '12345678');
      expect(a.pinned, isTrue);
      expect(a.color, NoteColor.yellow);
      expect(a.createdAt, DateTime(2026, 1, 2, 8));
      expect(a.updatedAt, DateTime(2026, 1, 3, 9, 30));
      // Trước khi có sync và Markdown: chưa đẩy, văn bản thường.
      for (final n in saved.items) {
        expect(n.markdown, isFalse);
        expect(n.dirty, isTrue);
        expect(n.remoteId, isNull);
      }
      expect(b.color, NoteColor.none);
      expect(b.updatedAt, DateTime(2026, 1, 4, 10));
      expect(c.title, '');
      expect(c.createdAt, _now);
      expect(c.updatedAt, _now);
    });

    test('dạng {items, deleted} giữ cả ghi chú lẫn tombstone', () async {
      await useFixture('notes_items_deleted.json');
      final saved = await source().load();

      final [n1, n2] = saved.items;
      expect(n1.id, 'n1');
      expect(n1.markdown, isTrue);
      expect(n1.color, NoteColor.blue);
      expect(n1.remoteId, 'obj-n1');
      expect(n1.dirty, isFalse);
      expect(n1.updatedAt, DateTime(2026, 10, 20, 17, 45, 30, 500));
      expect(n2.remoteId, isNull);
      expect(n2.dirty, isTrue);
      expect(saved.deleted.single.localId, 'gone-1');
      expect(saved.deleted.single.remoteId, 'obj-gone-1');
    });

    test('file hỏng thì rỗng', () async {
      await useFixture('notes_corrupt.json');
      final saved = await source().load();
      expect(saved.items, isEmpty);
      expect(saved.deleted, isEmpty);
    });

    test(
      'một ghi chú không đọc được thì cả file coi là hỏng, như bản cũ',
      () async {
        await File(path).writeAsString(
          jsonEncode([
            {'id': 'ok'},
            {'title': 'thiếu id'},
          ]),
        );
        final saved = await source().load();
        expect(saved.items, isEmpty);
      },
    );

    test('round-trip giữ nguyên mọi khoá của ghi chú và tombstone', () async {
      await useFixture('notes_items_deleted.json');
      final original = jsonDecode(await File(path).readAsString()) as Map;

      final saved = await source().load();
      final copy = '${dir.path}/copy.json';
      await NoteLocalDataSource(
        FakeClock(_now),
        path: copy,
      ).save(saved.items, saved.deleted);

      final written = jsonDecode(await File(copy).readAsString()) as Map;
      expect(written.keys, ['items', 'deleted']);
      for (final item in written['items'] as List) {
        expect((item as Map).keys, [
          'id',
          'title',
          'body',
          'pinned',
          'markdown',
          'color',
          'createdAt',
          'updatedAt',
          'remoteId',
          'dirty',
        ]);
      }
      expect(written, original);
    });

    test('bare list ghi lại thành {items, deleted} đủ khoá', () async {
      await useFixture('notes_bare_list.json');
      final saved = await source().load();
      await source().save(saved.items, saved.deleted);

      final written = jsonDecode(await File(path).readAsString()) as Map;
      expect(written['deleted'], isEmpty);
      final items = (written['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((e) => e['id']), ['old-1', 'old-2', 'old-3']);
      expect(items.first, {
        'id': 'old-1',
        'title': 'Wifi',
        'body': '12345678',
        'pinned': true,
        'markdown': false,
        'color': 'yellow',
        'createdAt': '2026-01-02T08:00:00.000',
        'updatedAt': '2026-01-03T09:30:00.000',
        'remoteId': null,
        'dirty': true,
      });
    });

    test('ghi xong đọc lại được đúng như trước', () async {
      final note = NoteModel(
        id: 'n1',
        title: 'Wifi',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 2),
        remoteId: 'obj-1',
        dirty: false,
      );
      await source().save(
        [note],
        [const SyncTombstone(localId: 'x', remoteId: 'obj-x')],
      );
      final saved = await source().load();
      expect(saved.items.single.toJson(), note.toJson());
      expect(saved.deleted.single.toJson(), {'id': 'x', 'remoteId': 'obj-x'});
    });
  });
}
