import 'dart:async';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/presentation/clipboard_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

void main() {
  late FakeClock clock;
  late FakeClipboardSource source;
  late InMemoryClipboardRepository repo;
  late ClipboardController controller;
  var disposed = false;
  var repaints = 0;

  /// Builds the controller over [clips] and [groups] and runs init.
  Future<void> start({
    List<ClipItem> clips = const [],
    List<({String id, String name})> groups = const [],
    InMemoryClipboardRepository? using,
  }) async {
    repo =
        using ??
        InMemoryClipboardRepository(
          clips: clips,
          groups: [for (final g in groups) clipGroup(g.id, name: g.name)],
        );
    controller = controllerFor(repo, source, clock: clock);
    disposed = false;
    await controller.init();
    repaints = 0;
    controller.addListener(() => repaints++);
  }

  void dispose() {
    if (disposed) return;
    disposed = true;
    controller.dispose();
  }

  List<String> ids(List<ClipItem> clips) => [for (final c in clips) c.id];

  setUp(() {
    clock = FakeClock(at(60));
    source = FakeClipboardSource();
  });

  tearDown(() async {
    dispose();
    source.dispose();
    await repo.dispose();
  });

  group('init', () {
    test(
      'xoá clip tạm quá 1 ngày, tải danh sách và bắt đầu ghi clipboard',
      () async {
        await start(
          clips: [
            clip('cu', createdMin: -24 * 60),
            clip('moi', createdMin: 30),
            clip('luu-cu', createdMin: -3 * 24 * 60, saved: true),
          ],
        );

        expect(controller.isLoading, isFalse);
        expect(ids(controller.tempClips), ['moi']);
        expect(ids(controller.savedClips), ['luu-cu']);
        // Dọn dẹp, không xin đẩy.
        expect(repo.log, ['deleteClips(cu)']);
        expect(source.watching, isTrue);
        expect(controller.captureEnabled, isTrue);
      },
    );

    test('chưa init thì đang tải; gọi init hai lần không nghe trùng', () async {
      repo = InMemoryClipboardRepository();
      controller = controllerFor(repo, source, clock: clock);
      disposed = false;
      expect(controller.isLoading, isTrue);

      await controller.init();
      // Luồng của nguồn giả chỉ cho một người nghe: nghe lần hai sẽ ném lỗi.
      await controller.init();
      expect(controller.isLoading, isFalse);
    });

    test('dispose thì thôi theo dõi clipboard', () async {
      await start();
      dispose();
      await pumpEventQueue();
      expect(source.watching, isFalse);
    });
  });

  group('capture', () {
    test(
      'nội dung mới thành clip tạm ở đầu danh sách, đã cắt khoảng trắng',
      () async {
        await start(clips: [clip('a', createdMin: 10)]);

        source.capture('  xin chào  ');
        await pumpEventQueue();

        expect(controller.tempClips.first.content, 'xin chào');
        expect(controller.tempClips.first.createdAt, at(60));
        expect(controller.tempCount, 2);
        expect(repaints, 1);
      },
    );

    test('nội dung đã có chỉ được đẩy lên đầu, không nhân đôi', () async {
      await start(
        clips: [
          clip('a', content: 'trùng', createdMin: 0),
          clip('b', createdMin: 10),
        ],
      );

      source.capture('trùng ');
      await pumpEventQueue();

      expect(ids(controller.tempClips), ['a', 'b']);
      expect(controller.tempClips.first.createdAt, at(60));
    });

    test('chuỗi rỗng bị bỏ qua', () async {
      await start();
      source.capture('   ');
      await pumpEventQueue();
      expect(controller.tempClips, isEmpty);
      expect(repaints, 0);
    });

    test('tắt ghi thì nguồn bị tắt', () async {
      await start();
      await controller.setCaptureEnabled(false);
      expect(source.isEnabled, isFalse);
      expect(controller.captureEnabled, isFalse);
      expect(repaints, 1);
    });
  });

  group('danh sách', () {
    test(
      'lọc theo nội dung hoặc ghi chú, không phân biệt hoa thường, và theo loại',
      () async {
        await start(
          clips: [
            clip('wifi', content: 'Mật khẩu WiFi nhà'),
            clip('ghi-chu', content: 'abc', note: 'wifi quán'),
            clip('link', content: 'https://wifi.example', type: ClipType.link),
            clip('khac', content: 'không liên quan'),
          ],
        );

        controller.setQuery('WIFI');
        expect(ids(controller.tempClips).toSet(), {'wifi', 'ghi-chu', 'link'});

        controller.setTypeFilter(ClipType.link);
        expect(ids(controller.tempClips), ['link']);
        expect(controller.query, 'WIFI');
        expect(controller.typeFilter, ClipType.link);

        // Đặt lại đúng giá trị cũ thì không vẽ lại.
        repaints = 0;
        controller
          ..setQuery('WIFI')
          ..setTypeFilter(ClipType.link);
        expect(repaints, 0);
      },
    );

    test('đã lưu xếp clip ghim trước rồi theo lần sửa gần nhất', () async {
      await start(
        clips: [
          clip('cu', saved: true, updatedMin: 1),
          clip('moi', saved: true, updatedMin: 5),
          clip('ghim', saved: true, pinned: true, updatedMin: 0),
          clip('nhom', saved: true, groupId: 'g', updatedMin: 3),
          clip('tam'),
        ],
        groups: [(id: 'g', name: 'Mã')],
      );

      expect(ids(controller.savedClips), ['ghim', 'moi', 'nhom', 'cu']);
      expect(ids(controller.pinnedClips), ['ghim']);
      expect(ids(controller.ungroupedSaved), ['ghim', 'moi', 'cu']);
      expect(ids(controller.clipsOfGroup('g')), ['nhom']);
      expect(controller.countOfGroup('g'), 1);
      expect(
        (controller.tempCount, controller.savedCount, controller.pinnedCount),
        (1, 4, 1),
      );
      expect(controller.groupById('g')?.name, 'Mã');
      expect(controller.groupById(null), isNull);
    });
  });

  group('thao tác một clip', () {
    test('ghim clip tạm thì clip được lưu', () async {
      await start(clips: [clip('a')]);

      expect(await controller.togglePin(controller.tempClips.single), isTrue);

      expect(controller.tempClips, isEmpty);
      expect(ids(controller.pinnedClips), ['a']);
      expect(controller.savedClips.single.isSaved, isTrue);
      expect(repaints, 1);
    });

    test(
      'bỏ lưu thì thành clip tạm, mất nhóm và xếp lịch xoá trên server',
      () async {
        await start(clips: [clip('a', saved: true, groupId: 'g')]);
        repo.remoteIds['a'] = 'r-a';

        expect(
          await controller.unsaveClip(controller.savedClips.single),
          isTrue,
        );

        final a = controller.tempClips.single;
        expect(a.groupId, isNull);
        expect(a.createdAt, at(60));
        expect(a.remaining(clock.now()), const Duration(days: 1));
        expect(repo.pendingDeletes, ['r-a']);
      },
    );

    test('copy đưa nội dung lên clipboard và đếm số lần dùng', () async {
      await start(clips: [clip('a', content: 'dán tôi')]);

      expect(
        await controller.copyToClipboard(controller.tempClips.single),
        isTrue,
      );

      expect(source.written, ['dán tôi']);
      expect(controller.tempClips.single.copyCount, 1);
    });

    test(
      'xoá rồi hoàn tác thì clip quay lại và lệnh xoá đang chờ bị huỷ',
      () async {
        await start(clips: [clip('a', saved: true)]);
        repo.remoteIds['a'] = 'r-a';
        final a = controller.savedClips.single;

        expect(await controller.deleteClip(a), isTrue);
        expect(controller.savedClips, isEmpty);
        expect(repo.pendingDeletes, ['r-a']);

        expect(await controller.restoreClip(a), isTrue);
        expect(ids(controller.savedClips), ['a']);
        expect(repo.pendingDeletes, isEmpty);
      },
    );

    test('xoá hết mục tạm thì giữ clip đã lưu', () async {
      await start(clips: [clip('t1'), clip('t2'), clip('s', saved: true)]);

      expect(await controller.clearTemp(), isTrue);

      expect(controller.tempClips, isEmpty);
      expect(ids(controller.savedClips), ['s']);
    });

    test('thêm tay thì clip vào thẳng danh sách lưu, đúng nhóm', () async {
      await start(groups: [(id: 'g', name: 'Mã')]);

      final added = await controller.addManual('  123456  ', groupId: 'g');

      expect(added?.content, '123456');
      expect(added?.type, ClipType.number);
      expect(ids(controller.clipsOfGroup('g')), [added!.id]);
      expect(repaints, 1);
    });

    test('sửa nội dung thì nhận lại loại', () async {
      await start(clips: [clip('a', saved: true)]);

      await controller.updateContent(
        controller.savedClips.single,
        'https://dart.dev',
      );

      expect(controller.savedClips.single.type, ClipType.link);
    });

    test(
      'làm việc trên bản đang lưu, không phải bản cũ người gọi giữ',
      () async {
        await start(clips: [clip('a', content: 'cũ', saved: true)]);
        final stale = controller.savedClips.single;
        // Một lượt sync thay nội dung.
        await repo.saveClip(stale.copyWith(content: 'mới từ máy khác'));
        repo.emitRemoteChange();
        await Future<void>.delayed(ClipboardController.syncReloadDelay * 2);

        await controller.togglePin(stale);

        expect(controller.pinnedClips.single.content, 'mới từ máy khác');
        expect(repo.clip('a')?.content, 'mới từ máy khác');
      },
    );
  });

  group('chọn nhiều', () {
    test(
      'copy nối theo thứ tự cũ nhất trước, mỗi clip một dòng, rồi bỏ chọn',
      () async {
        await start(
          clips: [
            clip('moi', content: 'ba', createdMin: 30),
            clip('cu', content: 'một', createdMin: 10),
            clip('giua', content: 'hai', createdMin: 20),
          ],
        );
        controller.selectAll(controller.tempClips);
        expect(controller.selectedCount, 3);

        expect(await controller.copySelected(), 3);

        expect(source.written, ['một\nhai\nba']);
        expect(controller.isSelecting, isFalse);
      },
    );

    test('ghim hàng loạt rồi bỏ ghim khi tất cả đã ghim', () async {
      await start(clips: [clip('a'), clip('b', saved: true)]);

      controller.selectAll(controller.tempClips + controller.savedClips);
      expect(await controller.togglePinSelected(), (2, true));
      expect(controller.pinnedCount, 2);

      controller.selectAll(controller.pinnedClips);
      expect(await controller.togglePinSelected(), (2, false));
      expect(controller.pinnedCount, 0);
      expect(controller.savedCount, 2);
    });

    test('bỏ lưu hàng loạt bỏ qua clip chưa lưu', () async {
      await start(clips: [clip('t'), clip('s', saved: true)]);
      controller
        ..toggleSelection('t')
        ..toggleSelection('s');

      expect(await controller.unsaveSelected(), 1);
      expect(controller.tempCount, 2);
    });

    test('lưu và đưa vào nhóm hàng loạt', () async {
      await start(
        clips: [clip('a'), clip('b')],
        groups: [(id: 'g', name: 'Mã')],
      );

      controller.toggleSelection('a');
      expect(await controller.saveSelected(), 1);
      expect(ids(controller.savedClips), ['a']);

      controller
        ..toggleSelection('a')
        ..toggleSelection('b');
      expect(await controller.assignGroupSelected('g'), 2);
      expect(controller.countOfGroup('g'), 2);
      expect(controller.savedCount, 2);
    });

    test('xoá hàng loạt trả về các clip đã xoá để hoàn tác', () async {
      await start(clips: [clip('a'), clip('b'), clip('c')]);
      controller
        ..toggleSelection('a')
        ..toggleSelection('c');

      final removed = await controller.deleteSelected();

      expect(ids(removed!).toSet(), {'a', 'c'});
      expect(ids(controller.tempClips), ['b']);
      expect(controller.isSelecting, isFalse);

      expect(await controller.restoreClips(removed), isTrue);
      expect(controller.tempCount, 3);
    });

    test('bấm lại một clip đã chọn thì bỏ chọn nó', () async {
      await start(clips: [clip('a')]);
      controller.toggleSelection('a');
      expect(controller.isSelected('a'), isTrue);
      controller.toggleSelection('a');
      expect(controller.isSelecting, isFalse);
      // Bỏ chọn khi không chọn gì thì không vẽ lại.
      repaints = 0;
      controller.clearSelection();
      expect(repaints, 0);
    });
  });

  group('nhóm', () {
    test('tạo nhóm ở cuối danh sách rồi đổi tên, đổi màu', () async {
      await start(groups: [(id: 'g', name: 'Mã')]);

      final created = await controller.createGroup('  Link  ', 0xFF00B894);
      expect(created?.name, 'Link');
      expect(created?.sortOrder, 1);
      expect([for (final g in controller.groups) g.name], ['Mã', 'Link']);

      final renamed = await controller.renameGroup(
        created!,
        'Liên kết',
        0xFFE17055,
      );
      expect(renamed?.color, 0xFFE17055);
      expect(controller.groupById(created.id)?.name, 'Liên kết');
    });

    test(
      'xoá nhóm thì giữ clip, clip vẫn được lưu và chưa phân nhóm',
      () async {
        await start(
          clips: [clip('a', saved: true, groupId: 'g')],
          groups: [(id: 'g', name: 'Mã')],
        );

        expect(await controller.deleteGroup(controller.groups.single), isTrue);

        expect(controller.groups, isEmpty);
        expect(controller.groupById('g'), isNull);
        expect(ids(controller.ungroupedSaved), ['a']);
        expect(repo.dirty, contains('a'));
      },
    );
  });

  group('lỗi', () {
    test(
      'thao tác lỗi thì trả về false, giữ danh sách và ghi lại lỗi',
      () async {
        await start(clips: [clip('a')]);
        const boom = StorageFailure('đĩa đầy');
        repo.failure = boom;

        expect(
          await controller.togglePin(controller.tempClips.single),
          isFalse,
        );

        expect(controller.failure, boom);
        expect(ids(controller.tempClips), ['a']);
      },
    );

    test('thao tác chọn nhiều lỗi thì trả về null và giữ lựa chọn', () async {
      await start(clips: [clip('a')]);
      controller.toggleSelection('a');
      repo.failure = const StorageFailure('đĩa đầy');

      expect(await controller.saveSelected(), isNull);
      expect(await controller.togglePinSelected(), isNull);
      expect(await controller.deleteSelected(), isNull);
      expect(controller.isSelected('a'), isTrue);
    });

    test('lần tải sau thành công thì xoá lỗi cũ', () async {
      await start(clips: [clip('a')]);
      repo.failure = const StorageFailure('đĩa đầy');
      await controller.togglePin(controller.tempClips.single);
      repo.failure = null;

      repo.emitRemoteChange();
      await Future<void>.delayed(ClipboardController.syncReloadDelay * 2);

      expect(controller.failure, isNull);
    });
  });

  group('sync và dọn dẹp', () {
    test('một lượt pull ghi nhiều clip thì chỉ tải lại một lần', () {
      fakeAsync((async) {
        unawaited(start());
        async.flushMicrotasks();

        for (var i = 0; i < 40; i++) {
          repo.saveClip(clip('keo-$i', saved: true, createdMin: i));
          repo.emitRemoteChange();
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(repaints, 0);

        async.elapse(ClipboardController.syncReloadDelay);
        expect(repaints, 1);
        expect(controller.savedCount, 40);
        dispose();
      });
    });

    test('sửa trên máy này thì không tải lại theo đường sync', () {
      fakeAsync((async) {
        unawaited(start());
        async.flushMicrotasks();

        unawaited(controller.addManual('gõ tay'));
        async.flushMicrotasks();
        async.elapse(ClipboardController.syncReloadDelay * 3);

        expect(repaints, 1);
        expect(controller.savedCount, 1);
        dispose();
      });
    });

    test('mỗi giờ dọn clip tạm đã hết hạn', () {
      fakeAsync((async) {
        unawaited(start(clips: [clip('a', createdMin: 60)]));
        async.flushMicrotasks();
        expect(controller.tempCount, 1);

        clock.current = at(60 + 24 * 60 + 1);
        async.elapse(ClipboardController.purgeInterval);

        expect(controller.tempCount, 0);
        expect(repaints, 1);
        dispose();
      });
    });

    test(
      'lượt tải đọc trước một thay đổi tại máy thì không đè mất thay đổi đó',
      () async {
        final gated = GatedClipboardRepository(clips: [clip('a', saved: true)]);
        await start(using: gated);

        // Một lượt sync làm danh sách tải lại; lượt tải bị giữ sau khi đọc.
        gated.gate = Completer<void>();
        repo.emitRemoteChange();
        await Future<void>.delayed(ClipboardController.syncReloadDelay * 2);

        final added = await controller.addManual('gõ tay');
        final release = gated.gate!;
        gated.gate = null;
        release.complete();
        await pumpEventQueue();

        expect(controller.savedClips.map((c) => c.id), contains(added!.id));
        expect(controller.savedCount, 2);
      },
    );
  });
}
