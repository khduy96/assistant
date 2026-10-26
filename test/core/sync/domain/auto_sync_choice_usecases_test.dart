import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/core/sync/domain/sync_preferences.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SyncPreferences] kept in a field; throws [error] when it is set.
class _FakeSyncPreferences implements SyncPreferences {
  bool? stored;
  Object? error;

  @override
  Future<bool?> autoSync() async {
    if (error case final e?) throw e;
    return stored;
  }

  @override
  Future<void> setAutoSync(bool enabled) async {
    if (error case final e?) throw e;
    stored = enabled;
  }
}

void main() {
  late _FakeSyncPreferences preferences;

  setUp(() => preferences = _FakeSyncPreferences());

  group('GetAutoSyncChoice', () {
    test('chưa chọn bao giờ thì Ok(null)', () async {
      expect(
        await GetAutoSyncChoice(preferences)(const NoParams()),
        const Ok<bool?>(null),
      );
    });

    test('trả nguyên lựa chọn đã lưu', () async {
      preferences.stored = false;
      expect(
        await GetAutoSyncChoice(preferences)(const NoParams()),
        const Ok<bool?>(false),
      );
      preferences.stored = true;
      expect(
        await GetAutoSyncChoice(preferences)(const NoParams()),
        const Ok<bool?>(true),
      );
    });

    test('đọc lỗi thì Err(StorageFailure), không ném', () async {
      preferences.error = StateError('disk');
      final result = await GetAutoSyncChoice(preferences)(const NoParams());
      expect(result.failureOrNull, isA<StorageFailure>());
      expect(result.failureOrNull?.cause, isA<StateError>());
    });
  });

  group('SetAutoSyncChoice', () {
    test('ghi đúng giá trị và trả Ok', () async {
      final set = SetAutoSyncChoice(preferences);

      expect((await set(false)).isOk, isTrue);
      expect(preferences.stored, isFalse);
      expect((await set(true)).isOk, isTrue);
      expect(preferences.stored, isTrue);
    });

    test('ghi lỗi thì Err(StorageFailure), không ném', () async {
      preferences.error = StateError('disk');
      final result = await SetAutoSyncChoice(preferences)(true);
      expect(result.failureOrNull, isA<StorageFailure>());
      expect(result.failureOrNull?.cause, isA<StateError>());
      expect(preferences.stored, isNull);
    });
  });
}
