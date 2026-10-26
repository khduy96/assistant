import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/services/clip_edits.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 21, 8);
final _now = DateTime(2026, 10, 22, 14, 30);

ClipItem _clip({
  bool saved = false,
  bool pinned = false,
  String? groupId,
  String? note,
}) => ClipItem(
  id: 'c1',
  content: 'x',
  type: ClipType.text,
  createdAt: _created,
  updatedAt: _created,
  isSaved: saved,
  isPinned: pinned,
  groupId: groupId,
  note: note,
  copyCount: 3,
);

void main() {
  test('saved: lưu, groupId null thì giữ nhóm cũ', () {
    final kept = ClipEdits.saved(_clip(groupId: 'g1'), _now);
    expect(kept.isSaved, isTrue);
    expect(kept.groupId, 'g1');
    expect(kept.updatedAt, _now);
    expect(kept.createdAt, _created);

    expect(ClipEdits.saved(_clip(), _now, groupId: 'g2').groupId, 'g2');
  });

  test('unsaved: thành clip tạm, mất nhóm, đếm lại 1 ngày', () {
    final clip = ClipEdits.unsaved(
      _clip(saved: true, pinned: true, groupId: 'g1'),
      _now,
    );
    expect(clip.isTemp, isTrue);
    expect(clip.isPinned, isFalse);
    expect(clip.groupId, isNull);
    expect(clip.createdAt, _now);
    expect(clip.updatedAt, _now);
    expect(clip.remaining(_now), const Duration(days: 1));
  });

  test('pinned: ghim clip tạm thì lưu luôn; bỏ ghim vẫn giữ đã lưu', () {
    final pinned = ClipEdits.pinned(_clip(), true, _now);
    expect(pinned.isPinned, isTrue);
    expect(pinned.isSaved, isTrue);
    expect(pinned.updatedAt, _now);

    final unpinned = ClipEdits.pinned(pinned, false, _now);
    expect(unpinned.isPinned, isFalse);
    expect(unpinned.isSaved, isTrue);

    final tempUnpinned = ClipEdits.pinned(_clip(), false, _now);
    expect(tempUnpinned.isTemp, isTrue);
  });

  test(
    'grouped: gán nhóm cho clip tạm thì lưu luôn; bỏ nhóm giữ trạng thái',
    () {
      final grouped = ClipEdits.grouped(_clip(), 'g1', _now);
      expect(grouped.groupId, 'g1');
      expect(grouped.isSaved, isTrue);
      expect(grouped.updatedAt, _now);

      final out = ClipEdits.grouped(grouped, null, _now);
      expect(out.groupId, isNull);
      expect(out.isSaved, isTrue);

      expect(ClipEdits.grouped(_clip(), null, _now).isTemp, isTrue);
    },
  );

  test('edited: cắt khoảng trắng, nhận diện lại loại, note null giữ cũ', () {
    final edited = ClipEdits.edited(
      _clip(note: 'cũ'),
      '  https://example.com  ',
      _now,
    );
    expect(edited.content, 'https://example.com');
    expect(edited.type, ClipType.link);
    expect(edited.note, 'cũ');
    expect(edited.updatedAt, _now);

    expect(
      ClipEdits.edited(_clip(note: 'cũ'), 'x', _now, note: 'mới').note,
      'mới',
    );
  });

  test('copied: chỉ đổi copiedAt và copyCount', () {
    final copied = ClipEdits.copied(_clip(), _now);
    expect(copied.copiedAt, _now);
    expect(copied.copyCount, 4);
    expect(copied.updatedAt, _created);
    expect(copied.createdAt, _created);
  });

  test('recaptured: clip tạm đặt lại createdAt, clip đã lưu thì giữ', () {
    final temp = ClipEdits.recaptured(_clip(), _now);
    expect(temp.createdAt, _now);
    expect(temp.updatedAt, _now);
    expect(temp.copiedAt, _now);

    final saved = ClipEdits.recaptured(_clip(saved: true), _now);
    expect(saved.createdAt, _created);
    expect(saved.updatedAt, _now);
    expect(saved.copiedAt, _now);
  });
}
