import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/domain/usecases/get_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/new_note.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/fakes.dart';
import 'fixture.dart';

/// Counts its calls, then does what the real use case does.
class _CountingGetNotes implements GetNotes {
  _CountingGetNotes(this._inner);

  final GetNotes _inner;
  int calls = 0;

  @override
  Future<Result<List<Note>>> call(NoParams params) {
    calls++;
    return _inner(params);
  }
}

class _FailingNewNote implements NewNote {
  @override
  Future<Result<Note>> call(NoParams params) async =>
      const Err(UnexpectedFailure('no id'));
}

List<String> _ids(List<Note> notes) => [for (final n in notes) n.id];

void main() {
  late FakeClock clock;
  late InMemoryNoteRepository repo;
  late NotesController controller;
  late int notified;

  setUp(() {
    clock = FakeClock(at(60));
    repo = InMemoryNoteRepository([
      note('old', title: 'Wifi nhà', body: 'mật khẩu 1234', updatedMin: 1),
      note('pinned', title: 'Ghim', pinned: true, updatedMin: 2),
      note('new', title: 'Họp', body: 'Chuẩn bị slide', updatedMin: 9),
    ]);
    controller = controllerFor(repo, clock: clock);
    notified = 0;
    controller.addListener(() => notified++);
  });

  tearDown(() async {
    controller.dispose();
    await repo.dispose();
  });

  test('chưa init thì danh sách rỗng', () {
    expect(controller.notes, isEmpty);
    expect(controller.results, isEmpty);
    expect(controller.count, 0);
    expect(controller.query, '');
  });

  test('init tải ghi chú: ghim trước, rồi sửa gần nhất', () async {
    await controller.init();

    expect(_ids(controller.notes), ['pinned', 'new', 'old']);
    expect(_ids(controller.results), ['pinned', 'new', 'old']);
    expect(controller.count, 3);
    expect(controller.failure, isNull);
    expect(notified, greaterThan(0));
  });

  test('init gọi hai lần chỉ đăng ký nghe một lần', () async {
    final getNotes = _CountingGetNotes(GetNotes(repo));
    final c = controllerFor(repo, clock: clock, getNotes: getNotes);
    await c.init();
    await c.init();
    expect(getNotes.calls, 1);

    await repo.save(note('x', title: 'x'));
    await pumpEventQueue();
    expect(getNotes.calls, 2);
    c.dispose();
  });

  test('thay đổi từ bên ngoài (như sync) làm danh sách tải lại', () async {
    await controller.init();

    await repo.save(note('synced', title: 'Từ máy khác', updatedMin: 30));
    await pumpEventQueue();

    expect(_ids(controller.notes), ['pinned', 'synced', 'new', 'old']);

    await repo.delete('old');
    await pumpEventQueue();

    expect(_ids(controller.notes), ['pinned', 'synced', 'new']);
    expect(controller.count, 3);
  });

  group('tìm kiếm', () {
    test(
      'lọc theo tiêu đề hoặc nội dung, không phân biệt hoa thường',
      () async {
        await controller.init();

        await controller.setQuery('MẬT KHẨU');
        expect(controller.query, 'MẬT KHẨU');
        expect(_ids(controller.results), ['old']);
        // count is every note, not just the matches.
        expect(controller.count, 3);
        expect(_ids(controller.notes), ['pinned', 'new', 'old']);
      },
    );

    test('query rỗng hoặc toàn khoảng trắng trả tất cả', () async {
      await controller.init();
      await controller.setQuery('họp');
      expect(_ids(controller.results), ['new']);

      await controller.setQuery('   ');
      expect(_ids(controller.results), ['pinned', 'new', 'old']);

      await controller.setQuery('');
      expect(_ids(controller.results), ['pinned', 'new', 'old']);
    });

    test('không khớp gì thì kết quả rỗng', () async {
      await controller.init();
      await controller.setQuery('không có đâu');
      expect(controller.results, isEmpty);
      expect(controller.count, 3);
    });

    test('query được giữ khi danh sách tải lại', () async {
      await controller.init();
      await controller.setQuery('họp');

      await repo.save(note('other', title: 'Họp tuần', updatedMin: 50));
      await pumpEventQueue();

      expect(_ids(controller.results), ['other', 'new']);
    });
  });

  group('thao tác', () {
    test('save đặt updatedAt theo Clock, giữ createdAt, xếp lại', () async {
      await controller.init();
      final old = controller.noteById('old')!;

      await controller.save(old.copyWith(title: 'Wifi văn phòng'));

      final saved = repo['old']!;
      expect(saved.title, 'Wifi văn phòng');
      expect(saved.updatedAt, at(60));
      expect(saved.createdAt, old.createdAt);
      expect(_ids(controller.notes), ['pinned', 'old', 'new']);
      expect(controller.noteById('old')!.title, 'Wifi văn phòng');
    });

    test('save ghi chú rỗng thì xoá nó', () async {
      await controller.init();
      final old = controller.noteById('old')!;

      await controller.save(old.copyWith(title: ' ', body: '\n'));

      expect(repo['old'], isNull);
      expect(_ids(controller.notes), ['pinned', 'new']);
    });

    test('setPinned đưa lên đầu và tính là một lần sửa', () async {
      await controller.init();

      await controller.setPinned(controller.noteById('old')!, true);

      expect(repo['old']!.pinned, isTrue);
      expect(repo['old']!.updatedAt, at(60));
      expect(_ids(controller.notes), ['old', 'pinned', 'new']);

      await controller.setPinned(controller.noteById('old')!, false);
      expect(_ids(controller.notes), ['pinned', 'old', 'new']);
    });

    test('delete xoá khỏi danh sách', () async {
      await controller.init();

      await controller.delete('new');

      expect(repo.deleted, ['new']);
      expect(controller.noteById('new'), isNull);
      expect(controller.count, 2);
    });

    test(
      'newNote trả ghi chú trống, id mới, thời gian theo Clock, chưa lưu',
      () async {
        await controller.init();

        final blank = await controller.newNote();

        expect(blank!.id, 'id-1');
        expect(blank.isEmpty, isTrue);
        expect(blank.createdAt, at(60));
        expect(blank.updatedAt, at(60));
        expect(repo['id-1'], isNull);
        expect(controller.count, 3);
      },
    );
  });

  group('lỗi', () {
    const failure = StorageFailure('disk');

    test('tải lỗi thì giữ danh sách cũ và ghi lại failure', () async {
      await controller.init();
      repo.failure = failure;

      await controller.setQuery('họp');

      expect(controller.failure, failure);
      expect(_ids(controller.notes), ['pinned', 'new', 'old']);
    });

    test('thao tác lỗi thì ghi lại failure và báo listener', () async {
      await controller.init();
      repo.failure = failure;
      final before = notified;

      await controller.delete('old');

      expect(controller.failure, failure);
      expect(notified, greaterThan(before));
      expect(controller.count, 3);
    });

    test('lần tải thành công sau đó xoá failure', () async {
      await controller.init();
      repo.failure = failure;
      await controller.delete('old');
      repo.failure = null;

      await controller.delete('old');

      expect(controller.failure, isNull);
      expect(controller.count, 2);
    });

    test('newNote lỗi thì trả null', () async {
      final c = controllerFor(repo, clock: clock, newNote: _FailingNewNote());
      await c.init();

      expect(await c.newNote(), isNull);
      expect(c.failure, const UnexpectedFailure('no id'));
      c.dispose();
    });
  });

  test('sau dispose, thay đổi của repository không làm gì nữa', () async {
    final c = controllerFor(repo, clock: clock);
    await c.init();
    c.dispose();

    // Would throw if the controller still listened and notified.
    await repo.save(note('late', title: 'muộn'));
    await pumpEventQueue();

    expect(c.noteById('late'), isNull);
  });

  test('dispose giữa lúc init không đăng ký nghe', () async {
    final c = controllerFor(repo, clock: clock);
    final pending = c.init();
    c.dispose();
    await pending;

    await repo.save(note('late', title: 'muộn'));
    await pumpEventQueue();
    expect(c.notes, isEmpty);
  });
}
