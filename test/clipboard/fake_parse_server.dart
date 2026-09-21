import 'dart:convert';
import 'dart:io';

/// A stand-in Parse server, so the sync wiring is proven without an account.
///
/// Stores objects in memory and honours the small slice of the Parse REST API
/// the app uses: equality `where`, the `updatedAt > iso` cursor, `keys`, and
/// create/update/delete.
class FakeParseServer {
  FakeParseServer(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeParseServer> start() async =>
      FakeParseServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// className -> objectId -> object
  final Map<String, Map<String, Map<String, Object?>>> objects = {};
  final List<String> deletedIds = [];

  int _counter = 0;
  int _clock = 0;

  String get url => 'http://${_server.address.address}:${_server.port}';

  Map<String, Map<String, Object?>> classOf(String className) =>
      objects.putIfAbsent(className, () => {});

  /// Inserts an object as if another device had pushed it.
  String seed(String className, Map<String, Object?> data) {
    final id = 'obj${++_counter}';
    classOf(className)[id] = {...data, 'objectId': id, 'updatedAt': _stamp()};
    return id;
  }

  /// Monotonic ISO timestamps keep cursor comparisons deterministic.
  String _stamp() {
    _clock++;
    return DateTime.utc(2026, 1, 1).add(Duration(seconds: _clock)).toIso8601String();
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final segments = request.uri.pathSegments;
    request.response.headers.contentType = ContentType.json;

    final className = segments[1];
    final objectId = segments.length > 2 ? segments[2] : null;
    final store = classOf(className);

    switch (request.method) {
      case 'POST':
        final id = 'obj${++_counter}';
        store[id] = {
          ...jsonDecode(body) as Map<String, Object?>,
          'objectId': id,
          'updatedAt': _stamp(),
        };
        request.response.write(jsonEncode({'objectId': id}));
      case 'PUT':
        if (!store.containsKey(objectId)) {
          request.response.statusCode = 400;
          request.response.write(
              jsonEncode({'code': 101, 'error': 'Object not found.'}));
          break;
        }
        store[objectId!] = {
          ...store[objectId]!,
          ...jsonDecode(body) as Map<String, Object?>,
          'updatedAt': _stamp(),
        };
        request.response.write(jsonEncode({'updatedAt': _stamp()}));
      case 'DELETE':
        if (store.remove(objectId) == null) {
          request.response.statusCode = 400;
          request.response.write(
              jsonEncode({'code': 101, 'error': 'Object not found.'}));
          break;
        }
        deletedIds.add(objectId!);
        request.response.write('{}');
      default:
        final query = request.uri.queryParameters;
        final where = query['where'] == null
            ? const <String, Object?>{}
            : jsonDecode(query['where']!) as Map<String, Object?>;
        final keys = query['keys']?.split(',');
        final results = store.values
            .where((row) => _matches(row, where))
            .map((row) => keys == null
                ? row
                : {
                    for (final key in [...keys, 'objectId', 'updatedAt'])
                      if (row.containsKey(key)) key: row[key],
                  })
            .toList();
        request.response.write(jsonEncode({'results': results}));
    }
    await request.response.close();
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

  Future<void> stop() => _server.close(force: true);
}
