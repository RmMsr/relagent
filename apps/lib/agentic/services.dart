import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Raised when the engine returns 409 because the session has an unsettled
/// in-flight cycle. Reasons include a second client/tab on the same session
/// or a prior /continue that errored mid-cycle and left the trailing
/// SystemAction unresolved. The user-facing message is intentionally
/// neutral — the right user action is the same in either case.
class SessionInFlightException extends EngineApiException {
  final String sessionId;
  final String? trailingMessageId;

  SessionInFlightException({
    required this.sessionId,
    required this.trailingMessageId,
    required super.technicalDetails,
    super.url,
  }) : super(
          userMessage:
              'Interaction is not complete, please retry to continue.',
        );
}

/// Raised when /stop is called but no cycle is in flight.
class NoInFlightCycleException extends EngineApiException {
  final String sessionId;

  NoInFlightCycleException({
    required this.sessionId,
    required super.technicalDetails,
    super.url,
  }) : super(userMessage: 'No active request to stop');
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
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri, notFoundMessage: 'Session not found');
  }

  return SessionInfo.fromJson(_parseJsonObject(response.body, uri));
}

/// Response from message history containing messages + sensitivity.
class MessageHistoryResponseData {
  final List<AgenticMessage> messages;
  final SensitivityLevel? sensitivityLevel;

  MessageHistoryResponseData({required this.messages, this.sensitivityLevel});
}

/// Fetches message history for a session.
///
/// If [afterMessageId] is provided, only messages after that UUID cursor are
/// returned. This enables incremental fetching when new messages are appended.
@visibleForTesting
Future<MessageHistoryResponseData> getMessageHistory({
  required String baseUrl,
  required String sessionId,
  String? afterMessageId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
  @visibleForTesting http.Client? client,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uriString = afterMessageId != null
      ? '$normalizedUrl/api/v1/messages/$sessionId?after=$afterMessageId'
      : '$normalizedUrl/api/v1/messages/$sessionId';
  final uri = Uri.parse(uriString);
  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    final effectiveClient = client ?? http.Client();
    response = await effectiveClient.get(uri, headers: headers);
    if (client == null) effectiveClient.close();
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri, notFoundMessage: 'Session not found');
  }

  final responseJson = _parseJsonObject(response.body, uri);
  final messagesJson = responseJson['messages'] as List<dynamic>? ?? [];

  SensitivityLevel? sensitivityLevel;
  final sensitivityRaw = responseJson['sensitivity_level'];
  if (sensitivityRaw is int) {
    sensitivityLevel = SensitivityLevel.fromValue(sensitivityRaw);
  } else if (sensitivityRaw is String) {
    sensitivityLevel = SensitivityLevel.fromName(sensitivityRaw);
  }

  return MessageHistoryResponseData(
    messages: messagesJson
        .map((json) => AgenticMessage.fromJson(json as Map<String, dynamic>))
        .toList(),
    sensitivityLevel: sensitivityLevel,
  );
}

/// Sends a message to the engine API.
/// When [sessionId] is null (first message in a new session), an optional
/// [sensitivityLevel] can be included so the engine applies it before the
/// first cycle runs, avoiding a post-hoc [setSensitivityLevel] correction.
Future<ChatResponseData> sendAgenticMessage({
  required String baseUrl,
  String? sessionId, // null for first message, engine creates session
  required String content,
  String? messageId, // stable UUID for idempotent POST on retry
  SensitivityLevel? sensitivityLevel,
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

  final bodyMap = <String, dynamic>{
    'messages': [
      {
        'role': 'user',
        'content': content,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        if (messageId != null) 'message_id': messageId,
      },
    ],
    if (sessionId != null) 'session_id': sessionId,
    if (sessionId == null && sensitivityLevel != null)
      'sensitivity_level': sensitivityLevel.value,
  };

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers, body: jsonEncode(bodyMap));
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(
      response,
      uri,
      notFoundMessage: 'Messages endpoint not found (check engine URL)',
      invalidDataMessage: 'Invalid message format',
    );
  }

  return _parseChatResponse(_parseJsonObject(response.body, uri), uri);
}

/// Fetches list of recent sessions.
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
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(
      response,
      uri,
      notFoundMessage: 'Sessions endpoint not found (check engine URL)',
    );
  }

  try {
    final json = jsonDecode(response.body) as List<dynamic>;
    return json
        .map((e) => SessionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }
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
    throw _networkException(e, uri);
  }

  // 404 is acceptable — session was already deleted
  if (response.statusCode >= 300 && response.statusCode != 404) {
    throw _httpException(response, uri);
  }
}

/// Sets the sensitivity level for a session.
Future<void> setSensitivityLevel({
  required String baseUrl,
  required String sessionId,
  required int sensitivityValue,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse(
    '$normalizedUrl/api/v1/sessions/$sessionId/sensitivity',
  );

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final body = jsonEncode({'sensitivity_level': sensitivityValue});

  final http.Response response;
  try {
    response = await http.put(uri, headers: headers, body: body);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }
}

/// Creates a global grant.
Future<void> createGlobalGrant({
  required String baseUrl,
  required GrantRequest grant,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse('$normalizedUrl/api/v1/grants');

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final body = jsonEncode(grant.toJson());

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers, body: body);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }
}

/// Records a per-approval grant decision on the in-flight SystemAction.
/// If [grant] is provided, also registers it as a session-scoped grant so
/// future approvals matching the same permission key auto-satisfy.
Future<void> grantSessionApproval({
  required String baseUrl,
  required String sessionId,
  required String approvalId,
  GrantRequest? grant,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse(
    '$normalizedUrl/api/v1/sessions/$sessionId/approvals/$approvalId/grant',
  );

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final body = jsonEncode({if (grant != null) 'grant': grant.toJson()});

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers, body: body);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }
}

/// Records a per-approval decline decision on the in-flight SystemAction.
Future<void> declineSessionApproval({
  required String baseUrl,
  required String sessionId,
  required String approvalId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse(
    '$normalizedUrl/api/v1/sessions/$sessionId/approvals/$approvalId/decline',
  );

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }
}

/// Settles the in-flight cycle by declining undecided approvals and marking
/// all in-flight messages final. Returns the settled message list.
Future<List<AgenticMessage>> stopSession({
  required String baseUrl,
  required String sessionId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse(
    '$normalizedUrl/api/v1/sessions/$sessionId/stop',
  );

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }

  final responseJson = _parseJsonObject(response.body, uri);
  final messagesJson = responseJson['messages'] as List<dynamic>? ?? [];
  return messagesJson
      .map((json) => AgenticMessage.fromJson(json as Map<String, dynamic>))
      .toList();
}

/// Response from continue or sendMessage containing message + sensitivity.
class ChatResponseData {
  final AgenticMessage message;
  final SensitivityLevel? sensitivityLevel;

  ChatResponseData({required this.message, this.sensitivityLevel});
}

/// Continues a session — triggers an agent run with current state.
Future<ChatResponseData> continueSession({
  required String baseUrl,
  required String sessionId,
  AuthType authType = AuthType.none,
  String? username,
  String? password,
  String? apiKey,
}) async {
  final normalizedUrl = _normalizeBaseUrl(baseUrl);
  final uri = Uri.parse(
    '$normalizedUrl/api/v1/sessions/$sessionId/continue',
  );

  final headers = _buildHeaders(
    authType: authType,
    username: username,
    password: password,
    apiKey: apiKey,
  );

  final http.Response response;
  try {
    response = await http.post(uri, headers: headers);
  } catch (e) {
    throw _networkException(e, uri);
  }

  if (response.statusCode >= 300) {
    throw _httpException(response, uri);
  }

  final responseJson = _parseJsonObject(response.body, uri);
  return _parseChatResponse(responseJson, uri);
}

// -- Helpers for new endpoints --

EngineApiException _networkException(Object e, Uri uri) {
  final isNetworkError =
      e.toString().contains('SocketException') ||
      e.toString().contains('Connection refused') ||
      e.toString().contains('Network is unreachable') ||
      e.toString().contains('Connection timeout');

  return EngineApiException(
    userMessage: isNetworkError
        ? 'Network connection error'
        : 'Could not connect to the engine',
    technicalDetails: e.toString(),
    url: uri.toString(),
  );
}

EngineApiException _httpException(
  http.Response response,
  Uri uri, {
  String? notFoundMessage,
  String? invalidDataMessage,
}) {
  if (response.statusCode == 409) {
    final conflict = tryParseConflict(response.body, uri);
    if (conflict != null) return conflict;
  }

  String userMessage;
  if (response.statusCode == 401 || response.statusCode == 403) {
    userMessage = 'Authentication failed';
  } else if (response.statusCode == 404) {
    userMessage = notFoundMessage ?? 'Endpoint not found (check engine URL and version)';
  } else if (response.statusCode == 422) {
    userMessage = invalidDataMessage ?? 'Invalid request data';
  } else if (response.statusCode >= 500) {
    userMessage = 'Engine error occurred';
  } else {
    userMessage = 'Request failed';
  }

  return EngineApiException(
    userMessage: userMessage,
    technicalDetails: _extractErrorDetails(response.statusCode, response.body),
    url: uri.toString(),
  );
}

@visibleForTesting
EngineApiException? tryParseConflict(String body, Uri uri) {
  try {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic>) return null;
    final detail = json['detail'];
    if (detail is! Map<String, dynamic>) return null;
    final error = detail['error'];
    final sessionId = detail['session_id'] as String? ?? '';
    if (error == 'session_in_flight') {
      return SessionInFlightException(
        sessionId: sessionId,
        trailingMessageId: detail['trailing_message_id'] as String?,
        technicalDetails: body,
        url: uri.toString(),
      );
    }
    if (error == 'no_in_flight_cycle') {
      return NoInFlightCycleException(
        sessionId: sessionId,
        technicalDetails: body,
        url: uri.toString(),
      );
    }
  } catch (_) {}
  return null;
}

Map<String, dynamic> _parseJsonObject(String body, Uri uri) {
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }
}

ChatResponseData _parseChatResponse(
  Map<String, dynamic> responseJson,
  Uri uri,
) {
  final sessionIdFromResponse = responseJson['session_id'] as String?;
  final messageJson = responseJson['message'] as Map<String, dynamic>?;

  if (messageJson == null) {
    throw EngineApiException(
      userMessage: 'Engine returned invalid response',
      technicalDetails: 'Missing "message" field in response',
      url: uri.toString(),
    );
  }

  messageJson['session_id'] = sessionIdFromResponse;

  SensitivityLevel? sensitivityLevel;
  final sensitivityRaw = responseJson['sensitivity_level'];
  if (sensitivityRaw is int) {
    sensitivityLevel = SensitivityLevel.fromValue(sensitivityRaw);
  } else if (sensitivityRaw is String) {
    sensitivityLevel = SensitivityLevel.fromName(sensitivityRaw);
  }

  return ChatResponseData(
    message: AgenticMessage.fromJson(messageJson),
    sensitivityLevel: sensitivityLevel,
  );
}
