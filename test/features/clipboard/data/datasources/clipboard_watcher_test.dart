import 'dart:async';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/clipboard/data/datasources/clipboard_watcher.dart';
import 'package:event_notice/features/clipboard/domain/ports/clipboard_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The watcher against a fake system clipboard behind the platform channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String? clipboard;
  late int reads;
  late bool failWrites;
  late ClipboardWatcher watcher;

  setUp(() {
    clipboard = null;
    reads = 0;
    failWrites = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.getData':
              reads++;
              final text = clipboard;
              return text == null ? null : {'text': text};
            case 'Clipboard.setData':
              if (failWrites) {
                throw PlatformException(code: 'busy');
              }
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
          }
          return null;
        });
    watcher = ClipboardWatcher(interval: const Duration(milliseconds: 5));
  });

  tearDown(() async {
    await watcher.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  /// Waits, polling, until [done] holds; fails after a second.
  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> pause() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  test('là một ClipboardSource, bật sẵn', () {
    expect(watcher, isA<ClipboardSource>());
    expect(watcher.isEnabled, isTrue);
  });

  test('không ai nghe thì không đọc clipboard', () async {
    clipboard = 'x';
    await pause();
    expect(reads, 0);
  });

  test('báo giá trị mới đã cắt khoảng trắng; bỏ qua rỗng và giá trị vừa '
      'thấy', () async {
    final seen = <String>[];
    final sub = watcher.captures.listen(seen.add);
    addTearDown(sub.cancel);

    clipboard = '  một  ';
    await until(() => seen.isNotEmpty);
    clipboard = '   ';
    await pause();
    clipboard = 'một';
    await pause();
    clipboard = 'hai';
    await until(() => seen.length == 2);

    expect(seen, ['một', 'hai']);
  });

  test('huỷ đăng ký thì ngừng đọc clipboard', () async {
    final sub = watcher.captures.listen((_) {});
    await until(() => reads > 0);

    await sub.cancel();
    await pause();
    final after = reads;
    await pause();

    expect(reads, after);
  });

  test('tắt thì ngừng báo, bật lại thì báo tiếp', () async {
    final seen = <String>[];
    final sub = watcher.captures.listen(seen.add);
    addTearDown(sub.cancel);
    await until(() => reads > 0);

    watcher.setEnabled(false);
    expect(watcher.isEnabled, isFalse);
    await pause();
    final after = reads;
    clipboard = 'lúc tắt';
    await pause();
    expect(reads, after);
    expect(seen, isEmpty);

    watcher.setEnabled(true);
    await until(() => seen.isNotEmpty);
    expect(seen, ['lúc tắt']);
  });

  test('bật khi chưa ai nghe thì vẫn chưa đọc', () async {
    watcher.setEnabled(false);
    watcher.setEnabled(true);
    await pause();
    expect(reads, 0);
  });

  test('write đặt nội dung lên clipboard và không bị bắt lại', () async {
    final seen = <String>[];
    final sub = watcher.captures.listen(seen.add);
    addTearDown(sub.cancel);
    await until(() => reads > 0);

    final result = await watcher.write('từ trong app');
    await pause();

    expect(result.isOk, isTrue);
    expect(clipboard, 'từ trong app');
    expect(seen, isEmpty);
  });

  test('write lỗi thì trả Err, không ném', () async {
    failWrites = true;

    final result = await watcher.write('x');

    expect(result.failureOrNull, isA<UnexpectedFailure>());
  });

  test('app xuống nền thì ngừng đọc, quay lại thì đọc tiếp', () async {
    final seen = <String>[];
    final sub = watcher.captures.listen(seen.add);
    addTearDown(sub.cancel);
    await until(() => reads > 0);

    watcher.didChangeAppLifecycleState(AppLifecycleState.paused);
    await pause();
    final after = reads;
    clipboard = 'lúc ở nền';
    await pause();
    expect(reads, after);

    watcher.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await until(() => seen.isNotEmpty);
    expect(seen, ['lúc ở nền']);
  });

  test('lỗi khi đọc clipboard không làm dừng việc theo dõi', () async {
    var failing = true;
    final logs = <String?>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = print);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          reads++;
          if (failing) throw PlatformException(code: 'locked');
          return {'text': 'sau lỗi'};
        });
    final seen = <String>[];
    final sub = watcher.captures.listen(seen.add);
    addTearDown(sub.cancel);
    await until(() => reads > 1);

    failing = false;
    await until(() => seen.isNotEmpty);

    expect(seen, ['sau lỗi']);
    expect(logs.first, startsWith('Clipboard poll failed'));
  });

  test('dispose đóng luồng captures', () async {
    final done = Completer<void>();
    watcher.captures.listen((_) {}, onDone: done.complete);

    await watcher.dispose();

    await done.future.timeout(const Duration(seconds: 1));
  });
}
