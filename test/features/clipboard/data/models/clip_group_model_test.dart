import 'package:event_notice/features/clipboard/data/models/clip_group_model.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_group.dart';
import 'package:flutter_test/flutter_test.dart';

import '../clip_db.dart';

void main() {
  useFfiSqlite();

  late ClipDb db;

  setUp(() async => db = await ClipDb.open());
  tearDown(() => db.close());

  final created = DateTime(2026, 10, 20, 8, 30);
  final updated = DateTime(2026, 10, 21, 9, 15);

  ClipGroupModel full() => ClipGroupModel(
    id: 'g1',
    name: 'Công việc',
    color: 0xFF00B894,
    createdAt: created,
    updatedAt: updated,
    sortOrder: 3,
    remoteId: 'obj-g1',
    dirty: false,
  );

  group('SQLite', () {
    test('round-trip qua bảng groups giữ nguyên mọi cột', () async {
      final raw = await db.raw;
      final model = full();
      await raw.insert('groups', model.toMap());

      final row = (await raw.query('groups')).single;

      expect(row['id'], 'g1');
      expect(row['name'], 'Công việc');
      expect(row['color'], 0xFF00B894);
      expect(row['created_at'], created.millisecondsSinceEpoch);
      expect(row['updated_at'], updated.millisecondsSinceEpoch);
      expect(row['sort_order'], 3);
      expect(row['remote_id'], 'obj-g1');
      expect(row['dirty'], 0);
      expect(ClipGroupModel.fromMap(row).toMap(), model.toMap());
    });

    test('dòng không có updated_at thì lấy created_at', () async {
      final raw = await db.raw;
      await raw.insert('groups', {
        'id': 'g1',
        'name': 'Cũ',
        'color': 0xFF5B8DEF,
        'created_at': created.millisecondsSinceEpoch,
      });

      final model = ClipGroupModel.fromMap((await raw.query('groups')).single);

      expect(model.updatedAt, created);
      expect(model.sortOrder, 0);
      expect(model.remoteId, isNull);
      expect(model.dirty, isTrue);
    });
  });

  group('Parse', () {
    test('toParse giữ nguyên tên field của lớp ClipGroup, không có space', () {
      expect(full().toParse(), {
        'localId': 'g1',
        'name': 'Công việc',
        'color': 0xFF00B894,
        'groupCreatedAt': created.millisecondsSinceEpoch,
        'groupUpdatedAt': updated.millisecondsSinceEpoch,
        'sortOrder': 3,
      });
    });

    test('fromParse đọc object của server và đánh dấu sạch', () {
      final back = ClipGroupModel.fromParse({
        ...full().toParse(),
        'objectId': 'obj-g1',
        'space': 'nha',
      }, now: DateTime(2030));

      expect(back.toMap(), full().toMap());
    });

    test('fromParse thiếu field: tên "Nhóm", màu đầu bảng, giờ lấy từ now', () {
      final now = DateTime(2026, 10, 22, 9);
      final model = ClipGroupModel.fromParse({'localId': 'g2'}, now: now);

      expect(model.name, 'Nhóm');
      expect(model.color, ClipGroup.palette.first);
      expect(model.createdAt, now);
      expect(model.updatedAt, now);
      expect(model.sortOrder, 0);
      expect(model.remoteId, isNull);
      expect(model.dirty, isFalse);
    });
  });
}
