import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiException implements Exception {
  const ApiException(this.message, this.statusCode,
      {this.code, this.fieldErrors = const {}});
  final String message;
  final int statusCode;
  final String? code;
  final Map<String, String> fieldErrors;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.token});
  final String? token;
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token'
      };
  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body);
  Future<dynamic> patch(String path, [Object? body]) =>
      _send('PATCH', path, body);
  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    late http.Response response;
    try {
      response = switch (method) {
        'POST' =>
          await http.post(uri, headers: _headers, body: jsonEncode(body ?? {})),
        'PATCH' => await http.patch(uri,
            headers: _headers, body: jsonEncode(body ?? {})),
        _ => await http.get(uri, headers: _headers),
      };
    } catch (_) {
      throw const ApiException(
        'Cannot reach the Soul Serve server. Check that the Go API is running.',
        0,
        code: 'network_error',
      );
    }
    dynamic data;
    try {
      data = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'The server returned an unreadable response.',
        response.statusCode,
        code: 'invalid_response',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = data is Map ? data : const {};
      final rawFields = payload['fields'];
      final fields = rawFields is Map
          ? rawFields
              .map((key, value) => MapEntry(key.toString(), value.toString()))
          : const <String, String>{};
      throw ApiException(
        payload['error']?.toString() ?? 'Request failed',
        response.statusCode,
        code: payload['code']?.toString(),
        fieldErrors: fields,
      );
    }
    return data;
  }
}
