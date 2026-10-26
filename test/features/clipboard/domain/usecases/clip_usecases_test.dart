import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/clipboard/domain/entities/clip_item.dart';
import 'package:event_notice/features/clipboard/domain/usecases/add_manual_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/assign_clip_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/assign_clips_group.dart';
import 'package:event_notice/features/clipboard/domain/usecases/capture_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/clear_temp_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/copy_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/copy_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/delete_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/get_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/purge_expired_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/restore_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/restore_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/save_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/save_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/toggle_clip_pin.dart';
import 'package:event_notice/features/clipboard/domain/usecases/toggle_clips_pin.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clip.dart';
import 'package:event_notice/features/clipboard/domain/usecases/unsave_clips.dart';
import 'package:event_notice/features/clipboard/domain/usecases/update_clip_content.dart';
import 'package:event_notice/features/clipboard/domain/usecases/watch_remote_clip_changes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// The fixed "now" of every test: 22/10/2026 14:30.
final _now = DateTime(2026, 10, 22, 14, 30);

DateTime _ago(Duration d) => _now.subtract(d);

ClipItem _clip(
  String id, {
  String? content,
  bool saved = false,
  bool pinned = false,
  String? groupId,
  String? note,
  int copyCount = 0,
  DateTime? created,
  DateTime? updated,
}) {
  final at = created ?? _ago(const Duration(hours: 1));
  return ClipItem(
    id: id,
    content: content ?? id,
    type: ClipType.text,
    createdAt: at,
    updatedAt: updated ?? at,
    isSaved: saved,
    isPinned: pinned,
    groupId: groupId,
    note: note,
    copyCount: copyCount,
  );
}

List<String> _ids(Iterable<ClipItem> clips) => [for (final c in clips) c.id];

void main() {
  const storageFailure = StorageFailure('disk');
  late FakeClock clock;
  late SequentialIdGenerator ids;

  setUp(() {
    clock = FakeClock(_now);
    ids = SequentialIdGenerator();
  });

  group('GetClips', () {
    test('mới nhất trước', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('mid', created: _ago(const Duration(hours: 2))),
          _clip('new', created: _ago(const Duration(minutes: 1))),
          _clip('old', created: _ago(const Duration(days: 3)), saved: true),
        ],
      );

      final result = await GetClips(repo)(const NoParams());

      expect(_ids(result.valueOrNull!), ['new', 'mid', 'old']);
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryClipboardRepository()..failure = storageFailure;
      expect(
        await GetClips(repo)(const NoParams()),
        const Err<List<ClipItem>>(storageFailure),
      );
    });
  });

  group('CaptureClip', () {
    test(
      'nội dung mới thành clip tạm, đã cắt khoảng trắng, không xin đẩy',
      () async {
        final repo = InMemoryClipboardRepository();

        final result = await CaptureClip(repo, ids, clock)('  https://a.vn \n');

        final clip = result.valueOrNull!;
        expect(clip.id, 'id-1');
        expect(clip.content, 'https://a.vn');
        expect(clip.type, ClipType.link);
        expect(clip.isTemp, isTrue);
        expect(clip.createdAt, _now);
        expect(clip.updatedAt, _now);
        expect(repo.clip('id-1'), clip);
        expect(repo.log, ['saveClip(id-1)']);
        expect(repo.pushRequests, 0);
      },
    );

    test('nội dung đã có (sau khi cắt khoảng trắng) chỉ đẩy bản cũ lên đầu; '
        'clip tạm được đặt lại createdAt', () async {
      final old = _clip(
        'c1',
        content: 'abc',
        created: _ago(const Duration(hours: 20)),
      );
      final repo = InMemoryClipboardRepository(clips: [old]);

      final result = await CaptureClip(repo, ids, clock)('  abc\n');

      final clip = result.valueOrNull!;
      expect(clip.id, 'c1');
      expect(clip.createdAt, _now);
      expect(clip.updatedAt, _now);
      expect(clip.copiedAt, _now);
      expect(clip.remaining(_now), const Duration(days: 1));
      expect(repo.clips, hasLength(1));
      expect(repo.log, ['saveClip(c1)']);
      expect(repo.pushRequests, 0);

      final list = await GetClips(repo)(const NoParams());
      expect(_ids(list.valueOrNull!).first, 'c1');
    });

    test('clip đã lưu bị copy lại thì giữ createdAt và xin đẩy', () async {
      final created = _ago(const Duration(days: 5));
      final repo = InMemoryClipboardRepository(
        clips: [_clip('c1', content: 'abc', saved: true, created: created)],
      );

      final clip = (await CaptureClip(repo, ids, clock)('abc')).valueOrNull!;

      expect(clip.createdAt, created);
      expect(clip.updatedAt, _now);
      expect(clip.copiedAt, _now);
      expect(clip.isSaved, isTrue);
      expect(repo.log, ['saveClip(c1, share)']);
    });

    test('chuỗi rỗng hoặc toàn khoảng trắng bị bỏ qua', () async {
      final repo = InMemoryClipboardRepository();
      final capture = CaptureClip(repo, ids, clock);

      expect(await capture(''), const Ok<ClipItem?>(null));
      expect(await capture(' \n\t '), const Ok<ClipItem?>(null));
      expect(repo.log, isEmpty);
    });

    test('lỗi của repository được trả lại, không ghi gì', () async {
      final repo = InMemoryClipboardRepository()..failure = storageFailure;
      expect(
        await CaptureClip(repo, ids, clock)('abc'),
        const Err<ClipItem?>(storageFailure),
      );
      expect(repo.log, isEmpty);
    });
  });

  group('PurgeExpiredClips', () {
    test('chỉ xoá clip tạm cũ hơn 1 ngày, không xin đẩy', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('expired', created: _ago(const Duration(hours: 25))),
          _clip('edge', created: _ago(const Duration(days: 1))),
          _clip('fresh', created: _ago(const Duration(hours: 1))),
          _clip('saved', saved: true, created: _ago(const Duration(days: 3))),
          _clip('pinned', pinned: true, created: _ago(const Duration(days: 3))),
        ],
      );
      repo.remoteIds['expired'] = 'r-expired';

      final result = await PurgeExpiredClips(repo, clock)(const NoParams());

      expect(result, const Ok(1));
      expect(repo.clip('expired'), isNull);
      expect(
        _ids(repo.clips),
        unorderedEquals(['edge', 'fresh', 'saved', 'pinned']),
      );
      expect(repo.log, ['deleteClips(expired)']);
      expect(repo.pushRequests, 0);
      expect(repo.pendingDeletes, ['r-expired']);
    });

    test(
      'đếm theo đồng hồ: clip vừa đúng 1 ngày sẽ bị xoá ở lần sau',
      () async {
        final repo = InMemoryClipboardRepository(
          clips: [_clip('edge', created: _ago(const Duration(days: 1)))],
        );
        final purge = PurgeExpiredClips(repo, clock);

        expect(await purge(const NoParams()), const Ok(0));
        clock.current = _now.add(const Duration(milliseconds: 1));
        expect(await purge(const NoParams()), const Ok(1));
      },
    );

    test('không có clip hết hạn thì không ghi gì', () async {
      final repo = InMemoryClipboardRepository(clips: [_clip('fresh')]);
      expect(
        await PurgeExpiredClips(repo, clock)(const NoParams()),
        const Ok(0),
      );
      expect(repo.log, isEmpty);
    });
  });

  group('ghim và gán nhóm', () {
    test('ghim clip tạm thì clip được lưu', () async {
      final repo = InMemoryClipboardRepository(clips: [_clip('c1')]);

      final clip = (await ToggleClipPin(repo, clock)(
        repo.clip('c1')!,
      )).valueOrNull!;

      expect(clip.isPinned, isTrue);
      expect(clip.isSaved, isTrue);
      expect(clip.isTemp, isFalse);
      expect(clip.updatedAt, _now);
      expect(repo.clip('c1'), clip);
      expect(repo.log, ['saveClip(c1, share)']);
    });

    test('bỏ ghim vẫn giữ clip trong danh sách đã lưu', () async {
      final repo = InMemoryClipboardRepository(
        clips: [_clip('c1', saved: true, pinned: true)],
      );

      final clip = (await ToggleClipPin(repo, clock)(
        repo.clip('c1')!,
      )).valueOrNull!;

      expect(clip.isPinned, isFalse);
      expect(clip.isSaved, isTrue);
    });

    test('gán nhóm cho clip tạm thì clip được lưu', () async {
      final repo = InMemoryClipboardRepository(clips: [_clip('c1')]);

      final clip = (await AssignClipGroup(repo, clock)((
        clip: repo.clip('c1')!,
        groupId: 'g1',
      ))).valueOrNull!;

      expect(clip.groupId, 'g1');
      expect(clip.isSaved, isTrue);
      expect(clip.updatedAt, _now);
      expect(repo.log, ['saveClip(c1, share)']);
    });

    test('bỏ nhóm giữ nguyên trạng thái lưu', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('saved', saved: true, groupId: 'g1'),
          _clip('temp'),
        ],
      );
      final assign = AssignClipGroup(repo, clock);

      final saved = (await assign((
        clip: repo.clip('saved')!,
        groupId: null,
      ))).valueOrNull!;
      final temp = (await assign((
        clip: repo.clip('temp')!,
        groupId: null,
      ))).valueOrNull!;

      expect(saved.groupId, isNull);
      expect(saved.isSaved, isTrue);
      expect(temp.isTemp, isTrue);
    });

    test('ghim nhiều: ghim hết, trừ khi tất cả đã ghim thì bỏ ghim', () async {
      final repo = InMemoryClipboardRepository(
        clips: [_clip('a', saved: true, pinned: true), _clip('b')],
      );
      final toggle = ToggleClipsPin(repo, clock);

      final first = (await toggle([
        repo.clip('a')!,
        repo.clip('b')!,
      ])).valueOrNull!;
      expect(first.pinned, isTrue);
      expect(_ids(first.clips), ['a', 'b']);
      expect(repo.clip('b')!.isPinned, isTrue);
      expect(repo.clip('b')!.isSaved, isTrue);

      final second = (await toggle([
        repo.clip('a')!,
        repo.clip('b')!,
      ])).valueOrNull!;
      expect(second.pinned, isFalse);
      expect(repo.clip('a')!.isPinned, isFalse);
      expect(repo.clip('b')!.isPinned, isFalse);
      expect(repo.clip('b')!.isSaved, isTrue);
    });

    test('ghim nhiều với danh sách rỗng không ghi gì', () async {
      final repo = InMemoryClipboardRepository();
      final result = (await ToggleClipsPin(repo, clock)([])).valueOrNull!;
      expect(result.clips, isEmpty);
      expect(result.pinned, isFalse);
      expect(repo.log, isEmpty);
    });

    test('gán nhóm nhiều clip', () async {
      final repo = InMemoryClipboardRepository(
        clips: [_clip('a'), _clip('b', saved: true)],
      );

      final result = await AssignClipsGroup(repo, clock)((
        clips: [repo.clip('a')!, repo.clip('b')!],
        groupId: 'g1',
      ));

      expect(_ids(result.valueOrNull!), ['a', 'b']);
      expect(repo.clip('a')!.groupId, 'g1');
      expect(repo.clip('a')!.isSaved, isTrue);
      expect(repo.clip('b')!.groupId, 'g1');
      expect(repo.pushRequests, 2);
    });
  });

  group('lưu và bỏ lưu', () {
    test('lưu clip tạm, groupId null thì giữ nhóm cũ', () async {
      final repo = InMemoryClipboardRepository(clips: [_clip('c1')]);

      final clip = (await SaveClip(repo, clock)((
        clip: repo.clip('c1')!,
        groupId: null,
      ))).valueOrNull!;

      expect(clip.isSaved, isTrue);
      expect(clip.updatedAt, _now);
      expect(repo.log, ['saveClip(c1, share)']);
    });

    test('lưu nhiều clip vào một nhóm', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('a'),
          _clip('b', saved: true, groupId: 'g0'),
        ],
      );

      final result = await SaveClips(repo, clock)((
        clips: [repo.clip('a')!, repo.clip('b')!],
        groupId: 'g1',
      ));

      expect(_ids(result.valueOrNull!), ['a', 'b']);
      expect(repo.clip('a')!.isSaved, isTrue);
      expect(repo.clip('a')!.groupId, 'g1');
      expect(repo.clip('b')!.groupId, 'g1');
    });

    test('bỏ lưu: thành clip tạm, mất nhóm, mất remoteId, xếp lịch xoá '
        'trên server và đếm lại 1 ngày', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip(
            'c1',
            saved: true,
            pinned: true,
            groupId: 'g1',
            created: _ago(const Duration(days: 30)),
          ),
        ],
      );
      repo.remoteIds['c1'] = 'r1';

      final clip = (await UnsaveClip(repo, clock)(
        repo.clip('c1')!,
      )).valueOrNull!;

      expect(clip.isTemp, isTrue);
      expect(clip.isSaved, isFalse);
      expect(clip.isPinned, isFalse);
      expect(clip.groupId, isNull);
      expect(clip.createdAt, _now);
      expect(clip.updatedAt, _now);
      expect(clip.remaining(_now), const Duration(days: 1));
      expect(repo.clip('c1'), clip);
      // Taken off the server first, then stored as an edit.
      expect(repo.log, ['detachFromServer(c1)', 'saveClip(c1, share)']);
      expect(repo.remoteIds, isNot(contains('c1')));
      expect(repo.pendingDeletes, ['r1']);

      // The new countdown runs from the unsave, not from the old createdAt.
      final purge = PurgeExpiredClips(repo, clock);
      clock.current = _now.add(const Duration(hours: 23));
      expect(await purge(const NoParams()), const Ok(0));
      clock.current = _now.add(const Duration(hours: 25));
      expect(await purge(const NoParams()), const Ok(1));
    });

    test('bỏ lưu: không tách khỏi server được thì không ghi clip', () async {
      final repo = InMemoryClipboardRepository(
        clips: [_clip('c1', saved: true)],
      )..failure = storageFailure;

      expect(
        await UnsaveClip(repo, clock)(_clip('c1', saved: true)),
        const Err<ClipItem>(storageFailure),
      );
      expect(repo.log, isEmpty);
    });

    test('bỏ lưu nhiều: bỏ qua clip chưa lưu', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('a', saved: true),
          _clip('temp'),
          _clip('b', saved: true),
        ],
      );
      repo.remoteIds['b'] = 'rb';

      final result = await UnsaveClips(repo, clock)([
        repo.clip('a')!,
        repo.clip('temp')!,
        repo.clip('b')!,
      ]);

      expect(_ids(result.valueOrNull!), ['a', 'b']);
      expect(repo.clip('a')!.isTemp, isTrue);
      expect(repo.clip('b')!.isTemp, isTrue);
      expect(repo.log, [
        'detachFromServer(a)',
        'saveClip(a, share)',
        'detachFromServer(b)',
        'saveClip(b, share)',
      ]);
      expect(repo.pendingDeletes, ['rb']);
    });
  });

  group('sửa nội dung và thêm tay', () {
    test(
      'sửa nội dung: cắt khoảng trắng, nhận diện lại loại, giữ ghi chú',
      () async {
        final repo = InMemoryClipboardRepository(
          clips: [_clip('c1', saved: true, note: 'ghi chú')],
        );

        final clip = (await UpdateClipContent(repo, clock)((
          clip: repo.clip('c1')!,
          content: '  me@example.com ',
          note: null,
        ))).valueOrNull!;

        expect(clip.content, 'me@example.com');
        expect(clip.type, ClipType.email);
        expect(clip.note, 'ghi chú');
        expect(clip.updatedAt, _now);
        expect(repo.log, ['saveClip(c1, share)']);
      },
    );

    test('sửa nội dung kèm ghi chú mới', () async {
      final repo = InMemoryClipboardRepository(clips: [_clip('c1', note: 'a')]);

      final clip = (await UpdateClipContent(repo, clock)((
        clip: repo.clip('c1')!,
        content: 'x',
        note: 'b',
      ))).valueOrNull!;

      expect(clip.note, 'b');
    });

    test('thêm tay: vào thẳng danh sách đã lưu, có nhóm nếu truyền', () async {
      final repo = InMemoryClipboardRepository();

      final clip = (await AddManualClip(repo, ids, clock)((
        content: '  #FF00AA  ',
        groupId: 'g1',
      ))).valueOrNull!;

      expect(clip.id, 'id-1');
      expect(clip.content, '#FF00AA');
      expect(clip.type, ClipType.color);
      expect(clip.isSaved, isTrue);
      expect(clip.isPinned, isFalse);
      expect(clip.groupId, 'g1');
      expect(clip.createdAt, _now);
      expect(clip.updatedAt, _now);
      expect(repo.log, ['saveClip(id-1, share)']);
    });
  });

  group('xoá và hoàn tác', () {
    test('xoá rồi hoàn tác thì huỷ lệnh xoá đang chờ trên server', () async {
      final original = _clip('c1', saved: true, groupId: 'g1', copyCount: 4);
      final repo = InMemoryClipboardRepository(clips: [original]);
      repo.remoteIds['c1'] = 'r1';

      expect(await DeleteClip(repo)(original), const Ok<void>(null));
      expect(repo.clip('c1'), isNull);
      expect(repo.pendingDeletes, ['r1']);

      clock.current = _now.add(const Duration(seconds: 5));
      final restored = (await RestoreClip(repo, clock)(original)).valueOrNull!;

      expect(restored, original.copyWith(updatedAt: clock.current));
      expect(repo.clip('c1'), restored);
      expect(repo.pendingDeletes, isEmpty);
      expect(repo.remoteIds['c1'], 'r1');
      expect(repo.dirty, contains('c1'));
      expect(repo.log, ['deleteClips(c1, share)', 'restoreClip(c1, share)']);
    });

    test('xoá nhiều trong một lần ghi, hoàn tác đưa lại đủ', () async {
      final a = _clip('a', saved: true);
      final b = _clip('b');
      final repo = InMemoryClipboardRepository(clips: [a, b, _clip('keep')]);
      repo.remoteIds['a'] = 'ra';

      final removed = (await DeleteClips(repo)([a, b])).valueOrNull!;
      expect(removed, [a, b]);
      expect(_ids(repo.clips), ['keep']);
      expect(repo.log, ['deleteClips(a b, share)']);
      expect(repo.pendingDeletes, ['ra']);

      final restored = (await RestoreClips(repo, clock)(removed)).valueOrNull!;
      expect(_ids(restored), ['a', 'b']);
      expect(restored.every((c) => c.updatedAt == _now), isTrue);
      expect(_ids(repo.clips), unorderedEquals(['a', 'b', 'keep']));
      expect(repo.pendingDeletes, isEmpty);
    });

    test('xoá nhiều với danh sách rỗng không ghi gì', () async {
      final repo = InMemoryClipboardRepository();
      expect((await DeleteClips(repo)([])).valueOrNull, isEmpty);
      expect(repo.log, isEmpty);
    });

    test('xoá clip tạm: giữ clip đã lưu và đã ghim', () async {
      final repo = InMemoryClipboardRepository(
        clips: [
          _clip('t1'),
          _clip('t2'),
          _clip('saved', saved: true),
          _clip('pinned', saved: true, pinned: true),
        ],
      );

      final result = await ClearTempClips(repo)(const NoParams());

      expect(result, const Ok(2));
      expect(_ids(repo.clips), unorderedEquals(['saved', 'pinned']));
      expect(repo.log, ['deleteClips(t1 t2, share)']);
    });

    test('xoá clip tạm khi không có clip tạm thì không ghi gì', () async {
      final repo = InMemoryClipboardRepository(
        clips: [_clip('saved', saved: true)],
      );
      expect(await ClearTempClips(repo)(const NoParams()), const Ok(0));
      expect(repo.log, isEmpty);
    });
  });

  group('copy', () {
    test('copy một clip: đặt lên clipboard, chỉ ghi lần copy', () async {
      final source = FakeClipboardSource();
      final original = _clip('c1', content: 'xin chào', copyCount: 2);
      final repo = InMemoryClipboardRepository(clips: [original]);

      final copied = (await CopyClip(source, repo, clock)(
        original,
      )).valueOrNull!;

      expect(source.written, ['xin chào']);
      expect(copied.copiedAt, _now);
      expect(copied.copyCount, 3);
      expect(copied.updatedAt, original.updatedAt);
      expect(repo.clip('c1'), copied);
      expect(repo.log, ['recordCopy(c1)']);
      expect(repo.dirty, isEmpty);
      expect(repo.pushRequests, 0);
    });

    test(
      'copy nhiều clip: nối theo thứ tự cũ nhất trước, mỗi clip một dòng',
      () async {
        final source = FakeClipboardSource();
        final newest = _clip('n', content: 'ba', created: _ago(Duration.zero));
        final oldest = _clip(
          'o',
          content: 'một',
          created: _ago(const Duration(hours: 5)),
        );
        final middle = _clip(
          'm',
          content: 'hai\ndòng',
          created: _ago(const Duration(hours: 1)),
          saved: true,
        );
        final repo = InMemoryClipboardRepository(
          clips: [newest, oldest, middle],
        );

        final result = await CopyClips(source, repo, clock)([
          newest,
          oldest,
          middle,
        ]);

        expect(source.written, ['một\nhai\ndòng\nba']);
        final copied = result.valueOrNull!;
        expect(_ids(copied), ['o', 'm', 'n']);
        expect(
          copied.every((c) => c.copiedAt == _now && c.copyCount == 1),
          isTrue,
        );
        expect(repo.log, ['recordCopy(o)', 'recordCopy(m)', 'recordCopy(n)']);
        expect(repo.pushRequests, 0);
      },
    );

    test('copy nhiều với danh sách rỗng không đụng tới clipboard', () async {
      final source = FakeClipboardSource();
      final repo = InMemoryClipboardRepository();

      expect((await CopyClips(source, repo, clock)([])).valueOrNull, isEmpty);
      expect(source.written, isEmpty);
      expect(repo.log, isEmpty);
    });

    test('không ghi được lên clipboard thì không ghi lần copy', () async {
      final source = FakeClipboardSource()
        ..failure = const UnexpectedFailure('x');
      final repo = InMemoryClipboardRepository(clips: [_clip('c1')]);

      expect(
        await CopyClip(source, repo, clock)(repo.clip('c1')!),
        const Err<ClipItem>(UnexpectedFailure('x')),
      );
      expect(repo.log, isEmpty);
    });
  });

  test('WatchRemoteClipChanges bắn khi sync ghi', () async {
    final repo = InMemoryClipboardRepository();
    final stream = (await WatchRemoteClipChanges(repo)(
      const NoParams(),
    )).valueOrNull!;
    var fired = 0;
    final sub = stream.listen((_) => fired++);

    repo.emitRemoteChange();
    repo.emitRemoteChange();

    expect(fired, 2);
    await sub.cancel();
    await repo.dispose();
  });
}
