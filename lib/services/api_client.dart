import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  ApiClient._();
  static ApiClient get instance => _instance;

  Map<String, String> get _headers {
    final token = AuthService.instance.jwtToken;
    return {
      'Content-Type': 'application/json',
      'X-API-Key': AppConfig.backendApiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path) => _request('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _request('POST', path, body);
  Future<dynamic> patch(String path, [Object? body]) => _request('PATCH', path, body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  Future<dynamic> _request(String method, String path, [Object? body]) async {
    final uri = Uri.parse('${AppConfig.backendUrl}$path');
    final response = await _send(method, uri, body);

    if (response.statusCode == 401) {
      final refreshed = await AuthService.instance.refreshJwt();
      if (refreshed) {
        final retry = await _send(method, uri, body);
        return _parse(retry);
      }
      throw ApiException(401, 'Session abgelaufen');
    }

    return _parse(response);
  }

  Future<http.Response> _send(String method, Uri uri, Object? body) {
    final bodyStr = body != null ? jsonEncode(body) : null;
    switch (method) {
      case 'GET':
        return http.get(uri, headers: _headers).timeout(AppConfig.networkTimeout);
      case 'POST':
        return http.post(uri, headers: _headers, body: bodyStr).timeout(AppConfig.networkTimeout);
      case 'PATCH':
        return http.patch(uri, headers: _headers, body: bodyStr).timeout(AppConfig.networkTimeout);
      case 'DELETE':
        return http.delete(uri, headers: _headers).timeout(AppConfig.networkTimeout);
      default:
        throw UnsupportedError('Method $method not supported');
    }
  }

  dynamic _parse(http.Response res) {
    if (res.statusCode == 204) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = res.body.trim();
      if (body.isEmpty) return null;
      return jsonDecode(body);
    }
    String msg = '${res.statusCode}';
    try {
      final err = jsonDecode(res.body) as Map<String, dynamic>;
      msg = err['message'] as String? ?? msg;
    } catch (_) {}
    throw ApiException(res.statusCode, msg);
  }
}
