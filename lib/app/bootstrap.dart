import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../core/data/app_database.dart';
import '../core/platform/startup_service.dart';
import '../features/pomodoro/presentation/pages/pomodoro_page.dart';
import 'app.dart';
import 'di/injection.dart';
import 'shell/desktop_shell.dart';

/// Gets the platform, the database, the services and the window ready, then
/// returns the app to run.
///
/// Returns null when [args] ask for a clock window instead: that window has
/// already started its own app.
Future<Widget?> bootstrap(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cửa sổ đồng hồ riêng: không DB, không tray, không báo thức.
  for (final flag in [pomodoroFlag, countdownFlag]) {
    if (isDesktop && args.contains(flag)) {
      await runClockWindow(flag);
      return null;
    }
  }
  // The clipboard history lives in SQLite; desktop needs the ffi engine.
  AppDatabase.initPlatform();
  final sl = configureAppDependencies();

  var silentStart = false;
  if (isDesktop) {
    await windowManager.ensureInitialized();

    // Launched by Windows at login: stay in the tray, no window on the screen.
    silentStart = args.contains(StartupService.startupFlag);

    const options = WindowOptions(
      size: Size(880, 620),
      minimumSize: Size(460, 420),
      center: true,
      title: 'Trợ lý',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (silentStart) {
        await windowManager.setSkipTaskbar(true);
        return;
      }
      await windowManager.show();
      await windowManager.focus();
    });
    // Closing the window keeps the app alive in the tray so alarms still fire.
    await windowManager.setPreventClose(true);
  }

  return EventNoticeApp.fromLocator(sl);
}
