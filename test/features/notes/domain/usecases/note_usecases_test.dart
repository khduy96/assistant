import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/usecase.dart';
import 'package:event_notice/features/notes/domain/entities/note.dart';
import 'package:event_notice/features/notes/domain/usecases/delete_note.dart';
import 'package:event_notice/features/notes/domain/usecases/get_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/new_note.dart';
import 'package:event_notice/features/notes/domain/usecases/save_note.dart';
import 'package:event_notice/features/notes/domain/usecases/search_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/set_note_pinned.dart';
import 'package:event_notice/features/notes/domain/usecases/watch_notes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

DateTime _min(int m) => _t0.add(Duration(minutes: m));

Note _note(
  String id, {
  String title = 'x',
  String body = '',
  bool pinned = false,
  int updatedMin = 0,
}) => Note(
  id: id,
  title: title,
  body: body,
  pinned: pinned,
  createdAt: _t0,
  updatedAt: _min(updatedMin),
);

List<String> _ids(Result<List<Note>> r) => [
  for (final n in r.valueOrNull!) n.id,
];

void main() {
  const storageFailure = StorageFailure('disk');

  group('GetNotes', () {
    test('ghim trước, rồi theo updatedAt giảm dần', () async {
      final repo = InMemoryNoteRepository([
        _note('old', updatedMin: 1),
        _note('pinnedOld', pinned: true, updatedMin: 2),
        _note('newest', updatedMin: 9),
        _note('pinnedNew', pinned: true, updatedMin: 5),
        _note('mid', updatedMin: 4),
      ]);

      final result = await GetNotes(repo)(const NoParams());

      expect(_ids(result), ['pinnedNew', 'pinnedOld', 'newest', 'mid', 'old']);
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryNoteRepository()..failure = storageFailure;
      expect(
        await GetNotes(repo)(const NoParams()),
        const Err<List<Note>>(storageFailure),
      );
    });
  });

  group('SearchNotes', () {
    final notes = [
      _note('a', title: 'Họp nhóm', updatedMin: 1),
      _note('b', title: 'Mua sắm', body: 'sữa, trứng', updatedMin: 3),
      _note('c', title: 'Nhóm đọc sách', pinned: true, updatedMin: 0),
    ];

    test('query rỗng trả về tất cả, đúng thứ tự', () async {
      final search = SearchNotes(InMemoryNoteRepository(notes));
      expect(_ids(await search('')), ['c', 'b', 'a']);
      expect(_ids(await search('   ')), ['c', 'b', 'a']);
    });

    test(
      'lọc theo tiêu đề hoặc nội dung, không phân biệt hoa thường',
      () async {
        final search = SearchNotes(InMemoryNoteRepository(notes));
        expect(_ids(await search('NHÓM')), ['c', 'a']);
        expect(_ids(await search('trứng')), ['b']);
        expect(_ids(await search('không có')), isEmpty);
      },
    );

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryNoteRepository(notes)..failure = storageFailure;
      expect((await SearchNotes(repo)('')).failureOrNull, storageFailure);
    });
  });

  group('SaveNote', () {
    test('đặt updatedAt bằng Clock.now(), giữ createdAt', () async {
      final repo = InMemoryNoteRepository();
      final clock = FakeClock(_min(30));

      final result = await SaveNote(repo, clock)(_note('n1', title: 'Việc'));

      expect(result.isOk, isTrue);
      expect(repo['n1']!.updatedAt, _min(30));
      expect(repo['n1']!.createdAt, _t0);
      expect(repo['n1']!.title, 'Việc');
    });

    test('sửa bản đã có thì thay thế, không thêm bản mới', () async {
      final repo = InMemoryNoteRepository([_note('n1', title: 'cũ')]);
      final clock = FakeClock(_min(10));

      await SaveNote(repo, clock)(repo['n1']!.copyWith(title: 'mới'));

      expect(repo.length, 1);
      expect(repo['n1']!.title, 'mới');
      expect(repo['n1']!.updatedAt, _min(10));
    });

    test('ghi chú rỗng (chỉ khoảng trắng) thì bị xoá', () async {
      final repo = InMemoryNoteRepository([_note('n1', title: 'có chữ')]);
      final clock = FakeClock(_min(10));

      final result = await SaveNote(repo, clock)(
        repo['n1']!.copyWith(title: '  ', body: '\n\t '),
      );

      expect(result.isOk, isTrue);
      expect(repo['n1'], isNull);
      expect(repo.deleted, ['n1']);
    });

    test('ghi chú mới mà rỗng thì không để lại gì', () async {
      final repo = InMemoryNoteRepository();
      await SaveNote(repo, FakeClock(_t0))(_note('n1', title: ''));
      expect(repo.length, 0);
    });

    test('lỗi của repository được trả lại nguyên vẹn', () async {
      final repo = InMemoryNoteRepository()..failure = storageFailure;
      final result = await SaveNote(repo, FakeClock(_t0))(_note('n1'));
      expect(result.failureOrNull, storageFailure);
    });
  });

  group('DeleteNote', () {
    test('xoá đúng ghi chú theo id', () async {
      final repo = InMemoryNoteRepository([_note('a'), _note('b')]);

      final result = await DeleteNote(repo)('a');

      expect(result.isOk, isTrue);
      expect(repo['a'], isNull);
      expect(repo['b'], isNotNull);
    });
  });

  group('SetNotePinned', () {
    test('đổi pinned và đặt updatedAt bằng Clock.now()', () async {
      final repo = InMemoryNoteRepository([_note('n1', title: 'giữ')]);
      final pin = SetNotePinned(repo, FakeClock(_min(45)));

      await pin((note: repo['n1']!, pinned: true));

      expect(repo['n1']!.pinned, isTrue);
      expect(repo['n1']!.updatedAt, _min(45));
      expect(repo['n1']!.title, 'giữ');
      expect(repo['n1']!.createdAt, _t0);
    });

    test('bỏ ghim', () async {
      final repo = InMemoryNoteRepository([_note('n1', pinned: true)]);
      await SetNotePinned(repo, FakeClock(_min(1)))((
        note: repo['n1']!,
        pinned: false,
      ));
      expect(repo['n1']!.pinned, isFalse);
    });
  });

  group('WatchNotes', () {
    test('bắn sự kiện mỗi khi repository đổi', () async {
      final repo = InMemoryNoteRepository();
      addTearDown(repo.dispose);
      final stream = (await WatchNotes(repo)(const NoParams())).valueOrNull!;
      var events = 0;
      final sub = stream.listen((_) => events++);
      addTearDown(sub.cancel);

      await SaveNote(repo, FakeClock(_t0))(_note('n1'));
      await DeleteNote(repo)('n1');

      expect(events, 2);
    });
  });

  group('NewNote', () {
    test('id từ IdGenerator, createdAt = updatedAt = Clock.now()', () async {
      final clock = FakeClock(_min(7));
      final newNote = NewNote(SequentialIdGenerator(), clock);

      final first = (await newNote(const NoParams())).valueOrNull!;
      clock.current = _min(8);
      final second = (await newNote(const NoParams())).valueOrNull!;

      expect(first.id, 'id-1');
      expect(first.createdAt, _min(7));
      expect(first.updatedAt, _min(7));
      expect(first.isEmpty, isTrue);
      expect(first.pinned, isFalse);
      expect(first.markdown, isFalse);
      expect(first.color, NoteColor.none);
      expect(second.id, 'id-2');
      expect(second.createdAt, _min(8));
    });
  });
}
