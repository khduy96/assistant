import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

final _created = DateTime(2026, 10, 22, 8);

ClipItem _clip({
  String content = 'x',
  bool saved = false,
  bool pinned = false,
  String? groupId,
  String? note,
  DateTime? copiedAt,
}) => ClipItem(
  id: 'c1',
  content: content,
  type: ClipType.text,
  createdAt: _created,
  updatedAt: _created,
  copiedAt: copiedAt,
  isSaved: saved,
  isPinned: pinned,
  groupId: groupId,
  note: note,
  copyCount: 2,
);

void main() {
  group('ClipItem.detectType', () {
    test('nhận diện link, email, màu và code (như bản cũ)', () {
      expect(ClipItem.detectType('https://example.com'), ClipType.link);
      expect(ClipItem.detectType('me@example.com'), ClipType.email);
      expect(ClipItem.detectType('#FF00AA'), ClipType.color);
      expect(ClipItem.detectType('0912345678'), ClipType.phone);
      expect(ClipItem.detectType('1234.5'), ClipType.number);
      expect(ClipItem.detectType('const a = 1; foo();'), ClipType.code);
      expect(ClipItem.detectType('xin chào'), ClipType.text);
    });

    test('cắt khoảng trắng trước khi nhận diện; chuỗi rỗng là văn bản', () {
      expect(ClipItem.detectType('  https://example.com \n'), ClipType.link);
      expect(ClipItem.detectType(''), ClipType.text);
      expect(ClipItem.detectType('   '), ClipType.text);
    });

    test('màu: chỉ #rgb, #rrggbb hoặc #aarrggbb', () {
      expect(ClipItem.detectType('#abc'), ClipType.color);
      expect(ClipItem.detectType('#11223344'), ClipType.color);
      expect(ClipItem.detectType('#12345'), ClipType.text);
      expect(ClipItem.detectType('#GGGGGG'), ClipType.text);
    });

    test('link bắt đầu bằng www. và không có khoảng trắng', () {
      expect(ClipItem.detectType('www.example.com/a?b=1'), ClipType.link);
      expect(ClipItem.detectType('https://a.b c'), ClipType.text);
    });

    test('số điện thoại cần ít nhất 8 chữ số, ít hơn thì là số', () {
      expect(ClipItem.detectType('+84 912 345 678'), ClipType.phone);
      expect(ClipItem.detectType('(028) 3822-1234'), ClipType.phone);
      expect(ClipItem.detectType('1234567'), ClipType.number);
      expect(ClipItem.detectType('-12,5'), ClipType.number);
    });

    test('code: hai dấu hiệu, hoặc một dấu hiệu khi có xuống dòng', () {
      expect(ClipItem.detectType('if (a) {\n  return b;\n}'), ClipType.code);
      expect(ClipItem.detectType('a;\nb'), ClipType.code);
      expect(ClipItem.detectType('a; b'), ClipType.text);
      expect(ClipItem.detectType('SELECT * FROM t;'), ClipType.code);
    });
  });

  group('ClipItem.preview', () {
    test('gộp mọi khoảng trắng thành một dấu cách', () {
      expect(_clip(content: '  a\n\n b\t c  ').preview, 'a b c');
    });

    test('nội dung trống hiện (trống)', () {
      expect(_clip(content: ' \n ').preview, '(trống)');
      expect(_clip(content: '').preview, '(trống)');
    });
  });

  group('clip tạm', () {
    test('chưa lưu và chưa ghim thì là clip tạm', () {
      expect(_clip().isTemp, isTrue);
      expect(_clip(saved: true).isTemp, isFalse);
      expect(_clip(pinned: true).isTemp, isFalse);
      expect(_clip().copyWith(isPinned: true).isTemp, isFalse);
    });

    test('hết hạn sau đúng 1 ngày kể từ createdAt', () {
      expect(ClipItem.tempTtl, const Duration(days: 1));
      expect(_clip().expiresAt, DateTime(2026, 10, 23, 8));
    });

    test('remaining tính theo thời điểm truyền vào', () {
      final clip = _clip();
      expect(
        clip.remaining(DateTime(2026, 10, 22, 14, 30)),
        const Duration(hours: 17, minutes: 30),
      );
      expect(clip.remaining(_created), const Duration(days: 1));
    });

    test('remaining bằng 0 khi đã tới hoặc quá hạn, không âm', () {
      final clip = _clip();
      expect(clip.remaining(DateTime(2026, 10, 23, 8)), Duration.zero);
      expect(clip.remaining(DateTime(2026, 10, 25)), Duration.zero);
    });
  });

  group('ClipItem.copyWith', () {
    test('giữ nguyên các field không truyền, id không đổi', () {
      final clip = _clip(
        saved: true,
        groupId: 'g1',
        note: 'ghi chú',
        copiedAt: _created,
      );
      final later = DateTime(2026, 10, 22, 9);
      final copy = clip.copyWith(updatedAt: later);

      expect(copy.id, 'c1');
      expect(copy.updatedAt, later);
      expect(copy.groupId, 'g1');
      expect(copy.note, 'ghi chú');
      expect(copy.copiedAt, _created);
      expect(copy.copyCount, 2);
      expect(copy.isSaved, isTrue);
      expect(copy, isNot(clip));
      expect(clip.copyWith(), clip);
    });

    test('null tường minh xoá groupId, note và copiedAt', () {
      final clip = _clip(groupId: 'g1', note: 'n', copiedAt: _created);
      final copy = clip.copyWith(groupId: null, note: null, copiedAt: null);

      expect(copy.groupId, isNull);
      expect(copy.note, isNull);
      expect(copy.copiedAt, isNull);
    });
  });

  test('so bằng theo giá trị', () {
    expect(_clip(groupId: 'g'), _clip(groupId: 'g'));
    expect(_clip(groupId: 'g').hashCode, _clip(groupId: 'g').hashCode);
    expect(_clip(groupId: 'g'), isNot(_clip(groupId: 'h')));
  });
}
