import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';

import '../core/platform/background_service.dart';
import '../core/sync/domain/entities/sync_settings.dart';
import '../core/sync/presentation/sync_controller.dart';
import '../features/clipboard/data/datasources/clipboard_watcher.dart';
import '../features/clipboard/data/repositories/clipboard_repository_impl.dart';
import '../features/clipboard/presentation/clipboard_controller.dart';
import '../features/clipboard/presentation/clipboard_tab_state.dart';
import '../features/notes/data/repositories/note_repository_impl.dart';
import '../features/notes/presentation/notes_controller.dart';
import '../features/p2p/data/repositories/peer_repository_impl.dart';
import '../features/p2p/data/repositories/transfer_repository_impl.dart';
import '../features/p2p/presentation/p2p_controller.dart';
import '../features/p2p/presentation/p2p_files.dart';
import '../features/reminders/data/repositories/reminder_repository_impl.dart';
import '../features/reminders/domain/ports/alarm_ringer.dart';
import '../features/reminders/presentation/reminders_controller.dart';
import '../features/todos/data/repositories/todo_repository_impl.dart';
import '../features/todos/presentation/todo_reminder_editor.dart';
import '../features/todos/presentation/todos_controller.dart';
import 'shell/alarm_overlay.dart';
import 'shell/desktop_shell.dart';
import 'shell/home_page.dart';

class EventNoticeApp extends StatefulWidget {
  /// The reminders, notes, todos, clipboard data, sync and file transfer come
  /// from the service locator through [EventNoticeApp.fromLocator], so no
  /// widget below has to reach into it.
  const EventNoticeApp({
    super.key,
    required this.reminders,
    required this.reminderRepository,
    required this.alarmRinger,
    required this.notes,
    required this.noteRepository,
    required this.todos,
    required this.todoRepository,
    required this.todoReminderEditor,
    required this.clipboard,
    required this.clipRepository,
    required this.clipboardWatcher,
    required this.sync,
    required this.syncSettings,
    required this.p2p,
    required this.peerRepository,
    required this.transferRepository,
    required this.p2pFiles,
  });

  /// Everything the app shows and closes, out of [sl] once
  /// `configureDependencies` has filled it.
  factory EventNoticeApp.fromLocator(GetIt sl) => EventNoticeApp(
        reminders: sl<RemindersController>(),
        reminderRepository: sl<ReminderRepositoryImpl>(),
        alarmRinger: sl<AlarmRinger>(),
        notes: sl<NotesController>(),
        noteRepository: sl<NoteRepositoryImpl>(),
        todos: sl<TodosController>(),
        todoRepository: sl<TodoRepositoryImpl>(),
        todoReminderEditor: sl<TodoReminderEditor>(),
        clipboard: sl<ClipboardController>(),
        clipRepository: sl<ClipboardRepositoryImpl>(),
        clipboardWatcher: sl<ClipboardWatcher>(),
        sync: sl<SyncController>(),
        syncSettings: sl<SyncSettings>(),
        p2p: sl<P2pController>(),
        peerRepository: sl<PeerRepositoryImpl>(),
        transferRepository: sl<TransferRepositoryImpl>(),
        p2pFiles: sl<P2pFiles>(),
      );

  /// The same controller the todo list reaches through [todoReminderEditor]
  /// and its linked-reminder bridge.
  final RemindersController reminders;

  /// Behind [reminders]. Closed with the app.
  final ReminderRepositoryImpl reminderRepository;

  /// Plays the alarm tone for [reminders] on desktop. Released with the app.
  final AlarmRinger alarmRinger;

  final NotesController notes;

  /// Loaded at startup, before the sync engine first reads the notes.
  final NoteRepositoryImpl noteRepository;

  final TodosController todos;

  /// Loaded at startup, before the sync engine first reads the todos.
  final TodoRepositoryImpl todoRepository;

  /// How the todo list opens the reminder form.
  final TodoReminderEditor todoReminderEditor;

  final ClipboardController clipboard;

  /// The clipboard tables, shared by the clipboard's use cases and its sync
  /// collections. Closed with the app.
  final ClipboardRepositoryImpl clipRepository;

  /// Watches the system clipboard for [clipboard]. Closed with the app.
  final ClipboardWatcher clipboardWatcher;

  /// When clips, todos and notes sync, and how the last cycle went.
  final SyncController sync;

  /// How this build syncs, known before [sync] starts.
  final SyncSettings syncSettings;

  /// Truyền tệp thẳng giữa các máy trong LAN, không qua Back4App.
  final P2pController p2p;

  /// Discovery behind [p2p]. Closed with the app.
  final PeerRepositoryImpl peerRepository;

  /// The receiving server and the sender behind [p2p]. Closed with the app.
  final TransferRepositoryImpl transferRepository;

  /// How the "Gửi tệp" tab reaches this machine's files.
  final P2pFiles p2pFiles;

  @override
  State<EventNoticeApp> createState() => _EventNoticeAppState();
}

class _EventNoticeAppState extends State<EventNoticeApp>
    with WidgetsBindingObserver {
  late final BackgroundService? _background =
      Platform.isAndroid ? BackgroundService() : null;
  late final RemindersController _reminders = widget.reminders;

  /// One "Đồng bộ ngay" and one timer cover everything the app keeps.
  late final SyncController _sync = widget.sync;

  /// The window and the tray icon, on desktop only.
  late final DesktopShell? _desktop =
      isDesktop ? DesktopShell(_reminders, _sync) : null;

  /// Which clipboard list is open and what is typed in its search box: the app
  /// bar and the floating button sit outside that tab but follow it.
  final ClipboardTabState _clipTab = ClipboardTabState();

  /// Last text pushed to the Android ongoing notification.
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _desktop?.attach();
    _start();
  }

  Future<void> _start() async {
    // Reads the auto-sync choice now, so the ⚙ menu shows it while the lists
    // below are still loading; start() reuses the same read.
    unawaited(_sync.load());
    // Only Android asks: elsewhere there is no OS alarm schedule.
    await _reminders.requestPermissions();
    await _reminders.init();
    // The sync engine reads the todos and the notes straight from their
    // repositories, so both files have to be loaded before the first cycle.
    await widget.todoRepository.init();
    await widget.todos.init();
    await widget.noteRepository.init();
    await widget.notes.init();
    await widget.clipboard.init();
    // Everything is loaded: from here edits push shortly after they happen,
    // and the first cycle starts without being waited for.
    await _sync.start();
    await widget.p2p.init();
    _reminders.addListener(_updateBackgroundStatus);
    await _startBackgroundService();
    // Opened by tapping an alarm notification: show that alert straight away.
    // Woken by a full-screen intent instead (no tap callback), the controller
    // asks what is ringing.
    await _reminders.showLaunchAlert();
  }

  Future<void> _startBackgroundService() async {
    await _background?.start(status: _reminders.nextAlertSummary());
  }

  /// Keeps the ongoing notification (Android) and the tray tooltip (Windows)
  /// showing what is coming up next.
  void _updateBackgroundStatus() {
    final deadline = _reminders.nearestDeadlineSummary();
    final summary = _reminders.nextAlertSummary();
    final status = deadline == null ? summary : '$summary\n$deadline';
    if (status == _lastStatus) return;
    _lastStatus = status;
    _background?.updateStatus(summary);
    _desktop?.showStatus(status);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The OS schedule holds a limited window of alerts; top it up on resume.
    _reminders.uiActive = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) _reminders.resync();
    if (state == AppLifecycleState.resumed) _sync.onAppActive();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reminders.removeListener(_updateBackgroundStatus);
    _desktop?.detach();
    // First, so no cycle starts on lists that are going away.
    _sync.dispose();
    widget.todos.dispose();
    widget.todoRepository.dispose();
    // The controller stops a tone still looping; then the ringer is released.
    _reminders.dispose();
    widget.reminderRepository.dispose();
    widget.alarmRinger.dispose();
    widget.notes.dispose();
    widget.noteRepository.dispose();
    widget.clipboard.dispose();
    widget.clipboardWatcher.dispose();
    widget.clipRepository.dispose();
    // Says goodbye and closes the port when transfer is on; then the network
    // repositories close their streams.
    widget.p2p.dispose();
    unawaited(widget.peerRepository.dispose());
    unawaited(widget.transferRepository.dispose());
    _clipTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // The stores outlive the widget tree here, so they are handed over as
        // values and disposed with this state, not by the providers.
        ChangeNotifierProvider<ClipboardController>.value(
          value: widget.clipboard,
        ),
        ChangeNotifierProvider<RemindersController>.value(value: _reminders),
        ChangeNotifierProvider<SyncController>.value(value: _sync),
        Provider<SyncSettings>.value(value: widget.syncSettings),
        ChangeNotifierProvider<ClipboardTabState>.value(value: _clipTab),
        ChangeNotifierProvider<NotesController>.value(value: widget.notes),
        ChangeNotifierProvider<TodosController>.value(value: widget.todos),
        ChangeNotifierProvider<P2pController>.value(value: widget.p2p),
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
      home: AlarmOverlay(
        reminders: _reminders,
        child: HomePage(
          todoReminderEditor: widget.todoReminderEditor,
          p2pFiles: widget.p2pFiles,
        ),
      ),
    );
  }
}
