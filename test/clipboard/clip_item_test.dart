import 'package:event_notice/clipboard/models/clip_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClipItem.detectType', () {
    test('nhận diện link, email, màu và code', () {
      expect(ClipItem.detectType('https://example.com'), ClipType.link);
      expect(ClipItem.detectType('me@example.com'), ClipType.email);
      expect(ClipItem.detectType('#FF00AA'), ClipType.color);
      expect(ClipItem.detectType('0912345678'), ClipType.phone);
      expect(ClipItem.detectType('1234.5'), ClipType.number);
      expect(ClipItem.detectType('const a = 1; foo();'), ClipType.code);
      expect(ClipItem.detectType('xin chào'), ClipType.text);
    });
  });

  test('clip tạm hết hạn sau 1 ngày', () {
    final now = DateTime.now();
    final item = ClipItem(
      id: '1',
      content: 'x',
      type: ClipType.text,
      createdAt: now,
      updatedAt: now,
    );
    expect(item.isTemp, isTrue);
    expect(item.expiresAt.difference(now).inHours, 24);
    expect(item.copyWith(isPinned: true).isTemp, isFalse);
  });
}
