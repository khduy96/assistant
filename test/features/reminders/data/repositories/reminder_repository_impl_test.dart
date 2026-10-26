import 'dart:async';
import 'dart:io';

import 'package:event_notice/core/domain/failure.dart';
import 'package:event_notice/core/domain/result.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/data/datasources/reminder_local_data_source.dart';
import 'package:event_notice/features/reminders/data/models/reminder_model.dart';
import 'package:event_notice/features/reminders/data/repositories/reminder_repository_impl.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

final _t0 = DateTime(2026, 10, 22, 8);

Reminder _reminder(String id, {String title = 'nhắc', bool enabled = true}) =>
    Reminder(
      id: id,
      title: title,
      enabled: enabled,
      date: DateTime(2026, 10, 23),
      time: TimeOfDay(hour: 9, minute: 0),
      createdAt: _t0,
    );

/// A data source that counts its writes and can be made to fail.
class _Source extends ReminderLocalDataSource {
  _Source(String path) : super(FakeClock(_t0), path: path);

  int writes = 0;
  bool failWrites = false;
  bool failLoads = false;

  @override
  Future<List<ReminderModel>> load() {
    if (failLoads) throw const FileSystemException('không đọc được');
    return super.load();
  }

  @override
  Future<void> save(List<ReminderModel> reminders) async {
    writes++;
    if (failWrites) throw const FileSystemException('đĩa đầy');
    await super.save(reminders);
  }
}

/// Counts the events a stream fires.
class _Counter {
  _Counter(Stream<void> stream) {
    _sub = stream.listen((_) => count++);
  }

  late final StreamSubscription<void> _sub;
  int count = 0;

  Future<void> cancel() => _sub.cancel();
}

/// Lets the broadcast streams deliver what they have queued.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late Directory dir;
  late String path;
  late _Source source;
  late ReminderRepositoryImpl repo;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reminder_repo_test');
    path = '${dir.path}/reminders.json';
    source = _Source(path);
    repo = ReminderRepositoryImpl(source);
  });

  tearDown(() async {
    await repo.dispose();
    await dir.delete(recursive: true);
  });

  /// What a fresh repository reads back from the file.
  Future<List<Reminder>> reread() async {
    final other = ReminderRepositoryImpl(_Source(path));
    final all = (await other.getAll()).valueOrNull!;
    await other.dispose();
    return all;
  }

  group('nạp', () {
    test('init đọc file mẫu', () async {
      await File(
        'test/features/reminders/data/fixtures/reminders_full.json',
      ).copy(path);
      await repo.init();
      final all = (await repo.getAll()).valueOrNull!;
      expect(all.map((r) => r.id), ['r1', 'r2']);
      expect(all.first.isDeadline, isTrue);
    });

    test('getAll tự nạp nếu chưa init và chỉ đọc đĩa một lần', () async {
      await repo.save(_reminder('a'));
      final fresh = _Source(path);
      var loads = 0;
      final counted = ReminderRepositoryImpl(
        _CountingLoads(fresh, () => loads++),
      );
      for (var i = 0; i < 5; i++) {
        expect((await counted.getAll()).valueOrNull!.single.id, 'a');
      }
      expect(loads, 1);
      await counted.dispose();
    });

    test('nạp lỗi thì trả StorageFailure và lần sau nạp lại', () async {
      source.failLoads = true;
      final failed = await repo.getAll();
      expect(failed.failureOrNull, isA<StorageFailure>());

      source.failLoads = false;
      expect(await repo.getAll(), isA<Ok<List<Reminder>>>());
    });
  });

  group('ghi', () {
    test('save thêm mới rồi thay đúng chỗ theo id', () async {
      await repo.save(_reminder('a', title: 'một'));
      await repo.save(_reminder('b'));
      await repo.save(_reminder('a', title: 'một sửa'));

      final all = (await repo.getAll()).valueOrNull!;
      expect(all.map((r) => r.id), ['a', 'b']);
      expect(all.first.title, 'một sửa');
      expect((await reread()).map((r) => r.title), ['một sửa', 'nhắc']);
    });

    test('find trả nhắc theo id, id lạ thì null', () async {
      await repo.save(_reminder('a'));
      expect((await repo.find('a')).valueOrNull?.id, 'a');
      expect(await repo.find('x'), const Ok<Reminder?>(null));
    });

    test('saveAll ghi một lần cho nhiều nhắc', () async {
      await repo.init();
      await repo.saveAll([_reminder('a'), _reminder('b'), _reminder('c')]);
      expect(source.writes, 1);
      expect((await reread()).map((r) => r.id), ['a', 'b', 'c']);
    });

    test('saveAll rỗng không ghi', () async {
      expect(await repo.saveAll(const []), const Ok<void>(null));
      expect(source.writes, 0);
    });

    test('delete xoá và ghi file; id lạ thì không ghi', () async {
      await repo.saveAll([_reminder('a'), _reminder('b')]);
      expect(await repo.delete('a'), const Ok<void>(null));
      expect((await reread()).map((r) => r.id), ['b']);

      final writes = source.writes;
      expect(await repo.delete('không có'), const Ok<void>(null));
      expect(source.writes, writes);
    });

    test('file luôn là bare list', () async {
      await repo.save(_reminder('a'));
      final text = await File(path).readAsString();
      expect(text.trimLeft().startsWith('['), isTrue);
    });

    test('getAll trả bản không sửa được', () async {
      await repo.save(_reminder('a'));
      final all = (await repo.getAll()).valueOrNull!;
      expect(() => all.add(_reminder('b')), throwsUnsupportedError);
    });
  });

  group('ghi lỗi', () {
    test('bộ nhớ vẫn đổi, báo StorageFailure, vẫn báo changes', () async {
      await repo.save(
        _reminder('a').copyWith(firedUpTo: DateTime(2026, 10, 22, 7)),
      );
      final counter = _Counter(repo.changes);
      source.failWrites = true;

      final handled = DateTime(2026, 10, 22, 9);
      final result = await repo.saveAll([
        _reminder('a').copyWith(firedUpTo: handled),
      ]);
      await _settle();

      expect(result.failureOrNull, isA<StorageFailure>());
      // Mốc đã báo phải tiến trong bộ nhớ, nếu không chuông sẽ kêu lại.
      expect((await repo.find('a')).valueOrNull!.firedUpTo, handled);
      expect(counter.count, 1);
      // Đĩa vẫn giữ bản cũ.
      expect((await reread()).single.firedUpTo, DateTime(2026, 10, 22, 7));
      await counter.cancel();
    });

    test('delete lỗi vẫn bỏ khỏi bộ nhớ', () async {
      await repo.save(_reminder('a'));
      source.failWrites = true;
      expect((await repo.delete('a')).failureOrNull, isA<StorageFailure>());
      expect((await repo.getAll()).valueOrNull, isEmpty);
    });

    test('lần ghi sau lỗi vẫn chạy', () async {
      await repo.init();
      source.failWrites = true;
      await repo.save(_reminder('a'));
      source.failWrites = false;
      expect(await repo.save(_reminder('b')), const Ok<void>(null));
      expect((await reread()).map((r) => r.id), ['a', 'b']);
    });
  });

  test('changes báo khi nạp và sau mỗi lần ghi', () async {
    final counter = _Counter(repo.changes);
    await repo.init();
    await repo.save(_reminder('a'));
    await repo.saveAll([_reminder('b'), _reminder('c')]);
    await repo.delete('a');
    await repo.delete('không có');
    await _settle();
    expect(counter.count, 4);
    await counter.cancel();
  });
}

/// Wraps a data source to count its loads.
class _CountingLoads extends ReminderLocalDataSource {
  _CountingLoads(this._inner, this._onLoad) : super(FakeClock(_t0));

  final ReminderLocalDataSource _inner;
  final void Function() _onLoad;

  @override
  Future<List<ReminderModel>> load() {
    _onLoad();
    return _inner.load();
  }

  @override
  Future<void> save(List<ReminderModel> reminders) => _inner.save(reminders);
}
