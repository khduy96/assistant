import 'dart:convert';

import 'package:http/http.dart' as http;

import 'parse_config.dart';

/// Thrown for any non-2xx answer from Back4App, with the Parse error message.
class ParseException implements Exception {
  ParseException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;

  /// Parse's own error code from the body, e.g. 101 for "object not found".
  /// More reliable than the HTTP status, which Parse often reports as 400.
  final int? code;

  @override
  String toString() =>
      'Back4App ($statusCode${code == null ? '' : '/$code'}): $message';
}

/// Thin REST wrapper over the Parse API — enough for the two object classes.
///
/// REST is used instead of the Parse SDK so the sync logic stays explicit and
/// testable, and so nothing extra runs in the background without being asked.
class ParseClient {
  ParseClient(this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final ParseConfig config;
  final http.Client _http;

  static const Duration _timeout = Duration(seconds: 30);

  Map<String, String> get _jsonHeaders => {
        ...config.headers,
        'Content-Type': 'application/json',
      };

  /// Queries a class, following Parse paging until everything is fetched.
  Future<List<Map<String, Object?>>> queryAll(
    String className, {
    required Map<String, Object?> where,
    String order = 'updatedAt',
    int pageSize = 500,
    List<String>? keys,
  }) async {
    final results = <Map<String, Object?>>[];
    var skip = 0;
    while (true) {
      final uri = config.classUri(className, {
        'where': jsonEncode(where),
        'order': order,
        'limit': '$pageSize',
        'skip': '$skip',
        // `keys` keeps the reconcile pass cheap: ids only, no content.
        if (keys != null) 'keys': keys.join(','),
      });
      final body = await _get(uri);
      final page = (body['results'] as List<dynamic>? ?? [])
          .cast<Map<String, Object?>>();
      results.addAll(page);
      if (page.length < pageSize) break;
      skip += page.length;
    }
    return results;
  }

  Future<Map<String, Object?>?> findOne(
    String className, {
    required Map<String, Object?> where,
  }) async {
    final uri = config.classUri(className, {
      'where': jsonEncode(where),
      'limit': '1',
    });
    final body = await _get(uri);
    final results =
        (body['results'] as List<dynamic>? ?? []).cast<Map<String, Object?>>();
    return results.isEmpty ? null : results.first;
  }

  /// Creates an object and returns its `objectId`.
  Future<String> create(
      String className, Map<String, Object?> data) async {
    final response = await _http
        .post(config.classUri(className),
            headers: _jsonHeaders, body: jsonEncode(data))
        .timeout(_timeout);
    final body = _decode(response);
    return body['objectId'] as String;
  }

  Future<void> update(
      String className, String objectId, Map<String, Object?> data) async {
    final response = await _http
        .put(config.objectUri(className, objectId),
            headers: _jsonHeaders, body: jsonEncode(data))
        .timeout(_timeout);
    _decode(response);
  }

  /// Removes an object for good. An already-missing object counts as success,
  /// so a repeated delete does not block the queue.
  Future<void> delete(String className, String objectId) async {
    final response = await _http
        .delete(config.objectUri(className, objectId), headers: _jsonHeaders)
        .timeout(_timeout);
    try {
      _decode(response);
    } on ParseException catch (error) {
      if (error.code != 101 && error.statusCode != 404) rethrow;
    }
  }

  /// A cheap round trip used by `tool/check_parse.dart`.
  Future<void> ping() async {
    await _get(config.classUri('Clip', {'limit': '1'}));
  }

  Future<Map<String, Object?>> _get(Uri uri) async {
    final response =
        await _http.get(uri, headers: config.headers).timeout(_timeout);
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    final text = response.body.isEmpty ? '{}' : response.body;
    final decoded = jsonDecode(text);
    final body =
        decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    if (response.statusCode >= 300) {
      throw ParseException(
        response.statusCode,
        (body['error'] as String?) ?? response.reasonPhrase ?? 'Lỗi không rõ',
        code: (body['code'] as num?)?.toInt(),
      );
    }
    return body;
  }

  void close() => _http.close();
}
