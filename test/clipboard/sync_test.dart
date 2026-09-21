import 'package:event_notice/clipboard/models/clip_item.dart';
import 'package:event_notice/clipboard/sync/parse_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ParseConfig', () {
    test('build không có .env thì app chạy hoàn toàn cục bộ', () {
      // Không có --dart-define nào trong `flutter test`.
      final config = ParseConfig.fromEnvironment();
      expect(config.isConfigured, isFalse);
      expect(config.serverUrl, ParseConfig.defaultServerUrl);
      expect(config.space, ParseConfig.defaultSpace);
    });

    test('server URL thừa dấu / vẫn ghép đúng đường dẫn', () {
      const config = ParseConfig(
        appId: 'app',
        clientKey: 'client',
        serverUrl: 'https://parseapi.back4app.com/',
        space: 'default',
      );
      expect(config.isConfigured, isTrue);
      expect(config.classUri('Clip').toString(),
          'https://parseapi.back4app.com/classes/Clip');
      expect(config.objectUri('Clip', 'abc').toString(),
          'https://parseapi.back4app.com/classes/Clip/abc');
    });

    test('placeholder YOUR_* trong .env bị coi là chưa điền', () {
      // Build thật sẽ chạy: flutter run --dart-define-from-file=.env
      // Chỉ copy .env.example mà chưa điền thì app phải ở chế độ cục bộ,
      // thay vì gọi Back4App bằng App ID giả rồi báo lỗi liên tục.
      const config = ParseConfig(
        appId: 'YOUR_APP_ID',
        clientKey: 'YOUR_CLIENT_KEY',
        serverUrl: ParseConfig.defaultServerUrl,
        space: ParseConfig.defaultSpace,
      );
      expect(ParseConfig.cleanValue(config.appId), isEmpty);
      expect(ParseConfig.cleanValue(config.clientKey), isEmpty);
      expect(ParseConfig.cleanValue('  app-that-thu  '), 'app-that-thu');
    });

    test('header gửi đúng App ID và Client Key', () {
      const config = ParseConfig(
        appId: 'app',
        clientKey: 'client',
        serverUrl: ParseConfig.defaultServerUrl,
        space: 'default',
      );
      expect(config.headers, {
        'X-Parse-Application-Id': 'app',
        'X-Parse-Client-Key': 'client',
      });
    });
  });

  group('ClipItem đồng bộ', () {
    ClipItem sample() {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      return ClipItem(
        id: 'local-1',
        content: 'xin chào',
        type: ClipType.text,
        createdAt: now,
        updatedAt: now,
        isSaved: true,
        isPinned: true,
        groupId: 'g1',
        copyCount: 3,
      );
    }

    test('gửi lên rồi nhận về giữ nguyên nội dung', () {
      final original = sample();
      final json = {...original.toParse('space-1'), 'objectId': 'abc123'};
      final restored = ClipItem.fromParse(json);

      expect(restored.id, original.id);
      expect(restored.content, original.content);
      expect(restored.isPinned, isTrue);
      expect(restored.groupId, 'g1');
      expect(restored.copyCount, 3);
      expect(restored.updatedAt, original.updatedAt);
      expect(restored.remoteId, 'abc123');
      // Vừa nhận từ server nên không còn thay đổi cần đẩy đi.
      expect(restored.dirty, isFalse);
    });

    test('payload gửi lên không còn cột deleted', () {
      // Xoá là xoá hẳn: object bị DELETE trên server, không có cờ tombstone.
      final json = sample().toParse('space-1');
      expect(json.containsKey('deleted'), isFalse);
      expect(json.containsKey('deletedAt'), isFalse);
    });

  });
}
