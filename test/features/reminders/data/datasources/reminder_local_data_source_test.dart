import 'dart:convert';
import 'dart:io';

import 'package:event_notice/core/data/app_paths.dart';
import 'package:event_notice/core/domain/time_of_day.dart';
import 'package:event_notice/features/reminders/data/datasources/reminder_local_data_source.dart';
import 'package:event_notice/features/reminders/data/models/reminder_model.dart';
import 'package:event_notice/features/reminders/domain/entities/reminder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fakes.dart';

const _fixtures = 'test/features/reminders/data/fixtures';

final _now = DateTime(2026, 10, 22, 8);

/// The keys of one reminder in `reminders.json`, in the order they are
/// written.
const _keys = [
  'id',
  'title',
  'note',
  'enabled',
  'repeat',
  'date',
  'hour',
  'minute',
  'weekdays',
  'repeatEveryMinutes',
  'endHour',
  'endMinute',
  'leadMinutes',
  'snoozeMinutes',
  'snoozedUntil',
  'firedUpTo',
  'isDeadline',
  'createdAt',
];

/// Puts the app's files in a test directory instead of the real one.
class _TempPaths extends AppPaths {
  const _TempPaths(this.dir);

  final String dir;

  @override
  Future<String> supportFile(String fileName) async => '$dir/$fileName';
}

/// The file's text with Windows line endings folded, so a checkout with
/// `autocrlf` compares the same.
String _text(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n').trimRight();

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('reminder_data_test');
    path = '${dir.path}/reminders.json';
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Copies a fixture to the test file, so the original is never written.
  Future<void> useFixture(String name) => File('$_fixtures/$name').copy(path);

  ReminderLocalDataSource source() =>
      ReminderLocalDataSource(FakeClock(_now), path: path);

  test('tên file là reminders.json', () async {
    final source = ReminderLocalDataSource(
      FakeClock(_now),
      paths: _TempPaths(dir.path),
    );
    await source.save(const []);
    expect(await File('${dir.path}/reminders.json').exists(), isTrue);
  });

  test('không có file thì rỗng', () async {
    expect(await source().load(), isEmpty);
  });

  test('đọc đủ mọi khoá của file hiện tại', () async {
    await useFixture('reminders_full.json');
    final [r1, r2] = await source().load();

    expect(r1.id, 'r1');
    expect(r1.title, 'Nộp hồ sơ');
    expect(r1.note, 'bản cứng');
    expect(r1.enabled, isTrue);
    expect(r1.repeat, RepeatRule.once);
    expect(r1.date, DateTime(2026, 10, 30));
    expect(r1.time, TimeOfDay(hour: 17, minute: 0));
    expect(r1.weekdays, isEmpty);
    expect(r1.repeatEveryMinutes, 0);
    expect(r1.endTime, isNull);
    expect(r1.leadMinutes, 60);
    expect(r1.snoozeMinutes, 5);
    expect(r1.snoozedUntil, isNull);
    expect(r1.firedUpTo, DateTime(2026, 10, 22, 8, 15, 30, 500));
    expect(r1.isDeadline, isTrue);
    expect(r1.createdAt, DateTime(2026, 10, 20, 9));

    expect(r2.enabled, isFalse);
    expect(r2.repeat, RepeatRule.weekly);
    expect(r2.time, TimeOfDay(hour: 10, minute: 0));
    expect(r2.weekdays, {DateTime.monday, DateTime.wednesday, DateTime.friday});
    expect(r2.repeatEveryMinutes, 120);
    expect(r2.endTime, TimeOfDay(hour: 22, minute: 30));
    expect(r2.leadMinutes, 10);
    expect(r2.snoozeMinutes, 15);
    expect(r2.snoozedUntil, DateTime(2026, 10, 22, 10, 15));
    expect(r2.firedUpTo, isNull);
    expect(r2.isDeadline, isFalse);
    expect(r2.createdAt, DateTime(2026, 10, 1, 7, 45));
  });

  test('file cũ thiếu khoá thì lấy mặc định như bản cũ', () async {
    await useFixture('reminders_old.json');
    final [a, b, c] = await source().load();

    expect(a.title, 'Họp giao ban');
    expect(a.repeat, RepeatRule.daily);
    expect(a.time, TimeOfDay(hour: 9, minute: 30));
    for (final r in [a, b, c]) {
      expect(r.enabled, isTrue);
      expect(r.weekdays, isEmpty);
      expect(r.repeatEveryMinutes, 0);
      expect(r.leadMinutes, 0);
      expect(r.snoozeMinutes, 5);
      expect(r.snoozedUntil, isNull);
      expect(r.firedUpTo, isNull);
      expect(r.isDeadline, isFalse);
      // Thiếu, null hay không đọc được createdAt thì lấy giờ của Clock.
      expect(r.createdAt, _now);
    }
    expect(a.note, '');
    expect(a.endTime, isNull);

    // Thiếu title, giờ, phút; repeat lạ thì là một lần; có endHour mà thiếu
    // endMinute thì phút là 0.
    expect(b.title, '');
    expect(b.repeat, RepeatRule.once);
    expect(b.time, TimeOfDay(hour: 8, minute: 0));
    expect(b.endTime, TimeOfDay(hour: 21, minute: 0));

    // null tường minh cũng như thiếu; không có endHour thì không có giờ dừng.
    expect(c.time, TimeOfDay(hour: 8, minute: 0));
    expect(c.endTime, isNull);
  });

  test('file hỏng thì rỗng', () async {
    await useFixture('reminders_corrupt.json');
    expect(await source().load(), isEmpty);
  });

  test(
    'một nhắc nhở không đọc được thì cả file coi là hỏng, như bản cũ',
    () async {
      for (final bad in [
        {'title': 'thiếu id', 'date': '2026-01-01T00:00:00.000'},
        {'id': 'thiếu date'},
        {'id': 'x', 'date': '2026-01-01', 'snoozedUntil': 'không phải ngày'},
        {'id': 'x', 'date': '2026-01-01', 'hour': '9'},
      ]) {
        await File(path).writeAsString(
          jsonEncode([
            {'id': 'ok', 'date': '2026-01-01T00:00:00.000'},
            bad,
          ]),
        );
        expect(await source().load(), isEmpty, reason: '$bad');
      }
    },
  );

  test('file không phải list thì coi là hỏng, như bản cũ', () async {
    await File(path).writeAsString(
      jsonEncode({
        'items': [
          {'id': 'ok', 'date': '2026-01-01T00:00:00.000'},
        ],
        'deleted': [],
      }),
    );
    expect(await source().load(), isEmpty);
  });

  test('round-trip giữ nguyên từng ký tự của file', () async {
    await useFixture('reminders_full.json');
    final saved = await source().load();

    final copy = '${dir.path}/copy.json';
    await ReminderLocalDataSource(FakeClock(_now), path: copy).save(saved);

    final written = jsonDecode(File(copy).readAsStringSync()) as List;
    for (final item in written) {
      expect((item as Map).keys, _keys);
    }
    expect(written, jsonDecode(File(path).readAsStringSync()));
    expect(_text(copy), _text('$_fixtures/reminders_full.json'));
  });

  test('file cũ ghi lại thành bare list đủ khoá', () async {
    await useFixture('reminders_old.json');
    await source().save(await source().load());

    final written = jsonDecode(File(path).readAsStringSync()) as List;
    expect(written.map((e) => (e as Map)['id']), ['a', 'b', 'c']);
    expect(written.first, {
      'id': 'a',
      'title': 'Họp giao ban',
      'note': '',
      'enabled': true,
      'repeat': 'daily',
      'date': '2026-01-05T00:00:00.000',
      'hour': 9,
      'minute': 30,
      'weekdays': <int>[],
      'repeatEveryMinutes': 0,
      'endHour': null,
      'endMinute': null,
      'leadMinutes': 0,
      'snoozeMinutes': 5,
      'snoozedUntil': null,
      'firedUpTo': null,
      'isDeadline': false,
      'createdAt': '2026-10-22T08:00:00.000',
    });
    expect((written[1] as Map)['repeat'], 'once');
    expect((written[1] as Map)['endMinute'], 0);
  });

  test('ghi xong đọc lại được đúng như trước', () async {
    final model = ReminderModel(
      id: 'r1',
      title: 'Họp',
      repeat: RepeatRule.weekly,
      date: DateTime(2026, 10, 22),
      time: TimeOfDay(hour: 14, minute: 5),
      weekdays: const {DateTime.friday, DateTime.monday},
      repeatEveryMinutes: 30,
      endTime: TimeOfDay(hour: 18, minute: 0),
      firedUpTo: DateTime(2026, 10, 22, 14, 5),
      createdAt: DateTime(2026, 10, 21),
    );
    await source().save([model]);
    final [read] = await source().load();
    expect(read.toJson(), model.toJson());
    // Thứ trong tuần được ghi theo thứ tự tăng dần.
    final written = jsonDecode(File(path).readAsStringSync()) as List;
    expect((written.single as Map)['weekdays'], [1, 5]);
  });

  test('hai lần ghi liền nhau thì lần sau thắng', () async {
    final s = source();
    final first = s.save([
      ReminderModel(
        id: 'a',
        date: DateTime(2026, 1, 1),
        time: TimeOfDay(hour: 8, minute: 0),
        createdAt: _now,
      ),
    ]);
    final second = s.save(const []);
    await Future.wait([first, second]);
    expect(await s.load(), isEmpty);
  });
}
