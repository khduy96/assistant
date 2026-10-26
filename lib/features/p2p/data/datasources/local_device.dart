import 'dart:io';

/// What file transfer needs to know about the machine it runs on. Tests
/// subclass it to pin the answers.
class LocalDevice {
  const LocalDevice();

  /// 'android', 'windows', ... as sent in discovery packets and by
  /// `GET /info`; the other side only uses it to pick an icon.
  String get platformTag {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'other';
  }

  /// Name a device gets before the user picks one: the host name, or a word
  /// for the kind of device when there is no usable host name.
  String defaultName() {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
    return switch (platformTag) {
      'android' => 'Điện thoại',
      'ios' => 'iPhone',
      _ => 'Máy tính',
    };
  }

  /// This machine's first IPv4 address on the LAN, or empty when there is
  /// none or the network cards cannot be listed.
  Future<String> localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {
      // Only shown to the user, so no address is no error.
    }
    return '';
  }
}
