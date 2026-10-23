import 'package:event_notice/app/di/injection.dart';
import 'package:event_notice/core/data/uuid_id_generator.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/core/sync/domain/sync_engine.dart';
import 'package:event_notice/features/clipboard/clipboard_injection.dart';
import 'package:event_notice/features/clipboard/data/clip_id_generator.dart';
import 'package:event_notice/features/clipboard/data/datasources/clip_local_data_source.dart';
import 'package:event_notice/features/clipboard/data/datasources/clipboard_watcher.dart';
import 'package:event_notice/features/clipboard/data/models/clip_model.dart';
import 'package:event_notice/features/clipboard/data/repositories/clipboard_repository_impl.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_group_sync_collection.dart';
import 'package:event_notice/features/clipboard/data/sync/clip_sync_collection.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/ports/clipboard_source.dart';
import 'package:event_notice/features/clipboard/domain/repositories/clipboard_repository.dart';
import 'package:event_notice/features/clipboard/domain/usecases/add_manual_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/capture_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_clips.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'data/clip_db.dart';
import 'domain/fakes.dart';

/// `<micro base36>-<rand base36>`, the id format clips and groups have on
/// disk and on other devices.
final clipIdFormat = RegExp(r'^[0-9a-z]+-[0-9a-z]+$');

Future<void> settle() => Future<void>.delayed(Duration.zero);

/// Waits, a few milliseconds at a time, until [done] holds: a capture runs
/// through a few SQLite round trips before the controller shows it.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  useFfiSqlite();

  late GetIt sl;
  late ClipDb db;
  late FakeClipboardSource source;

  setUp(() async {
    sl = GetIt.asNewInstance();
    db = await ClipDb.open();
    source = FakeClipboardSource();
  });

  tearDown(() async {
    await sl.reset();
    source.dispose();
    await db.close();
  });

  /// Points the clipboard at the throwaway database and the fake system
  /// clipboard; everything else stays as registered.
  void useTestDoubles() {
    sl
      ..unregister<ClipLocalDataSource>()
      ..registerLazySingleton(() => ClipLocalDataSource(db.db))
      ..unregister<ClipboardSource>()
      ..registerLazySingleton<ClipboardSource>(() => source);
  }

  group('configureDependencies', () {
    test('đăng ký đủ clipboard; id clip theo dạng cũ, id mặc định vẫn là '
        'UUID', () {
      configureDependencies(sl);
      final controller = sl<ClipboardController>();
      addTearDown(controller.dispose);

      expect(controller, isA<ClipboardController>());
      expect(sl<ClipGroupSyncCollection>().className, 'ClipGroup');
      expect(sl<ClipSyncCollection>().className, 'Clip');
      expect(sl<ClipboardSource>(), same(sl<ClipboardWatcher>()));
      expect(sl<IdGenerator>(), isA<UuidIdGenerator>());
      expect(
        sl<IdGenerator>(instanceName: clipIdsName),
        isA<ClipIdGenerator>(),
      );
    });

    test('kênh sync dùng đúng collection mà controller ghi vào: thêm clip '
        'thì engine thấy thay đổi local', () async {
      configureDependencies(sl);
      useTestDoubles();
      final engine = sl<SyncEngine>();
      final controller = sl<ClipboardController>();
      addTearDown(controller.dispose);
      var fired = 0;
      final sub = engine.localChanges.listen((_) => fired++);
      addTearDown(sub.cancel);
      await controller.init();

      final added = await controller.addManual('đẩy qua kênh chung');
      await settle();

      expect(added, isNotNull);
      expect(added!.id, matches(clipIdFormat));
      expect(fired, 1);
      expect(
        (await sl<ClipSyncCollection>().dirtyRecords()).single.localId,
        added.id,
      );
    });
  });

  group('registerClipboard', () {
    late FakeClock clock;

    setUp(() {
      clock = FakeClock(DateTime(2026, 10, 22, 9));
      sl
        ..registerSingleton<Clock>(clock)
        ..registerSingleton<IdGenerator>(SequentialIdGenerator());
      registerClipboard(sl);
      useTestDoubles();
    });

    test('một repository duy nhất, thấy dưới cả hai kiểu', () {
      expect(sl<ClipboardRepository>(), same(sl<ClipboardRepositoryImpl>()));
    });

    test('use case và collection là singleton', () {
      expect(sl<GetClips>(), same(sl<GetClips>()));
      expect(sl<CaptureClip>(), same(sl<CaptureClip>()));
      expect(sl<AddManualClip>(), same(sl<AddManualClip>()));
      expect(sl<ClipSyncCollection>(), same(sl<ClipSyncCollection>()));
      expect(
        sl<ClipGroupSyncCollection>(),
        same(sl<ClipGroupSyncCollection>()),
      );
    });

    test('mỗi lần lấy controller là một controller mới', () {
      final a = sl<ClipboardController>();
      final b = sl<ClipboardController>();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a, isNot(same(b)));
    });

    test('clip bắt được, clip gõ tay và nhóm mới dùng id dạng cũ, không dùng '
        'IdGenerator mặc định', () async {
      final controller = sl<ClipboardController>();
      addTearDown(controller.dispose);
      await controller.init();

      source.capture('copy tự động');
      await until(() => controller.tempClips.isNotEmpty);
      final manual = await controller.addManual('gõ tay');
      final group = await controller.createGroup('Công việc', 0xFF5B8DEF);

      expect(controller.tempClips.single.id, matches(clipIdFormat));
      expect(manual!.id, matches(clipIdFormat));
      expect(group!.id, matches(clipIdFormat));
      expect(sl<IdGenerator>().newId(), 'id-1');
    });

    group('thao tác qua controller và collection đã đăng ký', () {
      late ClipboardController controller;
      late int clipPushes;
      late int groupPushes;
      late int remoteChanges;

      setUp(() async {
        controller = sl<ClipboardController>();
        clipPushes = 0;
        groupPushes = 0;
        remoteChanges = 0;
        final subs = [
          sl<ClipSyncCollection>().localChanges.listen((_) => clipPushes++),
          sl<ClipGroupSyncCollection>().localChanges.listen(
            (_) => groupPushes++,
          ),
          sl<ClipboardRepository>().remoteChanges.listen(
            (_) => remoteChanges++,
          ),
        ];
        addTearDown(() async {
          controller.dispose();
          for (final sub in subs) {
            await sub.cancel();
          }
        });
      });

      test('clip tạm mới và lần copy không cần đẩy', () async {
        await controller.init();
        source.capture('copy tự động');
        await until(() => controller.tempClips.isNotEmpty);

        final temp = controller.tempClips.single;
        expect(await controller.copyToClipboard(temp), isTrue);
        await settle();

        expect(source.written, ['copy tự động']);
        expect(clipPushes, 0);
        expect(groupPushes, 0);
      });

      test('copy lại nội dung của clip đã lưu thì cần đẩy', () async {
        await controller.init();
        await controller.addManual('đã lưu');
        source.capture('đã lưu');
        await until(() => clipPushes >= 2);

        expect(controller.savedClips, hasLength(1));
        expect(clipPushes, 2);
      });

      test('sửa của người dùng thì cần đẩy, không báo như sync', () async {
        await controller.init();
        final item = (await controller.addManual('a'))!;
        expect(await controller.togglePin(item), isTrue);
        final pinned = controller.pinnedClips.single;
        expect(await controller.deleteClip(pinned), isTrue);
        expect(await controller.restoreClip(pinned), isTrue);
        final group = (await controller.createGroup('G', 0xFF5B8DEF))!;
        expect(await controller.deleteGroup(group), isTrue);
        await settle();

        expect(clipPushes, 4);
        expect(groupPushes, 2);
        expect(remoteChanges, 0);
      });

      test('thao tác do sync áp vào không cần đẩy, controller tải lại sau '
          'một nhịp', () async {
        await controller.init();
        final item = (await controller.addManual('a'))!;
        await settle();
        clipPushes = 0;
        final clips = sl<ClipSyncCollection>();

        await clips.markSynced(item.id, 'obj-a');
        await clips.applyRemote({
          'objectId': 'obj-b',
          'localId': 'b',
          'content': 'từ máy kia',
          'clipCreatedAt': 1,
          'clipUpdatedAt': 1,
          'isSaved': true,
        });
        await settle();
        expect(controller.savedCount, 1);

        await Future<void>.delayed(ClipboardController.syncReloadDelay * 3);
        expect(controller.savedCount, 2);

        await clips.removeLocalOnly('b');
        await settle();

        expect(remoteChanges, 3);
        expect(clipPushes, 0);
        expect(groupPushes, 0);
      });

      test('dọn clip tạm hết hạn lúc khởi động không cần đẩy', () async {
        final old = clock.now().subtract(const Duration(days: 2));
        await (await db.raw).insert(
          'clips',
          ClipModel(
            id: 'het-han',
            content: 'cũ',
            type: ClipType.text,
            createdAt: old,
            updatedAt: old,
          ).toMap(),
        );

        await controller.init();
        await settle();

        expect(controller.tempClips, isEmpty);
        expect(await (await db.raw).query('clips'), isEmpty);
        expect(clipPushes, 0);
      });
    });
  });
}
