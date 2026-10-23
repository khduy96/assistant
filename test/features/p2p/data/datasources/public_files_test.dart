import 'dart:io';

import 'package:event_notice/features/p2p/data/datasources/public_files.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('event_notice/files');
  late List<MethodCall> calls;
  late Object? Function(MethodCall call) answer;

  setUp(() {
    calls = [];
    answer = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('ngoài Android thì không gọi native', () async {
    final files = PublicFiles(isAndroid: false);

    expect(await files.isSupported(), isFalse);
    expect(await files.publish(File('a.txt')), isNull);
    expect(await files.openFile('content://1', 'a.txt'), isFalse);
    expect(await files.openDownloads(), isFalse);
    expect(calls, isEmpty);
  });

  test('saveToDownloads gửi đúng đường dẫn và thư mục con', () async {
    answer = (_) => {
      'uri': 'content://downloads/7',
      'path': 'Download/Trợ lý/a.txt',
    };
    final files = PublicFiles(isAndroid: true);

    final published = await files.publish(File('/data/a.txt'));

    expect(calls.single.method, 'saveToDownloads');
    expect(calls.single.arguments, {'path': '/data/a.txt', 'subDir': 'Trợ lý'});
    expect(published?.uri, 'content://downloads/7');
    expect(published?.path, 'Download/Trợ lý/a.txt');
  });

  test('native báo lỗi hoặc thiếu trường thì giữ tệp tại chỗ', () async {
    final files = PublicFiles(isAndroid: true);

    answer = (_) => {'uri': 'content://downloads/7'};
    expect(await files.publish(File('a.txt')), isNull);

    answer = (_) => throw PlatformException(code: 'io');
    expect(await files.publish(File('a.txt')), isNull);
    expect(await files.openFile('content://1', 'a.txt'), isFalse);
    expect(await files.openDownloads(), isFalse);
  });

  test('isSupported hỏi native một lần rồi nhớ', () async {
    answer = (_) => true;
    final files = PublicFiles(isAndroid: true);

    expect(await files.isSupported(), isTrue);
    expect(await files.isSupported(), isTrue);
    expect(calls.map((c) => c.method), ['isSupported']);
  });

  test('openFile và openDownloads gọi đúng phương thức', () async {
    answer = (_) => true;
    final files = PublicFiles(isAndroid: true);

    expect(await files.openFile('content://1', 'a.txt'), isTrue);
    expect(await files.openDownloads(), isTrue);
    expect(calls.map((c) => c.method), ['openFile', 'openDownloads']);
    expect(calls.first.arguments, {'uri': 'content://1', 'name': 'a.txt'});
  });
}
