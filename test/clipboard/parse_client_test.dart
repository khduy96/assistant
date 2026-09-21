import 'dart:convert';
import 'dart:io';

import 'package:event_notice/clipboard/sync/parse_client.dart';
import 'package:event_notice/clipboard/sync/parse_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// A stand-in Parse server, so the REST wiring is proven without an account.
class FakeParse {
  FakeParse(this._server) {
    _server.listen(_handle);
  }

  static Future<FakeParse> start() async =>
      FakeParse(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<HttpRequest> seen = [];
  final List<Map<String, Object?>> created = [];
  final List<String> updated = [];
  final List<String> deleted = [];
  final Map<String, List<Map<String, Object?>>> pages = {};
  int status = 200;
  String? errorMessage;
  int? errorCode;

  String get url => 'http://${_server.address.address}:${_server.port}';

  Future<void> _handle(HttpRequest request) async {
    seen.add(request);
    final body = await utf8.decodeStream(request);
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;

    if (status != 200) {
      request.response.statusCode = status;
      request.response.write(jsonEncode({
        'error': errorMessage,
        if (errorCode != null) 'code': errorCode,
      }));
      return request.response.close();
    }

    if (request.method == 'DELETE') {
      deleted.add(path.split('/').last);
      request.response.write('{}');
      return request.response.close();
    }

    if (request.method == 'POST') {
      created.add(jsonDecode(body) as Map<String, Object?>);
      request.response.write(jsonEncode({'objectId': 'obj${created.length}'}));
      return request.response.close();
    }

    if (request.method == 'PUT') {
      updated.add(path.split('/').last);
      request.response.write(jsonEncode({'updatedAt': '2026-01-01T00:00:00Z'}));
      return request.response.close();
    }

    // GET: serve one page at a time, keyed by the `skip` parameter.
    final skip = request.uri.queryParameters['skip'] ?? '0';
    request.response.write(jsonEncode({'results': pages[skip] ?? const []}));
    return request.response.close();
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late FakeParse server;
  late ParseClient client;

  setUp(() async {
    server = await FakeParse.start();
    client = ParseClient(ParseConfig(
      appId: 'app-id',
      clientKey: 'client-key',
      serverUrl: server.url,
      space: 'nha',
    ));
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('mọi yêu cầu đều kèm App ID và Client Key', () async {
    await client.ping();
    expect(server.seen.single.headers.value('X-Parse-Application-Id'), 'app-id');
    expect(server.seen.single.headers.value('X-Parse-Client-Key'), 'client-key');
  });

  test('queryAll lấy hết các trang', () async {
    List<Map<String, Object?>> page(int from, int count) => [
          for (var i = 0; i < count; i++) {'localId': 'id${from + i}'},
        ];
    // Trang đầy (500) nghĩa là còn nữa; trang thiếu là trang cuối.
    server.pages['0'] = page(0, 500);
    server.pages['500'] = page(500, 7);

    final results = await client.queryAll('Clip', where: {'space': 'nha'});
    expect(results, hasLength(507));
    expect(results.last['localId'], 'id506');
  });

  test('where được gửi lên dưới dạng JSON', () async {
    await client.queryAll('Clip', where: {'space': 'nha'});
    final query = server.seen.first.uri.queryParameters;
    expect(jsonDecode(query['where']!), {'space': 'nha'});
  });

  test('create trả objectId, update gọi đúng đối tượng', () async {
    final id = await client.create('Clip', {'localId': 'a'});
    expect(id, 'obj1');
    expect(server.created.single['localId'], 'a');

    await client.update('Clip', 'obj1', {'content': 'b'});
    expect(server.updated, ['obj1']);
  });

  test('lỗi từ server nổi lên kèm thông báo của Parse', () async {
    server.status = 401;
    server.errorMessage = 'unauthorized';
    await expectLater(
      client.ping(),
      throwsA(isA<ParseException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'unauthorized')),
    );
  });

  test('delete gọi đúng object và bỏ qua object đã biến mất', () async {
    await client.delete('Clip', 'obj9');
    expect(server.deleted, ['obj9']);

    // Object đã bị xoá trước đó: Parse trả 101, coi như thành công.
    server.status = 400;
    server.errorMessage = 'Object not found.';
    server.errorCode = 101;
    await client.delete('Clip', 'obj9');
  });

  test('keys giới hạn cột trả về cho bước đối chiếu xoá', () async {
    await client.queryAll('Clip', where: {'space': 'nha'}, keys: const ['localId']);
    expect(server.seen.first.uri.queryParameters['keys'], 'localId');
  });

  test('giữ mã lỗi Parse trong body, không chỉ HTTP status', () async {
    // Parse hay trả 400 kèm code 101 cho "object not found".
    server.status = 400;
    server.errorMessage = 'Object not found.';
    server.errorCode = 101;
    await expectLater(
      client.update('Clip', 'obj-đã-bị-xoá', {'content': 'x'}),
      throwsA(isA<ParseException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.code, 'code', 101)),
    );
  });
}
