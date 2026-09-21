import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point of the foreground service isolate.
@pragma('vm:entry-point')
void startAlarmWatchService() {
  FlutterForegroundTask.setTaskHandler(_AlarmWatchHandler());
}

/// The service exists to keep the app process alive and to show "đang canh
/// giờ" in the status bar; the ringing itself is owned by the OS alarm
/// schedule, so this handler has no work of its own to do.
class _AlarmWatchHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps the app running in the background on Android with a permanent
/// "đang canh giờ" notification, the way the tray icon does on Windows.
class BackgroundService {
  static const _channelId = 'alarm_watch_channel';

  bool _initialised = false;

  void _ensureInit() {
    if (_initialised) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: 'Nhắc việc đang chạy nền',
        channelDescription: 'Thông báo thường trực để app canh giờ báo',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Nothing to poll: the OS holds the alarms.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialised = true;
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Future<void> start({required String status}) async {
    _ensureInit();
    if (await isRunning) {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'Nhắc việc đang canh giờ',
        notificationText: status,
      );
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: 1000,
      serviceTypes: [ForegroundServiceTypes.specialUse],
      notificationTitle: 'Nhắc việc đang canh giờ',
      notificationText: status,
      callback: startAlarmWatchService,
    );
  }

  Future<void> updateStatus(String status) async {
    if (!await isRunning) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: 'Nhắc việc đang canh giờ',
      notificationText: status,
    );
  }

  Future<void> stop() async {
    if (!await isRunning) return;
    await FlutterForegroundTask.stopService();
  }
}
