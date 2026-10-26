import 'dart:async';
import 'dart:math';

import 'package:event_notice/core/domain/clock.dart';
import 'package:event_notice/core/sync/data/parse_config.dart';
import 'package:event_notice/core/sync/data/parse_sync_engine.dart';
import 'package:event_notice/core/sync/data/state_store_sync_preferences.dart';
import 'package:event_notice/core/sync/domain/entities/sync_budget.dart';
import 'package:event_notice/core/sync/domain/entities/sync_settings.dart';
import 'package:event_notice/core/sync/domain/entities/sync_status.dart';
import 'package:event_notice/core/sync/domain/sync_channel.dart';
import 'package:event_notice/core/sync/domain/sync_engine.dart';
import 'package:event_notice/core/sync/domain/usecases/get_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/get_month_requests.dart';
import 'package:event_notice/core/sync/domain/usecases/get_sync_settings.dart';
import 'package:event_notice/core/sync/domain/usecases/has_pending_changes.dart';
import 'package:event_notice/core/sync/domain/usecases/run_sync.dart';
import 'package:event_notice/core/sync/domain/usecases/set_auto_sync_choice.dart';
import 'package:event_notice/core/sync/domain/usecases/watch_local_changes.dart';
import 'package:event_notice/core/sync/presentation/sync_controller.dart';
import 'package:fake_async/fake_async.dart';

import '../fake_parse_server.dart';
import '../fakes.dart';

/// A month of sync on several devices sharing one space, in fake time.
///
/// Every device runs the real [ParseSyncEngine] and [SyncController] against
/// one in-memory [FakeParseServer]; only the lists (four
/// [MemorySyncCollection]s), the settings store and the clock are stand-ins.
/// Nothing touches a socket or the disk, so a month runs in seconds.

/// Time as fake_async sees it, shared by every device, so the engines' month
/// and the controllers' timers move together.
class FakeClock implements Clock {
  FakeClock(this._async, this.start);

  final FakeAsync _async;
  final DateTime start;

  @override
  DateTime now() => start.add(_async.elapsed);
}

/// One call to [SyncEngine.sync], and what it cost.
class CycleRecord {
  const CycleRecord({
    required this.at,
    required this.full,
    required this.auto,
    required this.checkRemote,
    required this.levelBefore,
    required this.requests,
    required this.state,
  });

  final DateTime at;
  final bool full;
  final bool auto;
  final bool checkRemote;

  /// Where the device stood against the budget when the call began.
  final SyncBudgetLevel levelBefore;

  /// How far the call moved the device's monthly meter.
  final int requests;
  final SyncState state;
}

/// Passes every call through to the real engine, logging each [sync] call
/// with how far it moved the meter.
class MeteredSyncEngine implements SyncEngine {
  MeteredSyncEngine(
    this._inner, {
    required this.budget,
    required this.clock,
    required this.onCycle,
  });

  final SyncEngine _inner;
  final SyncBudget budget;
  final Clock clock;
  final void Function(CycleRecord record) onCycle;

  @override
  SyncSettings get settings => _inner.settings;

  @override
  Stream<void> get localChanges => _inner.localChanges;

  @override
  Future<bool> hasLocalChanges() => _inner.hasLocalChanges();

  @override
  Future<int> requestsThisMonth() => _inner.requestsThisMonth();

  @override
  Future<SyncStatus> sync({
    bool full = false,
    bool auto = false,
    bool checkRemote = true,
  }) async {
    final before = await _inner.requestsThisMonth();
    final status = await _inner.sync(
      full: full,
      auto: auto,
      checkRemote: checkRemote,
    );
    final after = await _inner.requestsThisMonth();
    onCycle(
      CycleRecord(
        at: clock.now(),
        full: full,
        auto: auto,
        checkRemote: checkRemote,
        levelBefore: budget.levelFor(before),
        requests: after - before,
        state: status.state,
      ),
    );
    return status;
  }
}

/// One device: its lists and settings live for the whole month; the engine
/// and the controller live for one app session, as they do in the app.
class SimDevice {
  SimDevice(
    this.name, {
    required this.server,
    required this.clock,
    required this.budget,
  });

  static const String space = 'nha';

  final String name;
  final FakeParseServer server;
  final Clock clock;
  final SyncBudget budget;

  final MemorySyncStateStore state = MemorySyncStateStore();
  final MemorySyncCollection groups = MemorySyncCollection('ClipGroup');
  final MemorySyncCollection clips = MemorySyncCollection('Clip');
  final MemorySyncCollection todos = MemorySyncCollection('TodoItem');
  final MemorySyncCollection notes = MemorySyncCollection('NoteItem');

  /// In push order, as the app registers them.
  List<MemorySyncCollection> get collections => [groups, clips, todos, notes];

  /// Every sync call of every session, in order.
  final List<CycleRecord> cycles = [];

  /// `objectId`s this device deleted, by class.
  final Map<String, Set<String>> deletedObjectIds = {};

  /// How long each burst of edits took to reach the server, counted from its
  /// last edit.
  final List<Duration> pushLatencies = [];

  /// When the edit still waiting to go out was made.
  DateTime? _unpushedSince;

  SyncController? controller;

  ParseConfig get _config => ParseConfig(
    appId: 'app',
    clientKey: 'key',
    serverUrl: server.url,
    space: space,
  );

  MeteredSyncEngine _engine() => MeteredSyncEngine(
    ParseSyncEngine(
      config: _config,
      state: state,
      channels: [
        SyncChannel.shared([groups, clips]),
        SyncChannel.single(todos),
        SyncChannel.single(notes),
      ],
      clock: clock,
      budget: budget,
      httpClientFactory: () => server.client(tag: name),
    ),
    budget: budget,
    clock: clock,
    onCycle: _onCycle,
  );

  void _onCycle(CycleRecord record) {
    cycles.add(record);
    final since = _unpushedSince;
    if (since != null && _isClean) {
      pushLatencies.add(record.at.difference(since));
      _unpushedSince = null;
    }
  }

  /// Nothing waits to go out: no edit, no delete, no counter bump.
  bool get _isClean =>
      collections.every(
        (c) => c.tombstones.isEmpty && c.rows.values.every((r) => !r.dirty),
      ) &&
      (state.values['sync_meta_bump_$space'] ?? '').isEmpty;

  /// Whether an edit made here has not reached the server yet.
  bool get hasUnpushed => _unpushedSince != null;

  /// Opens the app: a fresh engine and controller, then `start()`.
  void open() {
    assert(controller == null);
    final engine = _engine();
    final c = SyncController(
      runSync: RunSync(engine),
      hasPendingChanges: HasPendingChanges(engine),
      getMonthRequests: GetMonthRequests(engine),
      watchLocalChanges: WatchLocalChanges(engine),
      getSyncSettings: GetSyncSettings(engine),
      getAutoSyncChoice: GetAutoSyncChoice(StateStoreSyncPreferences(state)),
      setAutoSyncChoice: SetAutoSyncChoice(StateStoreSyncPreferences(state)),
      clock: clock,
      budget: budget,
    );
    controller = c;
    unawaited(c.start());
  }

  /// Closes the app.
  void close() {
    controller?.dispose();
    controller = null;
  }

  /// A manual full sync straight through an engine, outside any session.
  Future<SyncStatus> syncByHand() => _engine().sync(full: true);

  /// This month's meter, as the engine keeps it.
  int get meter =>
      int.tryParse(state.values[ParseSyncEngine.monthKey(clock.now())] ?? '') ??
      0;

  /// Requests the server logged from this device.
  int get serverRequests => server.requestsBy(name).length;

  int requestsWhere(bool Function(CycleRecord r) test) =>
      cycles.where(test).fold(0, (sum, r) => sum + r.requests);

  int get autoRequests => requestsWhere((r) => r.auto);
  int get manualRequests => requestsWhere((r) => !r.auto);

  /// When the first cycle found this device at [level], if one did.
  DateTime? firstCycleAt(SyncBudgetLevel level) =>
      cycles.where((r) => r.levelBefore == level).firstOrNull?.at;

  /// One edit by the user: creates, changes or deletes [count] rows of
  /// [collection].
  void edit(
    MemorySyncCollection collection,
    Random random, {
    required int count,
    required int serial,
  }) {
    for (var i = 0; i < count; i++) {
      final ids = collection.rows.keys.toList();
      final roll = random.nextInt(100);
      if (ids.isEmpty || roll < 25) {
        collection.edit('$name-${collection.className}-$serial-$i', {
          'text': 'tạo bởi $name #$serial',
        });
      } else if (roll < 50) {
        final localId = ids[random.nextInt(ids.length)];
        final remoteId = collection.rows[localId]!.remoteId;
        if (remoteId != null) {
          deletedObjectIds
              .putIfAbsent(collection.className, () => {})
              .add(remoteId);
        }
        collection.delete(localId);
      } else {
        final localId = ids[random.nextInt(ids.length)];
        // A row pulled from the server keeps Parse's fields here; the app's
        // own models never push them back.
        collection.rows[localId]!.fields.removeWhere(
          (key, _) => _bookkeeping.contains(key),
        );
        collection.edit(localId, {'text': 'sửa bởi $name #$serial'});
      }
    }
    _unpushedSince = clock.now();
  }

  Future<void> dispose() async {
    close();
    for (final collection in collections) {
      await collection.close();
    }
  }
}

/// What the users do each day.
class Workload {
  const Workload({
    required this.name,
    required this.focusPerDevicePerDay,
    required this.editsPerDay,
    this.manualPerDevicePerDay = 1,
    this.days = 30,
    this.devices = 3,
    this.seedRowsPerClass = 150,
  });

  /// The reference workload of the spec.
  static const Workload normal = Workload(
    name: 'thường',
    focusPerDevicePerDay: 20,
    editsPerDay: 20,
  );

  /// Ten times the focus and five times the edits.
  static const Workload heavy = Workload(
    name: 'nặng',
    focusPerDevicePerDay: 200,
    editsPerDay: 100,
  );

  final String name;
  final int focusPerDevicePerDay;

  /// Across every device; each edit touches 1-3 rows.
  final int editsPerDay;
  final int manualPerDevicePerDay;
  final int days;
  final int devices;

  /// Rows already on the server, per class, before the month starts.
  final int seedRowsPerClass;
}

/// The first day of the month the simulation runs in (31 days).
final DateTime simulationStart = DateTime(2026, 10, 1);

/// The app is in use from about 08:00 for this long each day.
const Duration activeWindow = Duration(hours: 12);

/// The classes, in the order edits rotate through them.
const List<String> simClasses = ['ClipGroup', 'Clip', 'TodoItem', 'NoteItem'];

/// Where the month left the devices and the server.
class Simulation {
  Simulation._(this.workload, this.server, this.devices);

  final Workload workload;
  final FakeParseServer server;
  final List<SimDevice> devices;

  /// Each device's meter when the last day ended, before any check by hand.
  final Map<String, int> metersAtEnd = {};

  /// Edits made in the month, counting each row touched.
  int rowEdits = 0;
}

/// Runs [workload] for a month, then [handSyncRounds] rounds of one manual
/// full sync per device, and hands back the devices and the server.
Simulation runSimulation(
  Workload workload, {
  int seed = 20261001,
  SyncBudget budget = SyncBudget.configured,
  int handSyncRounds = 1,
}) {
  final random = Random(seed);
  final server = FakeParseServer.memory();
  for (final className in simClasses) {
    for (var i = 0; i < workload.seedRowsPerClass; i++) {
      server.seed(className, {
        'space': SimDevice.space,
        'localId': 'seed-$className-$i',
        'text': 'có sẵn $i',
      });
    }
  }

  late Simulation simulation;
  fakeAsync((async) {
    final clock = FakeClock(async, simulationStart);
    final devices = [
      for (var i = 1; i <= workload.devices; i++)
        SimDevice('may$i', server: server, clock: clock, budget: budget),
    ];
    simulation = Simulation._(workload, server, devices);

    void runUntil(DateTime at) {
      final wait = at.difference(clock.now());
      if (wait > Duration.zero) async.elapse(wait);
      async.flushMicrotasks();
    }

    var editSerial = 0;
    for (var day = 0; day < workload.days; day++) {
      final morning = simulationStart.add(Duration(days: day, hours: 8));
      DateTime within(DateTime from, Duration span) =>
          from.add(Duration(seconds: 1 + random.nextInt(span.inSeconds - 1)));

      final events = <(DateTime, void Function())>[];
      final closes = <DateTime>[];
      for (final device in devices) {
        final open = morning.add(Duration(minutes: random.nextInt(15)));
        events.add((open, device.open));
        for (var i = 0; i < workload.focusPerDevicePerDay; i++) {
          events.add((
            within(open, activeWindow),
            () => device.controller?.onAppActive(),
          ));
        }
        for (var i = 0; i < workload.manualPerDevicePerDay; i++) {
          events.add((
            within(open, activeWindow),
            () => unawaited(device.controller?.syncNow(full: true)),
          ));
        }
        closes.add(open.add(activeWindow + const Duration(minutes: 30)));
      }
      // Edits fall where every device's session is open.
      final editsFrom = morning.add(const Duration(minutes: 15));
      for (var i = 0; i < workload.editsPerDay; i++) {
        final serial = editSerial++;
        final device = devices[serial % devices.length];
        final collection = device.collections[serial % simClasses.length];
        final count = 1 + random.nextInt(3);
        simulation.rowEdits += count;
        events.add((
          within(editsFrom, activeWindow - const Duration(minutes: 15)),
          () => device.edit(collection, random, count: count, serial: serial),
        ));
      }

      events.sort((a, b) => a.$1.compareTo(b.$1));
      for (final (at, action) in events) {
        runUntil(at);
        action();
        async.flushMicrotasks();
      }

      final close = closes.reduce((a, b) => a.isAfter(b) ? a : b);
      runUntil(close);
      for (final device in devices) {
        device.close();
      }
      async.flushMicrotasks();
    }

    for (final device in devices) {
      simulation.metersAtEnd[device.name] = device.meter;
    }

    // Then each device syncs by hand, one after the other.
    runUntil(clock.now().add(const Duration(hours: 1)));
    for (var round = 0; round < handSyncRounds; round++) {
      for (final device in devices) {
        unawaited(device.syncByHand());
        async.flushMicrotasks();
      }
    }

    for (final device in devices) {
      unawaited(device.dispose());
    }
    async.flushMicrotasks();
  });
  return simulation;
}

/// What a device or the server holds for one class: `localId` to the
/// object's content without Parse's bookkeeping, plus its `objectId`.
typedef ClassSnapshot = Map<String, Map<String, Object?>>;

const Set<String> _bookkeeping = {
  'objectId',
  'createdAt',
  'updatedAt',
  'space',
  'ACL',
};

Map<String, Object?> _content(String? objectId, Map<String, Object?> fields) =>
    {
      for (final MapEntry(:key, :value) in fields.entries)
        if (!_bookkeeping.contains(key)) key: value,
      'objectId': objectId,
    };

/// [device]'s rows of [className].
ClassSnapshot deviceSnapshot(SimDevice device, String className) {
  final collection = device.collections.firstWhere(
    (c) => c.className == className,
  );
  return {
    for (final MapEntry(:key, :value) in collection.rows.entries)
      key: _content(value.remoteId, value.fields),
  };
}

/// The server's objects of [className] in the simulated space.
ClassSnapshot serverSnapshot(FakeParseServer server, String className) => {
  for (final MapEntry(key: objectId, value: object)
      in server.classOf(className).entries)
    if (object['space'] == SimDevice.space)
      object['localId']! as String: _content(objectId, object),
};

/// Requests [tag] sent, by kind, for the table in the docs.
Map<String, int> requestKinds(FakeParseServer server, String tag) {
  final kinds = <String, int>{};
  for (final request in server.log) {
    if (request.tag != tag) continue;
    final meta = request.className == ParseSyncEngine.metaClass;
    final kind = switch (request.method) {
      'GET' when meta => 'GET SyncMeta',
      'GET' when request.query.containsKey('keys') => 'GET ids',
      'GET' => 'GET dữ liệu',
      _ when meta => 'ghi SyncMeta',
      _ => 'ghi dữ liệu',
    };
    kinds[kind] = (kinds[kind] ?? 0) + 1;
  }
  return kinds;
}

/// A table of what each device spent, as Markdown.
String requestTable(Simulation simulation, SyncBudget budget) {
  const kinds = [
    'GET SyncMeta',
    'GET dữ liệu',
    'GET ids',
    'ghi dữ liệu',
    'ghi SyncMeta',
  ];
  final days = simulation.workload.days;
  final rows = <String>[
    '| Máy | Tổng (30 ngày) | /ngày | Tự động | Bấm tay | '
        '${kinds.join(' | ')} | % phần của máy |',
    '|---|---|---|---|---|${List.filled(kinds.length, '---').join('|')}|---|',
  ];
  var total = 0;
  for (final device in simulation.devices) {
    final used = simulation.metersAtEnd[device.name]!;
    total += used;
    final byKind = requestKinds(simulation.server, device.name);
    final auto = device.autoRequests;
    rows.add(
      '| ${device.name} | $used | ${(used / days).toStringAsFixed(1)} | '
      '$auto | ${used - auto} | '
      '${kinds.map((k) => byKind[k] ?? 0).join(' | ')} | '
      '${(100 * used / budget.deviceShare).toStringAsFixed(1)}% |',
    );
  }
  rows.add(
    '| Cả ${simulation.devices.length} máy | $total | '
    '${(total / days).toStringAsFixed(1)} | | | '
    '${List.filled(kinds.length, '').join(' | ')} | '
    '${(100 * total / budget.monthlyRequests).toStringAsFixed(1)}% ngân sách |',
  );
  for (final device in simulation.devices) {
    String day(SyncBudgetLevel level) {
      final at = device.firstCycleAt(level);
      return at == null ? 'không' : 'ngày ${at.day}';
    }

    rows.add(
      '${device.name}: chu kỳ đầu tiên ở mức cảnh báo: '
      '${day(SyncBudgetLevel.warning)}; ở mức hết phần: '
      '${day(SyncBudgetLevel.exhausted)}',
    );
  }
  return rows.join('\n');
}
