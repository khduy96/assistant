import 'dart:convert';

import 'package:event_notice/core/sync/data/parse_client.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fake_parse_server.dart';
import '../fakes.dart';

/// The engine against the monthly request budget, and the ways it saves
/// requests: cycles that only push, small classes pulled in one pass, full
/// pulls spaced by the budget.
///
/// Four in-memory lists stand in for the clipboard's two classes (on the
/// shared channel), the todos and the notes; the fake Back4App is reached in
/// memory, through the engine's HTTP client factory.
void main() {
  const budget = SyncBudget.configured;

  late FakeParseServer server;
  late MemorySyncStateStore state;
  late FixedClock clock;
  late MemorySyncCollection groups;
  late MemorySyncCollection clips;
  late MemorySyncCollection todos;
  late MemorySyncCollection notes;
  late int clientsMade;

  setUp(() {
    server = FakeParseServer.memory();
    state = MemorySyncStateStore();
    clock = FixedClock(DateTime(2026, 10, 22, 9));
    groups = MemorySyncCollection('ClipGroup');
    clips = MemorySyncCollection('Clip');
    todos = MemorySyncCollection('TodoItem');
    notes = MemorySyncCollection('NoteItem');
    clientsMade = 0;
  });

  tearDown(() async {
    for (final collection in [groups, clips, todos, notes]) {
      await collection.close();
    }
  });

  ParseConfig config() => ParseConfig(
    appId: 'app',
    clientKey: 'key',
    serverUrl: server.url,
    space: 'nha',
  );

  ParseSyncEngine engine({int onePassMaxRows = 500}) => ParseSyncEngine(
    config: config(),
    state: state,
    channels: [
      SyncChannel.shared([groups, clips]),
      SyncChannel.single(todos),
      SyncChannel.single(notes),
    ],
    clock: clock,
    budget: budget,
    httpClientFactory: () {
      clientsMade++;
      return server.client(tag: 'may');
    },
    onePassMaxRows: onePassMaxRows,
  );

  String monthKey() => ParseSyncEngine.monthKey(clock.now());

  Future<void> setUsed(int requests) => state.write(monthKey(), '$requests');

  /// The engine's own keys: cursors, counters seen, the last full pull, the
  /// counter object. A cycle cut short must leave them as they were.
  Map<String, String> progress() => {
    for (final MapEntry(:key, :value) in state.values.entries)
      if (key.startsWith('sync_cursor_') ||
          key.startsWith('sync_rev_') ||
          key.startsWith('sync_full_at_') ||
          key.startsWith('sync_meta_id_') ||
          key == 'sync_last_at')
        key: value,
  };

  Set<String> decodeSet(String? raw) =>
      raw == null || raw.isEmpty ? {} : {...(jsonDecode(raw) as List).cast()};

  Map<String, Object?> remoteTodo(String localId) => {
    'space': 'nha',
    'localId': localId,
    'title': 'từ máy kia',
  };

  group('chu kỳ tự động giữ trong phần ngân sách của máy', () {
    test('đã dùng hết phần của máy: không gửi request nào, không ghi gì, '
        'trả paused', () async {
      final sync = engine();
      await sync.sync();
      todos.edit('t1', {'title': 'chưa đẩy'});
      notes.tombstones.add('obj-n-cu');
      server.requests.clear();

      for (final used in [budget.stopAt, budget.stopAt + 25]) {
        await setUsed(used);
        final before = {...state.values};
        final made = clientsMade;

        final status = await sync.sync(auto: true);

        expect(status.state, SyncState.paused);
        expect(status.message, ParseSyncEngine.budgetSpentMessage);
        expect(status.message, contains('hết ngân sách request tháng này'));
        expect(status.monthRequests, used);
        expect(server.requests, isEmpty);
        expect(clientsMade, made, reason: 'không cần cả client');
        expect(state.values, before);
        expect((await todos.dirtyRecords()).single.localId, 't1');
        expect(notes.tombstones, ['obj-n-cu']);
      }
    });

    test(
      'còn ít hơn số cần: dừng đúng khi chạm stopAt giữa lúc đẩy; phần '
      'chưa đẩy còn nguyên, lần bấm tay sau đẩy hết và vẫn được đếm',
      () async {
        final sync = engine();
        await sync.sync();
        final settled = progress();
        todos
          ..edit('t1', {'title': 'một'})
          ..edit('t2', {'title': 'hai'})
          ..edit('t3', {'title': 'ba'});
        notes.tombstones.add('obj-n-cu');
        notes.edit('n1', {'body': 'ghi chú'});
        await setUsed(budget.stopAt - 2);
        server.requests.clear();

        final status = await sync.sync(auto: true);

        expect(status.state, SyncState.paused);
        expect(status.message, ParseSyncEngine.budgetSpentMessage);
        expect(server.requests, ['POST TodoItem', 'POST TodoItem']);
        expect(status.monthRequests, budget.stopAt);
        expect(state.values[monthKey()], '${budget.stopAt}');
        expect([for (final r in await todos.dirtyRecords()) r.localId], ['t3']);
        expect(notes.tombstones, ['obj-n-cu']);
        expect((await notes.dirtyRecords()).single.localId, 'n1');
        // t3's create never went out, so it is not marked in flight.
        expect(decodeSet(state.values['sync_inflight']), isEmpty);
        // What did go out is announced by the next cycle's bump.
        expect(decodeSet(state.values['sync_meta_bump_nha']), {'TodoItem'});
        expect(await sync.hasLocalChanges(), isTrue);
        expect(progress(), settled);

        server.requests.clear();
        final manual = await sync.sync();

        expect(manual.state, SyncState.ok);
        expect(server.requests, [
          'POST TodoItem',
          'DELETE NoteItem',
          'POST NoteItem',
          'PUT SyncMeta',
          'GET SyncMeta',
        ]);
        expect(manual.monthRequests, budget.stopAt + 5);
        expect(await sync.requestsThisMonth(), budget.stopAt + 5);
        expect(await todos.dirtyRecords(), isEmpty);
        expect(notes.tombstones, isEmpty);
        expect(server.classOf('TodoItem'), hasLength(3));
        final meta = server.classOf('SyncMeta').values.single;
        expect(meta['rev_TodoItem'], 1);
        expect(meta['rev_NoteItem'], 1);
        // No one else wrote: the bump moved each counter by one, nothing pulled.
        expect(state.values['sync_rev_nha_TodoItem'], '1');
        expect(state.values['sync_rev_nha_NoteItem'], '1');
        expect(state.values['sync_meta_bump_nha'], '');
      },
    );

    test(
      'dừng ở bước tăng bộ đếm: bump còn trong hàng chờ, rev không đổi',
      () async {
        final sync = engine();
        await sync.sync();
        final settled = progress();
        todos.edit('t1', {'title': 'một'});
        await setUsed(budget.stopAt - 1);
        server.requests.clear();

        final status = await sync.sync(auto: true);

        expect(status.state, SyncState.paused);
        expect(server.requests, ['POST TodoItem']);
        expect(status.monthRequests, budget.stopAt);
        expect(await todos.dirtyRecords(), isEmpty);
        expect(decodeSet(state.values['sync_meta_bump_nha']), {'TodoItem'});
        expect(server.classOf('SyncMeta').values.single['rev_TodoItem'], 0);
        expect(progress(), settled);

        server.requests.clear();
        await sync.sync();

        expect(server.requests, ['PUT SyncMeta', 'GET SyncMeta']);
        expect(state.values['sync_rev_nha_TodoItem'], '1');
        expect(state.values['sync_meta_bump_nha'], '');
      },
    );

    test('dừng giữa lúc kéo một kênh: kênh đó chưa áp gì, cursor, rev và mốc '
        'pull đầy đủ giữ nguyên', () async {
      final sync = engine();
      await sync.sync();
      final settled = progress();
      server.seed('ClipGroup', {'space': 'nha', 'localId': 'g-kia'});
      server.seed('Clip', {'space': 'nha', 'localId': 'c-kia'});
      server.bump('nha', 'ClipGroup');
      server.bump('nha', 'Clip');
      await setUsed(budget.stopAt - 2);
      server.requests.clear();

      final status = await sync.sync(auto: true);

      expect(status.state, SyncState.paused);
      expect(server.requests, ['GET SyncMeta', 'GET ClipGroup']);
      expect(groups.applied, isEmpty);
      expect(clips.applied, isEmpty);
      expect(progress(), settled);

      await sync.sync();

      expect(groups.applied.single['localId'], 'g-kia');
      expect(clips.applied.single['localId'], 'c-kia');
      expect(state.values['sync_rev_nha_Clip'], '1');
      expect(
        state.values['sync_cursor_nha'],
        server.classOf('Clip').values.single['updatedAt'],
      );
    });

    test(
      'bấm tay khi đã quá phần của máy vẫn chạy đủ chu kỳ và được đếm',
      () async {
        final sync = engine();
        todos.edit('t1', {'title': 'một'});
        await setUsed(budget.stopAt + 10);

        final status = await sync.sync(full: true);

        expect(status.state, SyncState.ok);
        expect(server.classOf('TodoItem'), hasLength(1));
        expect(
          status.monthRequests,
          budget.stopAt + 10 + server.requests.length,
        );
      },
    );

    test('sang tháng mới: chu kỳ tự động đầu tiên chạy bình thường và đẩy '
        'phần còn tồn', () async {
      // Close enough to the month's end that no full pull falls due.
      clock.current = DateTime(2026, 10, 31, 23);
      final sync = engine();
      await sync.sync();
      todos.edit('t1', {'title': 'làm cuối tháng'});
      await setUsed(budget.stopAt);
      expect((await sync.sync(auto: true)).state, SyncState.paused);
      server.requests.clear();

      clock.current = DateTime(2026, 11, 1, 0, 0, 1);
      final status = await sync.sync(auto: true);

      expect(status.state, SyncState.ok);
      expect(status.pushed, 1);
      expect(await todos.dirtyRecords(), isEmpty);
      expect(server.requests, [
        'POST TodoItem',
        'PUT SyncMeta',
        'GET SyncMeta',
      ]);
      expect(status.monthRequests, 3);
      expect(state.values['sync_req_2026-11'], '3');
      expect(state.values['sync_req_2026-10'], '${budget.stopAt}');
    });
  });

  group('chu kỳ chỉ đẩy (checkRemote: false)', () {
    test('chỉ đẩy và tăng bộ đếm, không GET nào; rev tiến khi không ai khác '
        'ghi; sync_last_at vẫn được ghi', () async {
      final sync = engine();
      await sync.sync();
      todos.edit('t1', {'title': 'một'});
      clock.current = clock.current.add(const Duration(minutes: 1));
      server.requests.clear();

      final status = await sync.sync(auto: true, checkRemote: false);

      expect(status.state, SyncState.ok);
      expect(status.pushed, 1);
      expect(status.pulled, 0);
      expect(server.requests, ['POST TodoItem', 'PUT SyncMeta']);
      expect(state.values['sync_rev_nha_TodoItem'], '1');
      expect(
        state.values['sync_last_at'],
        '${clock.now().millisecondsSinceEpoch}',
      );
    });

    test(
      'máy khác đã ghi: rev giữ nguyên để lần kiểm server sau kéo về',
      () async {
        final sync = engine();
        await sync.sync();
        server.seed('TodoItem', remoteTodo('t-kia'));
        server.bump('nha', 'TodoItem');
        todos.edit('t1', {'title': 'một'});
        server.requests.clear();

        await sync.sync(auto: true, checkRemote: false, full: true);

        expect(server.requests.where((r) => r.startsWith('GET')), isEmpty);
        expect(state.values['sync_rev_nha_TodoItem'], '0');
        expect(todos.applied, isEmpty);

        server.requests.clear();
        await sync.sync(auto: true);

        expect(server.requests, ['GET SyncMeta', 'GET TodoItem']);
        expect([
          for (final json in todos.applied) json['localId'],
        ], contains('t-kia'));
        expect(state.values['sync_rev_nha_TodoItem'], '2');
      },
    );
  });

  group('pull đầy đủ theo ngân sách', () {
    test(
      'mức normal: đến hạn đúng ở fullPullEvery(normal), không sớm hơn',
      () async {
        final every = budget.fullPullEvery(SyncBudgetLevel.normal);
        expect(every, lessThanOrEqualTo(const Duration(hours: 24)));
        final sync = engine();
        final start = clock.now();
        await sync.sync();
        server.seed('TodoItem', remoteTodo('t-khong-bump'));

        clock.current = start.add(every - const Duration(minutes: 1));
        server.requests.clear();
        await sync.sync(auto: true);
        expect(server.requests, ['GET SyncMeta']);
        expect(todos.applied, isEmpty);

        clock.current = start.add(every);
        await sync.sync(auto: true);
        expect(todos.applied.single['localId'], 't-khong-bump');
        expect(
          state.values['sync_full_at_nha'],
          '${clock.now().millisecondsSinceEpoch}',
        );
      },
    );

    test('mức warning: khoảng dài hơn, tính theo mức lúc đầu chu kỳ', () async {
      final normal = budget.fullPullEvery(SyncBudgetLevel.normal);
      final warning = budget.fullPullEvery(SyncBudgetLevel.warning);
      expect(warning, greaterThan(normal));
      final sync = engine();
      final start = clock.now();
      await sync.sync();
      server.seed('TodoItem', remoteTodo('t-khong-bump'));
      await setUsed(budget.warnAt);

      clock.current = start.add(normal);
      server.requests.clear();
      await sync.sync(auto: true);
      expect(server.requests, ['GET SyncMeta']);

      clock.current = start.add(warning);
      await sync.sync(auto: true);
      expect(todos.applied.single['localId'], 't-khong-bump');
    });
  });

  group('kéo một lượt', () {
    test('class ít dòng: một GET cả class, không keys; chỉ áp dòng mới hơn '
        'cursor; cursor là updatedAt mới nhất', () async {
      final sync = engine();
      await sync.sync();
      server.seed('TodoItem', remoteTodo('t-a'));
      server.bump('nha', 'TodoItem');
      await sync.sync();
      expect(todos.applied.single['localId'], 't-a');

      final newest = server.seed('TodoItem', remoteTodo('t-b'));
      server.bump('nha', 'TodoItem');
      server.log.clear();
      todos.applied.clear();
      await sync.sync();

      final pulls = [
        for (final r in server.log)
          if (r.className == 'TodoItem') r,
      ];
      expect(pulls, hasLength(1));
      expect(pulls.single.method, 'GET');
      expect(pulls.single.query.containsKey('keys'), isFalse);
      expect(pulls.single.where, {'space': 'nha'});
      expect([for (final json in todos.applied) json['localId']], ['t-b']);
      expect(
        state.values['sync_cursor_nha_TodoItem'],
        server.classOf('TodoItem')[newest]!['updatedAt'],
      );
    });

    test('class từ onePassMaxRows dòng trở lên: query theo cursor rồi '
        'keys=localId như cũ', () async {
      final sync = engine(onePassMaxRows: 1);
      await sync.sync();
      server.seed('TodoItem', remoteTodo('t-a'));
      server.bump('nha', 'TodoItem');
      await sync.sync();
      final cursor = state.values['sync_cursor_nha_TodoItem'];

      server.seed('TodoItem', remoteTodo('t-b'));
      server.bump('nha', 'TodoItem');
      server.log.clear();
      todos.applied.clear();
      await sync.sync();

      final pulls = [
        for (final r in server.log)
          if (r.className == 'TodoItem') r,
      ];
      expect(pulls, hasLength(2));
      expect(pulls[0].query.containsKey('keys'), isFalse);
      expect(pulls[0].where, {
        'space': 'nha',
        'updatedAt': {
          r'$gt': {'__type': 'Date', 'iso': cursor},
        },
      });
      expect(pulls[1].query['keys'], 'localId');
      expect(pulls[1].where, {'space': 'nha'});
      expect([for (final json in todos.applied) json['localId']], ['t-b']);
    });

    for (final onePassMaxRows in [500, 0]) {
      test('bản ghi bị máy kia xoá biến mất ở lần kéo kênh đó '
          '(onePassMaxRows: $onePassMaxRows)', () async {
        final sync = engine(onePassMaxRows: onePassMaxRows);
        final gone = server.seed('TodoItem', remoteTodo('t-a'));
        server.seed('TodoItem', remoteTodo('t-b'));
        final goneClip = server.seed('Clip', {
          'space': 'nha',
          'localId': 'c-a',
        });
        server.seed('Clip', {'space': 'nha', 'localId': 'c-b'});
        await sync.sync();
        expect(todos.rows.keys, unorderedEquals(['t-a', 't-b']));
        expect(clips.rows.keys, unorderedEquals(['c-a', 'c-b']));

        server.classOf('TodoItem').remove(gone);
        server.classOf('Clip').remove(goneClip);
        server.bump('nha', 'TodoItem');
        server.bump('nha', 'Clip');
        await sync.sync();

        expect(todos.rows.keys, ['t-b']);
        expect(clips.rows.keys, ['c-b']);
      });
    }

    test('kênh chung: truy vấn hết rồi mới đối chiếu và áp, theo thứ tự '
        'ClipGroup rồi Clip, dưới cursor chung', () async {
      final sync = engine(onePassMaxRows: 1);
      server.seed('Clip', {'space': 'nha', 'localId': 'c-a'});
      await sync.sync();
      // ClipGroup has no synced row (one pass), Clip has one (two queries).
      server.seed('ClipGroup', {'space': 'nha', 'localId': 'g-kia'});
      final newest = server.seed('Clip', {
        'space': 'nha',
        'localId': 'c-b',
        'groupLocalId': 'g-kia',
      });
      server.bump('nha', 'ClipGroup');
      server.log.clear();
      await sync.sync();

      expect(
        [for (final r in server.log) '$r ${r.query['keys'] ?? ''}'.trim()],
        ['GET SyncMeta', 'GET ClipGroup', 'GET Clip', 'GET Clip localId'],
      );
      expect(groups.applied.single['localId'], 'g-kia');
      expect(clips.applied.last['localId'], 'c-b');
      expect(
        state.values['sync_cursor_nha'],
        server.classOf('Clip')[newest]!['updatedAt'],
      );
      expect(state.values.containsKey('sync_cursor_nha_Clip'), isFalse);
      expect(state.values.containsKey('sync_cursor_nha_ClipGroup'), isFalse);
    });
  });

  test('settings của bản cũ: chu kỳ tự động đầu tiên cộng tiếp bộ đếm, giữ '
      'nguyên key, kéo một lượt chỉ áp dòng mới hơn cursor', () async {
    final oldTodo = server.seed('TodoItem', remoteTodo('t-cu'));
    final metaId = server.seed('SyncMeta', {
      'space': 'nha',
      'rev_Clip': 3,
      'rev_ClipGroup': 1,
      'rev_TodoItem': 2,
      'rev_NoteItem': 5,
    });
    todos.rows['t-cu'] = MemoryRow(
      fields: {'localId': 't-cu'},
      remoteId: oldTodo,
      dirty: false,
    );
    final legacy = {
      'sync_meta_id_nha': metaId,
      'sync_rev_nha_Clip': '3',
      'sync_rev_nha_ClipGroup': '1',
      'sync_rev_nha_TodoItem': '2',
      'sync_rev_nha_NoteItem': '5',
      'sync_cursor_nha': '2026-01-01T00:00:01.000Z',
      'sync_cursor_nha_TodoItem':
          server.classOf('TodoItem')[oldTodo]!['updatedAt']! as String,
      'sync_cursor_nha_NoteItem': '2026-01-01T00:00:01.000Z',
      'sync_full_at_nha':
          '${clock.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
      'sync_meta_bump_nha': '',
      'sync_inflight': '[]',
      'sync_last_at':
          '${clock.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch}',
      'sync_req_2026-10': '41',
    };
    state.values.addAll(legacy);

    final idle = await engine().sync(auto: true);

    expect(idle.state, SyncState.ok);
    expect(server.requests, ['GET SyncMeta']);
    expect(idle.monthRequests, 42);
    for (final key in legacy.keys) {
      if (key == 'sync_req_2026-10' || key == 'sync_last_at') continue;
      expect(state.values[key], legacy[key], reason: key);
    }

    server.seed('TodoItem', remoteTodo('t-moi'));
    server.bump('nha', 'TodoItem');
    final status = await engine().sync(auto: true);

    expect(status.monthRequests, 44);
    expect([for (final json in todos.applied) json['localId']], ['t-moi']);
    expect(todos.rows.keys, unorderedEquals(['t-cu', 't-moi']));
  });

  test('mỗi chu kỳ lấy một client mới từ httpClientFactory; mọi request '
      'mang tag của máy', () async {
    final sync = engine();
    todos.edit('t1', {'title': 'một'});

    await sync.sync();
    await sync.sync(auto: true);

    expect(clientsMade, 2);
    expect(server.requests, isNotEmpty);
    expect(server.requestsBy('may'), server.requests);
    expect(server.requestsBy(null), isEmpty);
  });

  group('FakeParseServer', () {
    test('client trong bộ nhớ chạy được dưới fake_async', () {
      fakeAsync((async) {
        final sync = engine();
        todos.edit('t1', {'title': 'một'});
        SyncStatus? status;

        sync.sync(auto: true).then((value) => status = value);
        async.flushMicrotasks();

        expect(status?.state, SyncState.ok);
        expect(server.classOf('TodoItem'), hasLength(1));
        expect(async.elapsed, Duration.zero);
      });
    });

    test(
      'tôn trọng limit, skip và order: queryAll đi qua đủ các trang',
      () async {
        for (var i = 0; i < 1203; i++) {
          server.seed('TodoItem', {'space': 'nha', 'localId': 't$i'});
        }
        server.seed('TodoItem', {'space': 'khac', 'localId': 'ngoai'});
        final client = ParseClient(
          config(),
          httpClient: server.client(tag: 'q'),
        );
        addTearDown(client.close);

        final rows = await client.queryAll('TodoItem', where: {'space': 'nha'});

        expect(rows, hasLength(1203));
        expect({for (final row in rows) row['localId']}, hasLength(1203));
        final stamps = [for (final row in rows) row['updatedAt']! as String];
        expect(stamps, [...stamps]..sort());
        expect(server.requestsBy('q'), List.filled(3, 'GET TodoItem'));
        expect(
          [for (final r in server.log) r.query['skip']],
          ['0', '500', '1000'],
        );
      },
    );

    test('findOne theo createdAt trả object cũ nhất', () async {
      final first = server.seed('SyncMeta', {'space': 'nha'});
      server.seed('SyncMeta', {'space': 'nha'});
      final client = ParseClient(config(), httpClient: server.client());
      addTearDown(client.close);

      final row = await client.findOne(
        'SyncMeta',
        where: {'space': 'nha'},
        order: 'createdAt',
      );
      final newest = await client.findOne(
        'SyncMeta',
        where: {'space': 'nha'},
        order: '-createdAt',
      );

      expect(row!['objectId'], first);
      expect(newest!['objectId'], isNot(first));
    });
  });
}
