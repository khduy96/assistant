import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

/// Polls the system clipboard and reports new text values.
///
/// Polling is the only portable way to observe the clipboard across Windows,
/// macOS, Linux, Android and iOS without a platform plugin. On Android 10+ and
/// iOS the OS only serves clipboard data while the app is in the foreground,
/// so capture pauses automatically when the app is backgrounded.
class ClipboardWatcher with WidgetsBindingObserver {
  ClipboardWatcher({
    required this.onCapture,
    this.interval = const Duration(milliseconds: 1200),
  });

  final Future<void> Function(String content) onCapture;
  final Duration interval;

  Timer? _timer;
  String? _lastSeen;
  bool _busy = false;
  bool _enabled = true;

  bool get isEnabled => _enabled;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  /// Turns capture on/off from the UI without tearing the watcher down.
  void setEnabled(bool value) {
    _enabled = value;
    if (value) {
      _resume();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Marks a value as already known so copying from inside the app does not
  /// re-capture it as a brand new clip.
  void acknowledge(String content) => _lastSeen = content.trim();

  void _resume() {
    _timer?.cancel();
    if (!_enabled) return;
    _timer = Timer.periodic(interval, (_) => _poll());
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_busy || !_enabled) return;
    _busy = true;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || text == _lastSeen) return;
      _lastSeen = text;
      await onCapture(text);
    } catch (error, stack) {
      debugPrint('Clipboard poll failed: $error\n$stack');
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _resume();
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _timer?.cancel();
        _timer = null;
    }
  }
}
