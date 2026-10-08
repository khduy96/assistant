import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'countdown_card.dart';
import 'pomodoro_card.dart';

/// Cờ dòng lệnh: chạy app chỉ với một công cụ đồng hồ trong cửa sổ riêng.
const pomodoroFlag = '--pomodoro';
const countdownFlag = '--countdown';

final _isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Desktop: mở cửa sổ mới (một tiến trình riêng). Mobile: sang trang mới.
Future<void> _openTool(
    BuildContext context, String flag, Widget Function() page) async {
  if (!_isDesktop) {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page()));
    return;
  }
  try {
    await Process.start(Platform.resolvedExecutable, [flag],
        mode: ProcessStartMode.detached);
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không mở được cửa sổ mới: $e')));
  }
}

Future<void> openPomodoro(BuildContext context) =>
    _openTool(context, pomodoroFlag, () => const PomodoroPage());

Future<void> openCountdown(BuildContext context) =>
    _openTool(context, countdownFlag, () => const CountdownPage());

class _ToolPage extends StatelessWidget {
  const _ToolPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: child,
          ),
        ),
      ),
    );
  }
}

class PomodoroPage extends StatelessWidget {
  const PomodoroPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ToolPage(title: 'Pomodoro', child: PomodoroCard());
}

class CountdownPage extends StatelessWidget {
  const CountdownPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _ToolPage(title: 'Đếm ngược', child: CountdownCard());
}

/// Điểm vào của cửa sổ riêng trên desktop.
Future<void> runClockWindow(String flag) async {
  final countdown = flag == countdownFlag;
  final title = countdown ? 'Đếm ngược' : 'Pomodoro';
  await windowManager.ensureInitialized();
  final options = WindowOptions(
    size: countdown ? const Size(440, 520) : const Size(420, 380),
    minimumSize: const Size(340, 340),
    center: true,
    title: title,
    alwaysOnTop: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(MaterialApp(
    title: title,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB), brightness: Brightness.light),
    darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF60A5FA), brightness: Brightness.dark),
    home: countdown ? const CountdownPage() : const PomodoroPage(),
  ));
}
