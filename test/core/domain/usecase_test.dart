import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedClock implements Clock {
  _FixedClock(this.at);
  final DateTime at;

  @override
  DateTime now() => at;
}

/// The shape every feature use case follows: one `call`, a Result back.
class _CurrentTime implements UseCase<DateTime, NoParams> {
  _CurrentTime(this._clock);
  final Clock _clock;

  @override
  Future<Result<DateTime>> call(NoParams params) async => Ok(_clock.now());
}

void main() {
  test('use case gọi qua call với NoParams và đọc giờ từ Clock giả', () async {
    final at = DateTime(2026, 10, 22, 8);
    final currentTime = _CurrentTime(_FixedClock(at));
    expect(await currentTime(const NoParams()), Ok(at));
  });
}
