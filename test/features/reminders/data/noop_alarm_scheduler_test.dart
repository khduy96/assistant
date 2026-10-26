import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/platform/alarm_sound.dart';
import 'package:event_notice/features/reminders/data/alarm_sound_ringer.dart';
import 'package:event_notice/features/reminders/data/noop_alarm_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the ringer asks of the sound.
class _FakeSound implements AlarmSound {
  final List<String> calls = [];

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

void main() {
  test(
    'NoopAlarmScheduler không chuông native, mọi câu trả lời rỗng',
    () async {
      const scheduler = NoopAlarmScheduler();
      expect(scheduler.ringsNatively, isFalse);
      expect(await scheduler.scheduleAll(const []), const Ok<void>(null));
      expect(await scheduler.stopRinging(), const Ok<void>(null));
      expect(await scheduler.ringingPayload(), const Ok<String?>(null));
      expect(await scheduler.launchPayload(), const Ok<String?>(null));
      expect(await scheduler.requestPermissions(), const Ok<void>(null));
      expect(await scheduler.canScheduleExactAlarms(), const Ok(false));
      expect(await scheduler.canDrawOverlays(), const Ok(false));
      expect(await scheduler.requestOverlayPermission(), const Ok<void>(null));
      expect(await scheduler.testRing(), const Ok<void>(null));
    },
  );

  test('AlarmSoundRinger chuyển thẳng sang AlarmSound', () async {
    final sound = _FakeSound();
    final ringer = AlarmSoundRinger(sound);
    await ringer.start();
    await ringer.stop();
    await ringer.dispose();
    expect(sound.calls, ['start', 'stop', 'dispose']);
  });
}
