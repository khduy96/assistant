import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'clipboard/data/app_database.dart';
import 'clipboard/state/clipboard_store.dart';
import 'clipboard/ui/clip_tabs.dart';
import 'services/background_service.dart';
import 'services/memory_trim.dart';
import 'services/android_alarm_service.dart';
import 'services/note_store.dart';
import 'services/reminder_store.dart';
import 'services/startup_service.dart';
import 'services/todo_store.dart';
import 'ui/alarm_screen.dart';
import 'ui/home_page.dart';

/// Desktop drives the alarm itself (window + tray); Android hands the schedule
/// to the OS so it still rings with the app closed.
final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // The clipboard history lives in SQLite; desktop needs the ffi engine.
  AppDatabase.initPlatform();

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

  runApp(const EventNoticeApp());
}

class EventNoticeApp extends StatefulWidget {
  const EventNoticeApp({super.key});

  @override
  State<EventNoticeApp> createState() => _EventNoticeAppState();
}

class _EventNoticeAppState extends State<EventNoticeApp>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  static const _alarmWindowSize = Size(520, 480);

  late final AndroidAlarmService? _notifications =
      Platform.isAndroid ? AndroidAlarmService() : null;
  late final BackgroundService? _background =
      Platform.isAndroid ? BackgroundService() : null;
  late final ReminderStore _store = ReminderStore(notifications: _notifications);
  final TodoStore _todos = TodoStore();
  final NoteStore _notes = NoteStore();
  // The todo list and the notes ride along on the clipboard's sync cycle, so
  // one "Đồng bộ ngay" and one timer cover everything the app keeps.
  late final ClipboardStore _clips = ClipboardStore(
    extraCollections: [_todos.syncCollection, _notes.syncCollection],
  );

  /// Which clipboard list is open and what is typed in its search box: the app
  /// bar and the floating button sit outside that tab but follow it.
  final ClipboardTabState _clipTab = ClipboardTabState();

  /// Whether the window was hidden in the tray when an alarm took over, so it
  /// can go back there once the alarm is dismissed.
  bool _hiddenBeforeAlarm = false;

  /// Window geometry to restore after the alarm popup shrinks the window.
  Rect? _boundsBeforeAlarm;

  /// Last text pushed to the Android ongoing notification.
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isDesktop) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _store.onAlertShown = _bringToFront;
      _store.onAlertsCleared = _releaseWindow;
      _setUpTray();
    }
    _start();
  }

  Future<void> _start() async {
    await _notifications?.requestPermissions();
    await _store.init();
    await _todos.init();
    await _notes.init();
    await _clips.init();
    _store.addListener(_updateBackgroundStatus);
    await _startBackgroundService();
    // Opened by tapping an alarm notification: show that alert straight away.
    final payload = await _notifications?.launchPayload();
    if (payload != null) {
      await _store.showAlertFromPayload(payload);
    } else {
      // Woken by a full-screen intent: no tap callback, ask what is ringing.
      await _store.showRingingAlert();
    }
  }

  Future<void> _startBackgroundService() async {
    await _background?.start(status: _store.nextAlertSummary());
  }

  /// Keeps the ongoing notification (Android) and the tray tooltip (Windows)
  /// showing what is coming up next.
  void _updateBackgroundStatus() {
    final deadline = _store.nearestDeadlineSummary();
    final summary = _store.nextAlertSummary();
    final status = deadline == null ? summary : '$summary\n$deadline';
    if (status == _lastStatus) return;
    _lastStatus = status;
    _background?.updateStatus(summary);
    if (isDesktop) {
      // Tray tooltips are capped at 127 characters by Windows.
      final tip = 'Trợ lý — $status';
      trayManager.setToolTip(
          tip.length <= 127 ? tip : tip.substring(0, 127));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS schedule holds a limited window of alerts; top it up on resume.
    _store.uiActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) _store.resync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store.removeListener(_updateBackgroundStatus);
    if (isDesktop) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    _store.dispose();
    _todos.dispose();
    _notes.dispose();
    _clips.dispose();
    _clipTab.dispose();
    super.dispose();
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
    _store.uiActive = true;
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
      _store.uiActive = false;
      await windowManager.hide();
      trimWorkingSet();
    }
  }

  @override
  void onWindowClose() async {
    // Closing the alarm popup turns the alarm off; otherwise X hides to tray.
    if (_store.currentAlert != null) {
      _hiddenBeforeAlarm = true;
      await _store.dismissAll();
      return;
    }
    _store.uiActive = false;
    await windowManager.hide();
    trimWorkingSet();
  }

  @override
  void onWindowMinimize() {
    _store.uiActive = false;
    trimWorkingSet();
  }

  @override
  void onWindowRestore() => _store.uiActive = true;

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

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // The stores outlive the widget tree here, so they are handed over as
        // values and disposed with this state, not by the providers.
        ChangeNotifierProvider<ClipboardStore>.value(value: _clips),
        ChangeNotifierProvider<ClipboardTabState>.value(value: _clipTab),
      ],
      child: _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    return MaterialApp(
      title: 'Trợ lý',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF60A5FA),
        brightness: Brightness.dark,
      ),
      home: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          final alert = _store.currentAlert;
          return Stack(
            children: [
              HomePage(
                store: _store,
                todos: _todos,
                notes: _notes,
                notifications: _notifications,
              ),
              if (alert != null) AlarmScreen(alert: alert, store: _store),
            ],
          );
        },
      ),
    );
  }
}
