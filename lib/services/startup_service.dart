import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// Registers the app in the per-user "Run" key so Windows starts it at login.
///
/// The registered command carries [startupFlag] so an auto-started instance
/// goes straight to the tray instead of popping a window on every boot.
class StartupService {
  static const registryValueName = 'NhacViec';
  static const startupFlag = '--minimized';
  static const _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

  String get _command => '"${Platform.resolvedExecutable}" $startupFlag';

  /// True when Windows is set to launch this exe at login.
  bool isEnabled() {
    if (!Platform.isWindows) return false;
    try {
      final key = CURRENT_USER.open(_runKeyPath);
      try {
        final value = key.getString(registryValueName);
        // An entry pointing at a different build counts as "off".
        return value != null && value.contains(Platform.resolvedExecutable);
      } finally {
        key.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Adds or removes the login entry. Returns the state actually in effect.
  bool setEnabled(bool enabled) {
    if (!Platform.isWindows) return false;
    try {
      final key = CURRENT_USER.open(
        _runKeyPath,
        config: const RegistryOpenConfig(
          access: RegistryAccess.readWrite,
          create: true,
        ),
      );
      try {
        if (enabled) {
          key.setValue(registryValueName, RegistryValue.string(_command));
        } else {
          key.removeValue(registryValueName);
        }
        return enabled;
      } finally {
        key.close();
      }
    } catch (_) {
      return isEnabled();
    }
  }
}
