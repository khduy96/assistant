import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:event_notice/core/data/app_paths.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/features/p2p/data/datasources/local_device.dart';
import 'package:event_notice/features/p2p/data/datasources/public_files.dart';
import 'package:event_notice/features/p2p/data/datasources/save_folder.dart';

/// Instant every test starts from.
final start = DateTime(2026, 10, 22, 9);

/// A clock that stays at [current] until a test moves it.
class FakeClock implements Clock {
  FakeClock([DateTime? current]) : current = current ?? start;

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration by) => current = current.add(by);
}

/// Hands out `id-1`, `id-2`, ... in order.
class SequentialIdGenerator implements IdGenerator {
  int calls = 0;

  @override
  String newId() => 'id-${++calls}';
}

/// Puts the app's files in a test directory instead of the real one.
class TempPaths extends AppPaths {
  const TempPaths(this.dir);

  final String dir;

  @override
  Future<String> supportFile(String fileName) async => '$dir/$fileName';
}

/// A machine with a fixed name, platform and address.
class FakeLocalDevice extends LocalDevice {
  const FakeLocalDevice({
    this.name = 'Máy thử',
    this.platform = 'windows',
    this.address = '192.168.1.5',
  });

  final String name;
  final String platform;
  final String address;

  @override
  String get platformTag => platform;

  @override
  String defaultName() => name;

  @override
  Future<String> localAddress() async => address;
}

/// Received files go to [dir] when no folder is chosen.
class FixedSaveFolder extends SaveFolder {
  const FixedSaveFolder(this.dir);

  final Directory dir;

  @override
  Future<Directory> defaultDir() async {
    await dir.create(recursive: true);
    return dir;
  }
}

/// Android's Download folder without the native side: [publish] moves the
/// file into [download] and answers with a fake `content://` uri.
class FakePublicFiles extends PublicFiles {
  FakePublicFiles({this.supported = true, this.download})
    : super(isAndroid: true);

  final bool supported;
  final Directory? download;
  final opened = <String>[];
  int downloadsOpened = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<PublishedFile?> publish(File file) async {
    final target = download;
    if (target == null) return null;
    final name = file.uri.pathSegments.last;
    await file.copy('${target.path}${Platform.pathSeparator}$name');
    await file.delete();
    return PublishedFile(
      uri: 'content://downloads/$name',
      path: 'Download/Trợ lý/$name',
    );
  }

  @override
  Future<bool> openFile(String uri, String name) async {
    opened.add(uri);
    return true;
  }

  @override
  Future<bool> openDownloads() async {
    downloadsOpened++;
    return true;
  }
}

/// A file of [bytes] bytes in [dir], each byte its index mod 256.
File makeFile(Directory dir, String name, int bytes) {
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  file.writeAsBytesSync(
    Uint8List.fromList(List.generate(bytes, (i) => i % 256)),
  );
  return file;
}

/// Names of the entries in [dir], sorted.
List<String> namesIn(Directory dir) =>
    dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

/// Waits until [condition] holds, polling every 10 ms, at most [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition never held', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
