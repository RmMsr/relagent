import 'dart:convert';

import 'package:http/http.dart' as http;

import '/agentic/models.dart';
import '/models/settings.dart';

String _normalizeBaseUrl(String baseUrl) {
  var url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// Extracts detailed error information from HTTP error responses.
/// For 422 validation errors, parses the HTTPValidationError schema.
String _extractErrorDetails(int statusCode, String responseBody) {
  final buffer = StringBuffer('HTTP $statusCode');

  if (responseBody.isEmpty) {
    return buffer.toString();
  }

  try {
    final json = jsonDecode(responseBody);
    if (json is Map<String, dynamic>) {
      // Handle HTTPValidationError format: {detail: [{loc, msg, type}, ...]}
      if (json.containsKey('detail')) {
        final detail = json['detail'];
        if (detail is List && detail.isNotEmpty) {
          buffer.writeln();
          for (final error in detail) {
            if (error is Map<String, dynamic>) {
              final loc = error['loc'] as List<dynamic>?;
              final msg = error['msg'] as String?;
              final type = error['type'] as String?;
              final location = loc?.join('.') ?? 'unknown';
              buffer.writeln('- $location: $msg ($type)');
            }
          }
        } else if (detail is String) {
          buffer.write(': $detail');
        }
      }
      // Handle simple error format: {error: "message"} or {message: "..."}
      else if (json.containsKey('error')) {
        buffer.write(': ${json['error']}');
      } else if (json.containsKey('message')) {
        buffer.write(': ${json['message']}');
      }
    }
  } catch (_) {
    // If JSON parsing fails, include raw body (truncated)
    final truncated = responseBody.length > 200
        ? '${responseBody.substring(0, 200)}...'
        : responseBody;
    buffer.write('\n$truncated');
  }

  return buffer.toString();
}

class EngineApiException implements Exception {
  final String userMessage;
  final String technicalDetails;
  final String? url;

  EngineApiException({
    required this.userMessage,
    required this.technicalDetails,
    this.url,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln(userMessage);
    if (url != null) {
      buffer.writeln('URL: $url');
    }
    buffer.write('Details: $technicalDetails');
    return buffer.toString();
  }
}

Map<String, String> _buildHeaders({
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

/// Fetches session info including title.
Future<SessionInfo> getSessionInfo({
  required String baseUrl,
  required String sessionId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse('$normalizedUrl/api/v1/sessions/$sessionId');

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.get(uri, headers: headers);
  } catch (e) {
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw EngineApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the engine',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  if (response.statusCode >= 300) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode == 404) {
      userMessage = 'Session not found';
    } else if (response.statusCode >= 500) {
      userMessage = 'Engine error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw EngineApiException(
      userMessage: userMessage,
      technicalDetails: _extractErrorDetails(
        response.statusCode,
        response.body,
      ),
      url: uri.toString(),
    );
  }

  final Map<String, dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }

  return SessionInfo.fromJson(responseJson);
}

/// Fetches message history for a session.
///
/// If [fromId] is provided, only messages starting from that index are returned.
/// This enables incremental fetching when new messages are appended.
///
/// Response format (MessagesResponse from OpenAPI schema):
/// ```json
/// {
///   "session_id": "uuid",
///   "messages": [
///     {"role": "user", "content": "...", "timestamp": "ISO8601"},
///     {"role": "assistant", "content": "...", "timestamp": "ISO8601"}
///   ]
/// }
/// ```
Future<List<AgenticMessage>> getMessageHistory({
  required String baseUrl,
  required String sessionId,
  int? fromId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  var uriString = '$normalizedUrl/api/v1/messages/$sessionId';
  if (fromId != null) {
    uriString += '?from_id=$fromId';
  }
  final uri = Uri.parse(uriString);

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.get(uri, headers: headers);
  } catch (e) {
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw EngineApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the engine',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  if (response.statusCode >= 300) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode == 404) {
      userMessage = 'Session not found';
    } else if (response.statusCode == 422) {
      userMessage = 'Invalid request data';
    } else if (response.statusCode >= 500) {
      userMessage = 'Engine error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw EngineApiException(
      userMessage: userMessage,
      technicalDetails: _extractErrorDetails(
        response.statusCode,
        response.body,
      ),
      url: uri.toString(),
    );
  }

  // Parse MessagesResponse: {session_id, messages: [...]}
  final Map<String, dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }

  final messagesJson = responseJson['messages'] as List<dynamic>? ?? [];

  return messagesJson
      .map((json) => AgenticMessage.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Sends a message to the engine API.
///
/// Request format (ChatRequest from OpenAPI schema):
/// ```json
/// {
///   "session_id": "uuid or null",
///   "messages": [{"role": "user", "content": "...", "timestamp": "ISO8601"}]
/// }
/// ```
///
/// Response format (ChatResponse from OpenAPI schema):
/// ```json
/// {
///   "session_id": "uuid",
///   "message": {"role": "assistant", "content": "...", "timestamp": "ISO8601"}
/// }
/// ```
Future<AgenticMessage> sendAgenticMessage({
  required String baseUrl,
  String? sessionId, // null for first message, engine creates session
  required String content,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse('$normalizedUrl/api/v1/messages');

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  // Build ChatRequest per OpenAPI schema
  final userMessage = <String, dynamic>{
    'role': 'user',
    'content': content,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
  final bodyMap = <String, dynamic>{
    'messages': [userMessage],
  };
  if (sessionId != null) {
    bodyMap['session_id'] = sessionId;
  }
  final body = jsonEncode(bodyMap);

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers, body: body);
  } catch (e) {
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw EngineApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the engine',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  if (response.statusCode >= 300) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode == 404) {
      userMessage = 'Messages endpoint not found (check engine URL)';
    } else if (response.statusCode == 422) {
      userMessage = 'Invalid message format';
    } else if (response.statusCode >= 500) {
      userMessage = 'Engine error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw EngineApiException(
      userMessage: userMessage,
      technicalDetails: _extractErrorDetails(
        response.statusCode,
        response.body,
      ),
      url: uri.toString(),
    );
  }

  final Map<String, dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }

  // Parse ChatResponse: {session_id, message: {...}}
  final sessionIdFromResponse = responseJson['session_id'] as String?;
  final messageJson = responseJson['message'] as Map<String, dynamic>?;

  if (messageJson == null) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'Missing "message" field in response',
      url: uri.toString(),
    );
  }

  // Add session_id to message for tracking
  messageJson['session_id'] = sessionIdFromResponse;

  return AgenticMessage.fromJson(messageJson);
}

/// Fetches list of recent sessions.
///
/// Response format (list of SessionInfo from OpenAPI schema):
/// ```json
/// [
///   {"session_id": "uuid", "title": "...", "created_at": "ISO8601", "updated_at": "ISO8601"},
///   ...
/// ]
/// ```
Future<List<SessionInfo>> getSessionsList({
  required String baseUrl,
  int limit = 100,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse('$normalizedUrl/api/v1/sessions?limit=$limit');

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.get(uri, headers: headers);
  } catch (e) {
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw EngineApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the engine',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  if (response.statusCode >= 300) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode == 404) {
      userMessage = 'Sessions endpoint not found (check engine URL)';
    } else if (response.statusCode >= 500) {
      userMessage = 'Engine error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw EngineApiException(
      userMessage: userMessage,
      technicalDetails: _extractErrorDetails(
        response.statusCode,
        response.body,
      ),
      url: uri.toString(),
    );
  }

  // Parse list of SessionInfo
  final List<dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as List<dynamic>;
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }

  return responseJson
      .map((json) => SessionInfo.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Deletes a session.
///
/// Returns successfully if session was deleted or didn't exist.
Future<void> deleteSessionApi({
  required String baseUrl,
  required String sessionId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse('$normalizedUrl/api/v1/sessions/$sessionId');

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.delete(uri, headers: headers);
  } catch (e) {
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw EngineApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the engine',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  // 404 is acceptable - session already deleted
  if (response.statusCode >= 300 && response.statusCode != 404) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode >= 500) {
      userMessage = 'Engine error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw EngineApiException(
      userMessage: userMessage,
      technicalDetails: _extractErrorDetails(
        response.statusCode,
        response.body,
      ),
      url: uri.toString(),
    );
  }
}
