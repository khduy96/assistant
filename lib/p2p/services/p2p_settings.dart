import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Tên máy + id cố định và các tuỳ chọn của phần truyền tệp, lưu trong một
/// tệp JSON cạnh các dữ liệu khác của app.
class P2pSettings {
  P2pSettings({
    required this.deviceId,
    required this.deviceName,
    required this.autoAccept,
    required this.enabled,
    required this.saveDir,
    List<String>? manualPeers,
  }) : manualPeers = manualPeers ?? [];

  final String deviceId;
  String deviceName;

  /// Nhận thẳng không hỏi. Mặc định tắt: mỗi tệp lạ đều phải bấm "Nhận".
  bool autoAccept;

  /// Bật/tắt toàn bộ phần P2P (mở cổng, phát quảng bá).
  bool enabled;

  /// Thư mục lưu tệp nhận được; null nghĩa là dùng thư mục mặc định.
  String? saveDir;

  /// Thiết bị người dùng tự khai bằng IP, dạng `172.28.0.50:45700`. Dành cho
  /// mạng công ty chặn broadcast nên hai máy không tự thấy nhau được.
  final List<String> manualPeers;

  static File? _file;

  static Future<File> _target() async {
    final cached = _file;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _file = File('${dir.path}${Platform.pathSeparator}p2p.json');
  }

  static Future<P2pSettings> load() async {
    final file = await _target();
    Map<String, dynamic> raw = const {};
    if (await file.exists()) {
      try {
        raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Tệp hỏng: bắt đầu lại từ mặc định thay vì chặn app.
      }
    }
    final settings = P2pSettings(
      deviceId: raw['deviceId'] as String? ?? const Uuid().v4(),
      deviceName: raw['deviceName'] as String? ?? defaultDeviceName(),
      autoAccept: raw['autoAccept'] as bool? ?? false,
      enabled: raw['enabled'] as bool? ?? true,
      saveDir: raw['saveDir'] as String?,
      manualPeers: (raw['manualPeers'] as List?)?.cast<String>().toList(),
    );
    if (raw.isEmpty) await settings.save();
    return settings;
  }

  Future<void> save() async {
    final file = await _target();
    await file.writeAsString(jsonEncode({
      'deviceId': deviceId,
      'deviceName': deviceName,
      'autoAccept': autoAccept,
      'enabled': enabled,
      if (saveDir != null) 'saveDir': saveDir,
      'manualPeers': manualPeers,
    }));
  }

  static String defaultDeviceName() {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    return switch (platformTag) {
      'android' => 'Điện thoại',
      'ios' => 'iPhone',
      _ => 'Máy tính',
    };
  }

  static String get platformTag {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  /// Nơi cất tệp nhận được khi người dùng chưa chọn thư mục riêng.
  ///
  /// Android không cho ghi thẳng vào Download nếu không xin quyền toàn bộ bộ
  /// nhớ, nên dùng thư mục riêng của app (vẫn xem được bằng trình quản lý tệp).
  static Future<Directory> defaultSaveDir() async {
    Directory? base;
    if (Platform.isAndroid) {
      base = await getExternalStorageDirectory();
    } else {
      try {
        base = await getDownloadsDirectory();
      } catch (_) {
        base = null;
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}Trợ lý');
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> resolveSaveDir() async {
    final custom = saveDir;
    if (custom != null && custom.trim().isNotEmpty) {
      final dir = Directory(custom);
      try {
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        // Thư mục đã chọn không còn ghi được (ổ rời, thẻ nhớ rút ra).
      }
    }
    return defaultSaveDir();
  }
}
