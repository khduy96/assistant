import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../clip_db.dart';

void main() {
  useFfiSqlite();

  late ClipDb db;

  setUp(() async => db = await ClipDb.open());
  tearDown(() => db.close());

  final created = DateTime(2026, 10, 20, 8, 30);
  final updated = DateTime(2026, 10, 21, 9, 15);
  final copied = DateTime(2026, 10, 22, 7);

  ClipModel full() => ClipModel(
    id: 'mgx3k2a1-1x2y3z',
    content: 'https://example.com',
    type: ClipType.link,
    createdAt: created,
    updatedAt: updated,
    copiedAt: copied,
    isSaved: true,
    isPinned: true,
    groupId: null,
    note: 'trang chủ',
    copyCount: 4,
    remoteId: 'obj-1',
    dirty: false,
  );

  group('SQLite', () {
    test('round-trip qua bảng clips giữ nguyên mọi cột', () async {
      final raw = await db.raw;
      final model = full();
      await raw.insert('clips', model.toMap());

      final row = (await raw.query('clips')).single;

      expect(row['id'], 'mgx3k2a1-1x2y3z');
      expect(row['content'], 'https://example.com');
      expect(row['type'], 'link');
      expect(row['created_at'], created.millisecondsSinceEpoch);
      expect(row['updated_at'], updated.millisecondsSinceEpoch);
      expect(row['copied_at'], copied.millisecondsSinceEpoch);
      expect(row['is_saved'], 1);
      expect(row['is_pinned'], 1);
      expect(row['group_id'], isNull);
      expect(row['note'], 'trang chủ');
      expect(row['copy_count'], 4);
      expect(row['remote_id'], 'obj-1');
      expect(row['dirty'], 0);
      expect(ClipModel.fromMap(row).toMap(), model.toMap());
    });

    test('toMap chỉ ghi các cột đang dùng', () {
      expect(full().toMap().keys, [
        'id',
        'content',
        'type',
        'created_at',
        'updated_at',
        'copied_at',
        'is_saved',
        'is_pinned',
        'group_id',
        'note',
        'copy_count',
        'remote_id',
        'dirty',
      ]);
    });

    test('đọc được dòng tối thiểu: mặc định của schema và loại lạ', () async {
      final raw = await db.raw;
      // Only the NOT NULL columns without a default, as a v1 row was.
      await raw.insert('clips', {
        'id': 'c1',
        'content': 'x',
        'type': 'file',
        'created_at': 1,
        'updated_at': 2,
      });

      final model = ClipModel.fromMap((await raw.query('clips')).single);

      expect(model.type, ClipType.text);
      expect(model.copiedAt, isNull);
      expect(model.isSaved, isFalse);
      expect(model.isPinned, isFalse);
      expect(model.copyCount, 0);
      expect(model.remoteId, isNull);
      // v2 added `dirty` defaulting to 1: unpushed.
      expect(model.dirty, isTrue);
      expect(model.isTemp, isTrue);
    });
  });

  group('Parse', () {
    test('toParse giữ nguyên tên field của lớp Clip, không có space', () {
      expect(full().toParse(), {
        'localId': 'mgx3k2a1-1x2y3z',
        'content': 'https://example.com',
        'kind': 'link',
        'clipCreatedAt': created.millisecondsSinceEpoch,
        'clipUpdatedAt': updated.millisecondsSinceEpoch,
        'isSaved': true,
        'isPinned': true,
        'groupLocalId': null,
        'note': 'trang chủ',
        'copyCount': 4,
      });
    });

    test('fromParse đọc object của server, sạch và giữ copiedAt local', () {
      final model = ClipModel.fromParse(
        {
          'objectId': 'obj-9',
          'space': 'nha',
          'localId': 'c9',
          'content': '#FF0000',
          'kind': 'color',
          'clipCreatedAt': created.millisecondsSinceEpoch,
          'clipUpdatedAt': updated.millisecondsSinceEpoch,
          'isSaved': true,
          'isPinned': false,
          'groupLocalId': 'g1',
          'note': 'đỏ',
          'copyCount': 2,
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
        copiedAt: copied,
        now: DateTime(2030),
      );

      expect(model.id, 'c9');
      expect(model.content, '#FF0000');
      expect(model.type, ClipType.color);
      expect(model.createdAt, created);
      expect(model.updatedAt, updated);
      expect(model.copiedAt, copied);
      expect(model.isSaved, isTrue);
      expect(model.isPinned, isFalse);
      expect(model.groupId, 'g1');
      expect(model.note, 'đỏ');
      expect(model.copyCount, 2);
      expect(model.remoteId, 'obj-9');
      expect(model.dirty, isFalse);
    });

    test('fromParse thiếu field: giờ lấy từ now, còn lại về mặc định', () {
      final now = DateTime(2026, 10, 22, 9);
      final model = ClipModel.fromParse({'localId': 'c1'}, now: now);

      expect(model.content, '');
      expect(model.type, ClipType.text);
      expect(model.createdAt, now);
      expect(model.updatedAt, now);
      expect(model.copiedAt, isNull);
      expect(model.isSaved, isFalse);
      expect(model.isPinned, isFalse);
      expect(model.groupId, isNull);
      expect(model.copyCount, 0);
      expect(model.remoteId, isNull);
    });

    test('toParse rồi fromParse cho lại cùng dữ liệu', () {
      final model = full();
      final back = ClipModel.fromParse(
        {...model.toParse(), 'objectId': 'obj-1'},
        copiedAt: copied,
        now: DateTime(2030),
      );
      expect(back.toMap(), model.toMap());
    });
  });
}
