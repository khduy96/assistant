import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// One request a [FakeParseServer] received.
class FakeRequest {
  const FakeRequest({
    required this.tag,
    required this.method,
    required this.className,
    required this.query,
  });

  /// The tag of the [FakeParseServer.client] that sent it; null over HTTP.
  final String? tag;
  final String method;
  final String className;
  final Map<String, String> query;

  /// `where`, decoded; empty when there was none.
  Map<String, Object?> get where => query['where'] == null
      ? const {}
      : jsonDecode(query['where']!) as Map<String, Object?>;

  @override
  String toString() => '$method $className';
}

/// A stand-in Parse server, so the sync wiring is proven without an account.
///
/// Stores objects in memory and honours the small slice of the Parse REST API
/// the app uses: equality `where`, the `updatedAt > iso` cursor, `keys`,
/// `order`, `limit`, `skip`, and create/update/delete.
///
/// Reach it over HTTP ([start], [url]) or, with no socket at all, through
/// [client] — which also runs under fake_async.
class FakeParseServer {
  FakeParseServer(HttpServer server) : _server = server {
    server.listen(_serve);
  }

  /// A server reached only through [client].
  FakeParseServer.memory() : _server = null;

  static Future<FakeParseServer> start() async =>
      FakeParseServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer? _server;

  /// Parse's answer to a query without `limit`.
  static const int defaultLimit = 100;

  /// className -> objectId -> object
  final Map<String, Map<String, Map<String, Object?>>> objects = {};
  final List<String> deletedIds = [];

  /// Every request received, as `METHOD className`, to check what a sync
  /// cycle spends against the budget.
  final List<String> requests = [];

  /// Every request received, with who sent it and its query.
  final List<FakeRequest> log = [];

  int _counter = 0;
  int _clock = 0;

  /// The server's address. A [FakeParseServer.memory] server answers [client]
  /// on any address, so it hands out a placeholder.
  String get url {
    final server = _server;
    if (server == null) return 'http://parse.fake';
    return 'http://${server.address.address}:${server.port}';
  }

  /// An HTTP client that talks to this server in memory, without a socket.
  /// Each request it sends is logged under [tag].
  http.Client client({String? tag}) => MockClient((request) async {
    final (status, body) = _handle(
      request.method,
      request.url,
      request.body,
      tag: tag,
    );
    return http.Response.bytes(
      utf8.encode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  /// The requests sent through [client] with [tag], as `METHOD className`.
  List<String> requestsBy(String? tag) => [
    for (final request in log)
      if (request.tag == tag) '$request',
  ];

  Map<String, Map<String, Object?>> classOf(String className) =>
      objects.putIfAbsent(className, () => {});

  /// Inserts an object as if another device had pushed it.
  String seed(String className, Map<String, Object?> data) {
    final id = 'obj${++_counter}';
    final stamp = _stamp();
    classOf(className)[id] = {
      ...data,
      'objectId': id,
      'createdAt': stamp,
      'updatedAt': stamp,
    };
    return id;
  }

  /// Bumps a class's change counter, as another device does after a push.
  void bump(String space, String className) {
    final metas = classOf('SyncMeta');
    final meta = metas.values.where((m) => m['space'] == space).firstOrNull ??
        metas[seed('SyncMeta', {'space': space})]!;
    final field = 'rev_$className';
    meta[field] = ((meta[field] as num?) ?? 0) + 1;
  }

  /// Applies Parse operators (`Increment`) and returns the fields they set,
  /// which Parse echoes back in its answer.
  Map<String, Object?> _applyOps(
      Map<String, Object?> target, Map<String, Object?> body) {
    final echoed = <String, Object?>{};
    for (final entry in body.entries) {
      final value = entry.value;
      if (value is Map && value['__op'] == 'Increment') {
        final next =
            ((target[entry.key] as num?) ?? 0) + (value['amount'] as num);
        target[entry.key] = next;
        echoed[entry.key] = next;
      } else {
        target[entry.key] = value;
      }
    }
    return echoed;
  }

  /// Monotonic ISO timestamps keep cursor comparisons deterministic.
  String _stamp() {
    _clock++;
    return DateTime.utc(2026, 1, 1).add(Duration(seconds: _clock)).toIso8601String();
  }

  Future<void> _serve(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final (status, text) = _handle(request.method, request.uri, body);
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(text);
    await request.response.close();
  }

  static const String _notFound = '{"code":101,"error":"Object not found."}';

  /// Answers one request with its status and JSON body.
  (int, String) _handle(String method, Uri uri, String body, {String? tag}) {
    final segments = uri.pathSegments;
    final at = segments.indexOf('classes');
    final className = segments[at + 1];
    final objectId = segments.length > at + 2 ? segments[at + 2] : null;
    final store = classOf(className);
    requests.add('$method $className');
    log.add(
      FakeRequest(
        tag: tag,
        method: method,
        className: className,
        query: uri.queryParameters,
      ),
    );

    switch (method) {
      case 'POST':
        final id = 'obj${++_counter}';
        final row = <String, Object?>{};
        _applyOps(row, jsonDecode(body) as Map<String, Object?>);
        final stamp = _stamp();
        store[id] = {
          ...row,
          'objectId': id,
          'createdAt': stamp,
          'updatedAt': stamp,
        };
        return (201, jsonEncode({'objectId': id, 'createdAt': stamp}));
      case 'PUT':
        final row = store[objectId];
        if (row == null) return (400, _notFound);
        final echoed =
            _applyOps(row, jsonDecode(body) as Map<String, Object?>);
        row['updatedAt'] = _stamp();
        return (200, jsonEncode({'updatedAt': row['updatedAt'], ...echoed}));
      case 'DELETE':
        if (store.remove(objectId) == null) return (400, _notFound);
        deletedIds.add(objectId!);
        return (200, '{}');
      default:
        return (
          200,
          jsonEncode({'results': _query(store, uri.queryParameters)}),
        );
    }
  }

  List<Map<String, Object?>> _query(
    Map<String, Map<String, Object?>> store,
    Map<String, String> query,
  ) {
    final where = query['where'] == null
        ? const <String, Object?>{}
        : jsonDecode(query['where']!) as Map<String, Object?>;
    final rows = store.values.where((row) => _matches(row, where)).toList();

    final order = query['order'];
    if (order != null) {
      final descending = order.startsWith('-');
      final field = descending ? order.substring(1) : order;
      rows.sort((a, b) {
        var result = '${a[field] ?? ''}'.compareTo('${b[field] ?? ''}');
        if (result == 0) {
          result = '${a['objectId']}'.compareTo('${b['objectId']}');
        }
        return descending ? -result : result;
      });
    }

    final skip = int.tryParse(query['skip'] ?? '') ?? 0;
    final limit = int.tryParse(query['limit'] ?? '') ?? defaultLimit;
    final keys = query['keys']?.split(',');
    return [
      for (final row in rows.skip(skip).take(limit))
        keys == null
            ? row
            : {
                for (final key in [
                  ...keys,
                  'objectId',
                  'createdAt',
                  'updatedAt',
                ])
                  if (row.containsKey(key)) key: row[key],
              },
    ];
  }

  bool _matches(Map<String, Object?> row, Map<String, Object?> where) {
    for (final entry in where.entries) {
      final expected = entry.value;
      if (expected is Map && expected[r'$gt'] != null) {
        final iso = (expected[r'$gt'] as Map)['iso'] as String;
        if ('${row[entry.key] ?? ''}'.compareTo(iso) <= 0) return false;
      } else if (row[entry.key] != expected) {
        return false;
      }
    }
    return true;
  }

  Future<void> stop() async => _server?.close(force: true);
}
