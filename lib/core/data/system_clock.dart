import '../domain/clock.dart';

/// The real [Clock]: the device's local time.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
