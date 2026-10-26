import 'dart:math';

import '../../../core/domain/clock.dart';
import '../../../core/domain/id_generator.dart';

/// The [IdGenerator] for clips and groups: `<micro base36>-<rand base36>`,
/// the time of creation in microseconds then a random salt, the format these
/// ids already have on disk and on other devices.
class ClipIdGenerator implements IdGenerator {
  /// [random] replaces the salt source; tests pass a seeded one.
  ClipIdGenerator(this._clock, {Random? random}) : _random = random ?? Random();

  final Clock _clock;
  final Random _random;

  @override
  String newId() {
    final stamp = _clock.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = _random.nextInt(0x7fffffff).toRadixString(36);
    return '$stamp-$salt';
  }
}
