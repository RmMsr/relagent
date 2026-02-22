import 'dart:convert';

import 'package:http/http.dart' as http;
import '/chat/models.dart';
import '/models/settings.dart';

enum InputClassification { request, abort, confirm, ignore, clientControl }

class ChatApiException implements Exception {
  final String userMessage;
  final String technicalDetails;
  final String? url;

  ChatApiException({
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

Future<ChatMessage> getChatResponse(
  List<ChatMessage> history, {
  required String baseUrl,
  required String model,
  required String primeMessage,
  AuthType authType = AuthType.none,
  String? basicAuthUsername,
  String? basicAuthPassword,
  String? apiKey,
}) async {
  final uri = Uri.parse('$baseUrl/chat/completions');
  var messages = <dynamic>[];
  String? lastContent;
  ChatRole? lastRole;

  final systemPrimeMessage = {'role': 'system', 'content': primeMessage};

  messages.add(systemPrimeMessage);

  for (ChatMessage m in history) {
    // Skip error messages when sending to API
    if (m.role == ChatRole.error) continue;

    // Skip consecutive duplicate messages to keep context small
    if (m.text == lastContent && m.role == lastRole) continue;

    messages.add({'role': m.role.name, 'content': m.text});
    lastContent = m.text;
    lastRole = m.role;
  }
  final body = {'messages': messages, 'model': model};

  // Build headers with authentication
  // API key (Bearer) takes precedence over Basic Auth
  final headers = <String, String>{'content-type': 'application/json'};

  if (apiKey != null) {
    headers['authorization'] = 'Bearer $apiKey';
  } else if (authType == AuthType.basic &&
      basicAuthUsername != null &&
      basicAuthPassword != null) {
    final credentials = base64Encode(
      utf8.encode('$basicAuthUsername:$basicAuthPassword'),
    );
    headers['authorization'] = 'Basic $credentials';
  }

  final http.Response response;
  try {
    response = await http.post(uri, body: jsonEncode(body), headers: headers);
  } catch (e) {
    // Check if it's a network-related error
    final isNetworkError =
        e.toString().contains('SocketException') ||
        e.toString().contains('Connection refused') ||
        e.toString().contains('Network is unreachable') ||
        e.toString().contains('Connection timeout');

    throw ChatApiException(
      userMessage: isNetworkError
          ? 'Network connection error'
          : 'Could not connect to the chat server',
      technicalDetails: e.toString(),
      url: uri.toString(),
    );
  }

  if (response.statusCode >= 300) {
    String userMessage;
    if (response.statusCode == 401 || response.statusCode == 403) {
      userMessage = 'Authentication failed';
    } else if (response.statusCode == 404) {
      userMessage = 'Chat endpoint not found (check your settings)';
    } else if (response.statusCode >= 500) {
      userMessage = 'Server error occurred';
    } else {
      userMessage = 'Request failed';
    }

    throw ChatApiException(
      userMessage: userMessage,
      technicalDetails: 'HTTP ${response.statusCode}',
      url: uri.toString(),
    );
  }

  final Map<String, dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException catch (e) {
    throw ChatApiException(
      userMessage: 'Server returned invalid response',
      technicalDetails: 'JSON parsing failed: ${e.message}',
      url: uri.toString(),
    );
  }

  final choices = responseJson['choices'];
  if (choices is! List || choices.isEmpty) {
    throw ChatApiException(
      userMessage: 'Server returned an empty response',
      technicalDetails: 'Response contains no choices',
      url: uri.toString(),
    );
  }

  final finalChoice = choices.last;

  if (finalChoice is! Map || finalChoice['message'] == null) {
    throw ChatApiException(
      userMessage: 'Server returned malformed response',
      technicalDetails: 'Choice has no message field',
      url: uri.toString(),
    );
  }

  return ChatMessage.fromJson(choices.last['message']);
}

InputClassification classifyUserInput(String input) {
  final text = input.toLowerCase().trim();
  if (text == 'cancel') {
    return InputClassification.abort;
  } else if (text == 'stop recording') {
    return InputClassification.clientControl;
  } else if (text == '?' || text == '.') {
    return InputClassification.ignore;
  }
  return InputClassification.request;
}
