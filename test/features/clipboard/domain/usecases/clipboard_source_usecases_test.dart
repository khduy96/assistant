import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/usecases/capture_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_capture_enabled.dart';
import 'package:event_notice/features/clipboard/domain/usecases/set_capture_enabled.dart';
import 'package:event_notice/features/clipboard/domain/usecases/watch_captured_clips.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

final _now = DateTime(2026, 10, 22, 14, 30);

void main() {
  late FakeClipboardSource source;
  late InMemoryClipboardRepository repo;
  late WatchCapturedClips watch;

  setUp(() {
    source = FakeClipboardSource();
    repo = InMemoryClipboardRepository();
    watch = WatchCapturedClips(
      source,
      CaptureClip(repo, SequentialIdGenerator(), FakeClock(_now)),
    );
  });

  tearDown(() async {
    source.dispose();
    await repo.dispose();
  });

  /// Lets the capture pipeline run until nothing is left to do.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('WatchCapturedClips', () {
    test('chỉ theo dõi clipboard khi có người nghe', () async {
      final stream = (await watch(const NoParams())).valueOrNull!;
      expect(source.watching, isFalse);

      final sub = stream.listen((_) {});
      await settle();
      expect(source.watching, isTrue);

      await sub.cancel();
      expect(source.watching, isFalse);
    });

    test('mỗi giá trị mới thành một clip tạm đã lưu', () async {
      final seen = <Result<ClipItem>>[];
      final sub = (await watch(const NoParams())).valueOrNull!.listen(seen.add);

      source.capture('https://a.vn');
      await settle();

      expect(seen, hasLength(1));
      final clip = seen.single.valueOrNull!;
      expect(clip.content, 'https://a.vn');
      expect(clip.type, ClipType.link);
      expect(clip.isTemp, isTrue);
      expect(repo.clip(clip.id), clip);
      await sub.cancel();
    });

    test(
      'xử lý lần lượt: hai lần copy cùng nội dung chỉ ra một clip',
      () async {
        final seen = <ClipItem>[];
        final sub = (await watch(
          const NoParams(),
        )).valueOrNull!.listen((r) => seen.add(r.valueOrNull!));

        source
          ..capture('abc')
          ..capture('  abc ')
          ..capture('xyz');
        for (var i = 0; i < 5; i++) {
          await settle();
        }

        expect([for (final c in seen) c.content], ['abc', 'abc', 'xyz']);
        expect(seen[0].id, seen[1].id);
        expect(repo.clips, hasLength(2));
        await sub.cancel();
      },
    );

    test(
      'giá trị trống bị bỏ qua, lỗi được báo mà vẫn theo dõi tiếp',
      () async {
        final seen = <Result<ClipItem>>[];
        final sub = (await watch(
          const NoParams(),
        )).valueOrNull!.listen(seen.add);

        source.capture('   ');
        await settle();
        expect(seen, isEmpty);

        repo.failure = const StorageFailure('disk');
        source.capture('abc');
        await settle();
        expect(seen, [const Err<ClipItem>(StorageFailure('disk'))]);

        repo.failure = null;
        source.capture('abc');
        await settle();
        expect(seen, hasLength(2));
        expect(seen.last.valueOrNull!.content, 'abc');
        await sub.cancel();
      },
    );
  });

  test('bật/tắt bắt clipboard', () async {
    expect(
      await GetCaptureEnabled(source)(const NoParams()),
      const Ok<bool>(true),
    );

    expect(await SetCaptureEnabled(source)(false), const Ok<void>(null));
    expect(source.isEnabled, isFalse);
    expect(
      await GetCaptureEnabled(source)(const NoParams()),
      const Ok<bool>(false),
    );

    await SetCaptureEnabled(source)(true);
    expect(source.isEnabled, isTrue);
  });
}
