import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

// No `default` branch: these only compile while the switches stay exhaustive,
// so adding a third Result variant or a fifth Failure breaks this file.
String describeResult(Result<int> result) => switch (result) {
      Ok(:final value) => 'ok $value',
      Err(:final failure) => 'err ${failure.message}',
    };

String describeFailure(Failure failure) => switch (failure) {
      StorageFailure() => 'storage',
      NetworkFailure() => 'network',
      ValidationFailure() => 'validation',
      UnexpectedFailure() => 'unexpected',
    };

void main() {
  group('Result', () {
    test('switch phủ hết Ok và Err', () {
      expect(describeResult(const Ok(3)), 'ok 3');
      expect(describeResult(const Err(StorageFailure('hỏng file'))),
          'err hỏng file');
    });

    test('Ok giữ giá trị, không có failure', () {
      const Result<int> result = Ok(7);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
    });

    test('Err giữ failure, không có giá trị', () {
      const Result<int> result = Err(NetworkFailure('mất mạng'));
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, const NetworkFailure('mất mạng'));
    });

    test('Ok<void> dùng được cho thao tác không trả gì', () {
      const Result<void> result = Ok(null);
      expect(result.isOk, isTrue);
    });

    test('so sánh bằng theo giá trị', () {
      expect(const Ok(1), const Ok(1));
      expect(const Ok(1), isNot(const Ok(2)));
      expect(const Err<int>(StorageFailure('a')),
          const Err<int>(StorageFailure('a')));
      expect(const Err<int>(StorageFailure('a')),
          isNot(const Err<int>(NetworkFailure('a'))));
    });
  });

  group('Failure', () {
    test('switch phủ hết bốn loại', () {
      expect(describeFailure(const StorageFailure('x')), 'storage');
      expect(describeFailure(const NetworkFailure('x')), 'network');
      expect(describeFailure(const ValidationFailure('x')), 'validation');
      expect(describeFailure(const UnexpectedFailure('x')), 'unexpected');
    });

    test('giữ lỗi gốc nhưng so sánh theo loại và message', () {
      final cause = Exception('io');
      final failure = StorageFailure('đọc notes.json', cause: cause);
      expect(failure.cause, same(cause));
      expect(failure, const StorageFailure('đọc notes.json'));
      expect(failure.hashCode, const StorageFailure('đọc notes.json').hashCode);
      expect(failure, isNot(const UnexpectedFailure('đọc notes.json')));
    });
  });
}
