// Kiểm tra cấu hình Back4App trong .env mà không cần mở app.
//
//   dart run tool/check_parse.dart
//
// Đọc thẳng .env (không qua --dart-define) và gọi thử hai class Clip/ClipGroup,
// rồi báo đúng chỗ cần sửa trên Back4App. Không in ra khoá.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? '.env' : args.first;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Không thấy $path — copy .env.example rồi điền khoá.');
    exit(2);
  }

  final env = _readEnv(file);
  final appId = _clean(env['PARSE_APP_ID']);
  final clientKey = _clean(env['PARSE_CLIENT_KEY']);
  final serverUrl = _clean(env['PARSE_SERVER_URL']).isEmpty
      ? 'https://parseapi.back4app.com'
      : _clean(env['PARSE_SERVER_URL']);
  final space = _clean(env['PARSE_SPACE']).isEmpty
      ? 'default'
      : _clean(env['PARSE_SPACE']);

  stdout.writeln('Server : $serverUrl');
  stdout.writeln('App ID : ${_mask(appId)}');
  stdout.writeln('Client : ${_mask(clientKey)}');
  stdout.writeln('Space  : $space');
  if (env.containsKey('PARSE_REST_API_KEY')) {
    stdout.writeln('CẢNH BÁO: $path còn PARSE_REST_API_KEY. Khoá này đi vào '
        'lệnh build nếu nạp bằng --dart-define-from-file. Chuyển sang '
        '.env.server (xem .env.server.example).');
  }
  if (appId.isEmpty || clientKey.isEmpty) {
    stderr.writeln('\nChưa điền App ID / Client Key — app sẽ chạy cục bộ.');
    exit(2);
  }

  final client = HttpClient();
  var failed = false;
  for (final className in ['Clip', 'ClipGroup']) {
    final uri = Uri.parse('${serverUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/classes/$className?count=1&limit=0&where=${Uri.encodeComponent(
      jsonEncode({'space': space}),
    )}');
    try {
      final request = await client.getUrl(uri);
      request.headers.set('X-Parse-Application-Id', appId);
      request.headers.set('X-Parse-Client-Key', clientKey);
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      if (response.statusCode == 200) {
        final rows = (jsonDecode(body)['count'] as num?)?.toInt() ?? 0;
        stdout.writeln('OK   $className — đọc được ($rows bản ghi trong space)');
      } else {
        failed = true;
        stdout.writeln('LỖI  $className — HTTP ${response.statusCode}: '
            '${_explain(body)}');
      }
    } catch (error) {
      failed = true;
      stdout.writeln('LỖI  $className — $error');
    }
  }
  client.close();
  exit(failed ? 1 : 0);
}

Map<String, String> _readEnv(File file) {
  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final text = line.trim();
    if (text.isEmpty || text.startsWith('#')) continue;
    final index = text.indexOf('=');
    if (index <= 0) continue;
    env[text.substring(0, index).trim()] = text.substring(index + 1).trim();
  }
  return env;
}

String _clean(String? value) {
  final text = value?.trim() ?? '';
  return text.startsWith('YOUR_') ? '' : text;
}

String _mask(String value) =>
    value.isEmpty ? '(trống)' : '${value.substring(0, 4)}…(${value.length})';

/// Dịch các lỗi Parse hay gặp khi chưa mở quyền cho client chưa đăng nhập.
String _explain(String body) {
  try {
    final json = jsonDecode(body) as Map<String, Object?>;
    final code = json['code'];
    final error = json['error'];
    final hint = switch (code) {
      119 => ' → bật quyền Find/Get cho Public trong Class Level Permissions',
      101 => ' → class chưa tồn tại; app sẽ tự tạo ở lần đồng bộ đầu nếu bật '
          'Allow Client Class Creation',
      _ => '',
    };
    return '$error$hint';
  } catch (_) {
    return body;
  }
}
