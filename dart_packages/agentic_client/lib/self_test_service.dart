import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_type.dart';

String _normalizeBaseUrl(String baseUrl) {
  var url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

Map<String, String> _engineHeaders({
  required AuthType authType,
  String? username,
  String? password,
  String? apiKey,
}) {
  final headers = <String, String>{'content-type': 'application/json'};
  if (authType == AuthType.basic && username != null && password != null) {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    headers['authorization'] = 'Basic $credentials';
  }
  if (apiKey != null) {
    headers['x-api-key'] = apiKey;
  }
  return headers;
}

/// Checks if the engine is reachable via GET /health.
/// Returns the response duration on success, or null if unreachable.
Future<Duration?> fetchEngineHealth({
  required String baseUrl,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/health');
  final start = DateTime.now();
  try {
    final response = await http.get(uri).timeout(timeout);
    final elapsed = DateTime.now().difference(start);
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    return body == 'ok' ? elapsed : null;
  } catch (_) {
    return null;
  }
}

/// Calls GET /api/v1/status with auth headers.
/// Returns the parsed JSON map on success, or throws a [SelfTestServiceException].
Future<Map<String, dynamic>> fetchEngineStatus({
  required String baseUrl,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/v1/status');
  final headers = _engineHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );
  final http.Response response;
  try {
    response = await http.get(uri, headers: headers).timeout(timeout);
  } catch (e) {
    throw SelfTestServiceException('Connection failed: $e');
  }
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw SelfTestAuthException(response.statusCode);
  }
  if (response.statusCode != 200) {
    throw SelfTestServiceException('HTTP ${response.statusCode}');
  }
  try {
    return jsonDecode(response.body) as Map<String, dynamic>;
  } catch (e) {
    throw SelfTestServiceException('Invalid JSON response');
  }
}

/// Calls GET /api/v1/self-test with auth headers.
/// Returns the list of engine test result maps on success.
Future<List<Map<String, dynamic>>> fetchEngineSelfTests({
  required String baseUrl,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/api/v1/self-test');
  final headers = _engineHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );
  final http.Response response;
  try {
    response = await http.get(uri, headers: headers).timeout(timeout);
  } catch (e) {
    throw SelfTestServiceException('Connection failed: $e');
  }
  if (response.statusCode != 200) {
    throw SelfTestServiceException('HTTP ${response.statusCode}');
  }
  try {
    final list = jsonDecode(response.body) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  } catch (e) {
    throw SelfTestServiceException('Invalid JSON response');
  }
}

class SelfTestServiceException implements Exception {
  final String message;
  const SelfTestServiceException(this.message);
  @override
  String toString() => message;
}

class SelfTestAuthException extends SelfTestServiceException {
  final int statusCode;
  const SelfTestAuthException(this.statusCode)
    : super('Authentication failed (HTTP $statusCode)');
}
