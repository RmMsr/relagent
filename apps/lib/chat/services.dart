import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:relagent/chat/models.dart';

enum InputClassification { request, abort, confirm, ignore, clientControl }

Future<ChatMessage> getChatResponse(
  List<ChatMessage> history, {
  required String baseUrl,
  required String model,
}) async {
  final uri = Uri.parse('$baseUrl/chat/completions');
  var messages = [];
  for (ChatMessage m in history) {
    messages.add({'role': m.role.name, 'content': m.text});
  }
  final body = {'messages': messages, 'model': model};
  final response = await http.post(
    uri,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json'},
  );

  if (response.statusCode >= 300) {
    throw Exception('Failed to send message: ${response.statusCode}');
  }

  final Map<String, dynamic> responseJson;
  try {
    responseJson = jsonDecode(response.body) as Map<String, dynamic>;
  } on FormatException {
    throw Exception('Failed to parse response');
  }

  final choices = responseJson['choices'];
  if (choices! is Map || choices.isEmpty) {
    throw Exception('Response contains no choices');
  }

  final finalChoice = choices.last;

  if (finalChoice is! Map || finalChoice['message'] == null) {
    throw Exception('Choice has no message');
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
