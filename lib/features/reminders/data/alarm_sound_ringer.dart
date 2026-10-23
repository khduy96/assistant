import '../../../core/platform/alarm_sound.dart';
import '../domain/ports/alarm_ringer.dart';

/// Plays the bundled alarm tone through [AlarmSound], looped while an alert
/// is on screen (desktop).
class AlarmSoundRinger implements AlarmRinger {
  AlarmSoundRinger([AlarmSound? sound]) : _sound = sound ?? AlarmSound();

  final AlarmSound _sound;

  @override
  Future<void> start() => _sound.start();

  @override
  Future<void> stop() => _sound.stop();

  @override
  Future<void> dispose() => _sound.dispose();
}
