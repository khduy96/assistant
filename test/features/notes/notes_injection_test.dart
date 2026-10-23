import 'dart:io';

import 'package:event_notice/app/di/injection.dart';
import 'package:event_notice/core/data/system_clock.dart';
import 'package:event_notice/core/data/uuid_id_generator.dart';
import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/domain/id_generator.dart';
import 'package:event_notice/features/notes/data/datasources/note_local_data_source.dart';
import 'package:event_notice/features/notes/data/repositories/note_repository_impl.dart';
import 'package:event_notice/features/notes/data/sync/note_sync_collection.dart';
import 'package:event_notice/features/notes/domain/repositories/note_repository.dart';
import 'package:event_notice/features/notes/domain/usecases/get_notes.dart';
import 'package:event_notice/features/notes/domain/usecases/new_note.dart';
import 'package:event_notice/features/notes/domain/usecases/save_note.dart';
import 'package:event_notice/features/notes/domain/usecases/watch_notes.dart';
import 'package:event_notice/features/notes/notes_injection.dart';
import 'package:event_notice/features/notes/presentation/notes_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'domain/fakes.dart';

void main() {
  late GetIt sl;

  setUp(() => sl = GetIt.asNewInstance());
  tearDown(() => sl.reset());

  group('configureDependencies', () {
    test('đăng ký Clock và IdGenerator của hệ thống', () {
      configureDependencies(sl);

      expect(sl<Clock>(), isA<SystemClock>());
      expect(sl<IdGenerator>(), isA<UuidIdGenerator>());
    });

    test('đăng ký đủ notes', () {
      configureDependencies(sl);

      expect(sl<NotesController>(), isA<NotesController>());
      expect(sl<NoteSyncCollection>().className, 'NoteItem');
    });
  });

  group('registerNotes', () {
    setUp(() {
      sl
        ..registerSingleton<Clock>(FakeClock(DateTime(2026, 10, 22, 9, 30)))
        ..registerSingleton<IdGenerator>(SequentialIdGenerator());
      registerNotes(sl);
    });

    test('một repository duy nhất, thấy dưới cả hai kiểu', () {
      expect(sl<NoteRepository>(), same(sl<NoteRepositoryImpl>()));
    });

    test('use case và collection là singleton', () {
      expect(sl<GetNotes>(), same(sl<GetNotes>()));
      expect(sl<SaveNote>(), same(sl<SaveNote>()));
      expect(sl<WatchNotes>(), same(sl<WatchNotes>()));
      expect(sl<NewNote>(), same(sl<NewNote>()));
      expect(sl<NoteSyncCollection>(), same(sl<NoteSyncCollection>()));
    });

    test('mỗi lần lấy controller là một controller mới', () {
      final a = sl<NotesController>();
      final b = sl<NotesController>();
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      expect(a, isNot(same(b)));
    });

    test('sửa qua controller thì collection thấy bản cần đẩy và báo '
        'thay đổi local', () async {
      final dir = await Directory.systemTemp.createTemp('notes_injection');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/notes.json';
      // Trỏ file ghi chú vào thư mục tạm, phần còn lại giữ như đăng ký.
      sl
        ..unregister<NoteLocalDataSource>()
        ..registerLazySingleton(() => NoteLocalDataSource(sl(), path: path));

      final repo = sl<NoteRepositoryImpl>();
      final collection = sl<NoteSyncCollection>();
      final controller = sl<NotesController>();
      addTearDown(controller.dispose);
      await repo.init();
      await controller.init();

      var localChanges = 0;
      final sub = collection.localChanges.listen((_) => localChanges++);
      addTearDown(sub.cancel);

      final blank = await controller.newNote();
      expect(blank!.id, 'id-1');
      await controller.save(blank.copyWith(title: 'Wifi', body: '12345678'));
      // Sự kiện thay đổi của repository thật tới sau một nhịp, và lượt tải
      // lại nó gây ra mới là lượt thắng.
      await Future<void>.delayed(Duration.zero);

      expect(controller.failure, isNull);
      expect(controller.notes.single.title, 'Wifi');
      expect((await collection.dirtyRecords()).single.localId, 'id-1');
      expect(localChanges, 1);
      expect(await File(path).readAsString(), contains('"Wifi"'));
    });
  });
}
