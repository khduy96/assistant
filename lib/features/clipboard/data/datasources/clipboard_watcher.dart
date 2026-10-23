import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/domain/failure.dart';
import '../../../../core/domain/result.dart';
import '../../domain/ports/clipboard_source.dart';

/// [ClipboardSource] on the system clipboard: polls it for new text values
/// and writes clips back to it.
///
/// Polling is the only portable way to observe the clipboard across Windows,
/// macOS, Linux, Android and iOS without a platform plugin. On Android 10+ and
/// iOS the OS only serves clipboard data while the app is in the foreground,
/// so capture pauses automatically when the app is backgrounded.
///
/// Polling runs only while [captures] has a listener and capture is enabled.
class ClipboardWatcher with WidgetsBindingObserver implements ClipboardSource {
  ClipboardWatcher({this.interval = const Duration(milliseconds: 1200)}) {
    _captures = StreamController<String>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
  }

  final Duration interval;

  late final StreamController<String> _captures;
  Timer? _timer;
  String? _lastSeen;
  bool _busy = false;
  bool _enabled = true;
  bool _watching = false;

  @override
  Stream<String> get captures => _captures.stream;

  @override
  bool get isEnabled => _enabled;

  /// Turns capture on/off from the UI without tearing the watcher down.
  @override
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (enabled) {
      _resume();
    } else {
      _pause();
    }
  }

  @override
  Future<Result<void>> write(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      acknowledge(text);
      return const Ok(null);
    } catch (e) {
      return Err(UnexpectedFailure('Could not write the clipboard', cause: e));
    }
  }

  /// Marks a value as already known so copying from inside the app does not
  /// re-capture it as a brand new clip.
  void acknowledge(String content) => _lastSeen = content.trim();

  /// Stops polling and closes [captures].
  Future<void> dispose() async {
    _stop();
    await _captures.close();
  }

  void _start() {
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void _stop() {
    _watching = false;
    WidgetsBinding.instance.removeObserver(this);
    _pause();
  }

  void _resume() {
    _timer?.cancel();
    _timer = null;
    if (!_watching || !_enabled) return;
    _timer = Timer.periodic(interval, (_) => _poll());
    unawaited(_poll());
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_busy || !_enabled || !_watching) return;
    _busy = true;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || text == _lastSeen) return;
      // Stopped while reading: leave the value for the next listener.
      if (!_watching || _captures.isClosed) return;
      _lastSeen = text;
      _captures.add(text);
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
        _pause();
    }
  }
}
