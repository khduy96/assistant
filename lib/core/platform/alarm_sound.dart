import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef _PlaySoundNative = Int32 Function(
    Pointer<Utf16> sound, IntPtr module, Uint32 flags);
typedef _PlaySoundDart = int Function(
    Pointer<Utf16> sound, int module, int flags);

/// Loops the bundled alarm tone while an alert is on screen.
///
/// Uses winmm's PlaySound rather than an audio plugin: it loops a WAV natively
/// and needs no extra native build step.
class AlarmSound {
  static const _sndAsync = 0x0001;
  static const _sndNoDefault = 0x0002;
  static const _sndLoop = 0x0008;
  static const _sndPurge = 0x0040;
  static const _sndFilename = 0x00020000;

  _PlaySoundDart? _playSound;
  String? _soundPath;
  Pointer<Utf16>? _nativePath;
  bool _playing = false;

  _PlaySoundDart? _resolve() {
    if (!Platform.isWindows) return null;
    return _playSound ??= DynamicLibrary.open('winmm.dll')
        .lookupFunction<_PlaySoundNative, _PlaySoundDart>('PlaySoundW');
  }

  /// PlaySound needs a real file, so the asset is unpacked once into temp.
  Future<String> _soundFile() async {
    final cached = _soundPath;
    if (cached != null) return cached;
    final data = await rootBundle.load('assets/sounds/alarm.wav');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}event_notice_alarm.wav');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    return _soundPath = file.path;
  }

  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    final playSound = _resolve();
    if (playSound == null) {
      await SystemSound.play(SystemSoundType.alert);
      return;
    }
    try {
      final path = await _soundFile();
      // Kept alive until stop(): async playback reads the path after returning.
      final native = _nativePath = path.toNativeUtf16();
      playSound(native, 0, _sndFilename | _sndAsync | _sndLoop | _sndNoDefault);
    } catch (_) {
      _playing = false;
    }
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _resolve()?.call(nullptr, 0, _sndPurge);
    final native = _nativePath;
    if (native != null) {
      malloc.free(native);
      _nativePath = null;
    }
  }

  Future<void> dispose() => stop();
}
