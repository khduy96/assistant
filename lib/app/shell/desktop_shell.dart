import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/memory_trim.dart';
import '../../core/sync/presentation/sync_controller.dart';
import '../../features/reminders/presentation/reminders_controller.dart';

/// Desktop drives the alarm itself (window + tray); Android hands the schedule
/// to the OS so it still rings with the app closed.
final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// The desktop window and its tray icon: X hides to the tray, an alarm pops
/// the window up in front, and coming back to the window pulls.
class DesktopShell with WindowListener, TrayListener {
  DesktopShell(this._reminders, this._sync);

  static const _alarmWindowSize = Size(520, 480);

  final RemindersController _reminders;

  /// One "Đồng bộ ngay" and one timer cover everything the app keeps.
  final SyncController _sync;

  /// Whether the window was hidden in the tray when an alarm took over, so it
  /// can go back there once the alarm is dismissed.
  bool _hiddenBeforeAlarm = false;

  /// Window geometry to restore after the alarm popup shrinks the window.
  Rect? _boundsBeforeAlarm;

  /// Starts following the window, the tray and the alerts of [_reminders].
  void attach() {
    windowManager.addListener(this);
    trayManager.addListener(this);
    _reminders.onAlertShown = _bringToFront;
    _reminders.onAlertsCleared = _releaseWindow;
    _setUpTray();
  }

  void detach() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }

  /// Shows what is coming up next on the tray icon.
  void showStatus(String status) {
    // Tray tooltips are capped at 127 characters by Windows.
    final tip = 'Trợ lý — $status';
    trayManager.setToolTip(
        tip.length <= 127 ? tip : tip.substring(0, 127));
  }

  Future<void> _setUpTray() async {
    await trayManager.setIcon('assets/icons/tray.ico');
    await trayManager.setToolTip('Trợ lý — đang canh giờ');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'show', label: 'Mở cửa sổ'),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Thoát hẳn'),
    ]));
  }

  Future<void> _showWindow() async {
    _reminders.uiActive = true;
    _sync.onAppActive();
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  /// Shrinks the window into a centred always-on-top popup for the alarm.
  Future<void> _bringToFront() async {
    _hiddenBeforeAlarm = !await windowManager.isVisible();
    _boundsBeforeAlarm ??= await windowManager.getBounds();
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(_alarmWindowSize);
    await windowManager.center();
    await _showWindow();
  }

  /// Puts the window back the way the user had it once no alarm is left.
  Future<void> _releaseWindow() async {
    await windowManager.setAlwaysOnTop(false);
    final saved = _boundsBeforeAlarm;
    if (saved != null) {
      _boundsBeforeAlarm = null;
      await windowManager.setBounds(saved);
    }
    if (_hiddenBeforeAlarm) {
      _hiddenBeforeAlarm = false;
      _reminders.uiActive = false;
      await windowManager.hide();
      trimWorkingSet();
    }
  }

  @override
  void onWindowClose() async {
    // Closing the alarm popup turns the alarm off; otherwise X hides to tray.
    if (_reminders.currentAlert != null) {
      _hiddenBeforeAlarm = true;
      await _reminders.dismissAll();
      return;
    }
    _reminders.uiActive = false;
    await windowManager.hide();
    trimWorkingSet();
  }

  @override
  void onWindowMinimize() {
    _reminders.uiActive = false;
    trimWorkingSet();
  }

  @override
  void onWindowRestore() {
    _reminders.uiActive = true;
    _sync.onAppActive();
  }

  /// Back from another app: pull, unless a cycle ran in the last few minutes.
  @override
  void onWindowFocus() => _sync.onAppActive();

  @override
  void onTrayIconMouseDown() => _showWindow();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
      case 'quit':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
    }
  }
}
