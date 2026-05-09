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

class ApiComment {
  final String id;
  final String stableUid;
  final String username;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ApiComment({
    required this.id,
    required this.stableUid,
    required this.username,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ApiComment.fromJson(Map<String, dynamic> j) {
    return ApiComment(
      id: j['id'] as String,
      stableUid: j['stableUid'] as String? ?? '',
      username: j['username'] as String? ?? 'Unbekannt',
      body: j['body'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  ApiClient._();
  static ApiClient get instance => _instance;

  // Persistent client — reuses TCP connections (HTTP keep-alive).
  final _client = http.Client();

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
    final headers = _headers;
    final bodyStr = body != null ? jsonEncode(body) : null;
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers).timeout(AppConfig.networkTimeout);
      case 'POST':
        return _client.post(uri, headers: headers, body: bodyStr).timeout(AppConfig.networkTimeout);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: bodyStr).timeout(AppConfig.networkTimeout);
      case 'DELETE':
        return _client.delete(uri, headers: headers).timeout(AppConfig.networkTimeout);
      default:
        throw UnsupportedError('Method $method not supported');
    }
  }

  // ── Comments ──────────────────────────────────────────────────────────────

  Future<List<ApiComment>> getReminderComments(String classId, String reminderId) async {
    final data = await get('/classes/$classId/reminders/$reminderId/comments') as List<dynamic>;
    return data.cast<Map<String, dynamic>>().map(ApiComment.fromJson).toList();
  }

  Future<ApiComment> createReminderComment(String classId, String reminderId, String body) async {
    final data = await post('/classes/$classId/reminders/$reminderId/comments', {'body': body}) as Map<String, dynamic>;
    return ApiComment.fromJson(data);
  }

  Future<void> deleteReminderComment(String classId, String reminderId, String commentId) async {
    await delete('/classes/$classId/reminders/$reminderId/comments/$commentId');
  }

  Future<List<ApiComment>> getDishComments(String dishId) async {
    final encoded = Uri.encodeComponent(dishId);
    final data = await get('/dish-comments/$encoded') as List<dynamic>;
    return data.cast<Map<String, dynamic>>().map(ApiComment.fromJson).toList();
  }

  Future<ApiComment> createDishComment(String dishId, String body) async {
    final encoded = Uri.encodeComponent(dishId);
    final data = await post('/dish-comments/$encoded', {'body': body}) as Map<String, dynamic>;
    return ApiComment.fromJson(data);
  }

  Future<void> deleteDishComment(String dishId, String commentId) async {
    final encoded = Uri.encodeComponent(dishId);
    await delete('/dish-comments/$encoded/$commentId');
  }

  dynamic _parse(http.Response res) {
    if (res.statusCode == 204) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = res.body;
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
