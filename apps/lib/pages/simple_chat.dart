import 'package:flutter/material.dart';
import 'package:relagent/chat/models.dart';
import 'package:relagent/chat/services.dart';
import 'package:relagent/chat/widgets.dart';

class SimpleChatPage extends StatefulWidget {
  const SimpleChatPage({super.key, required this.title});
  final String title;

  @override
  State<SimpleChatPage> createState() => _SimpleChatState();
}

class _SimpleChatState extends State<SimpleChatPage> {
  var messages = <ChatMessage>[];

  void _sendMessage(String query) async {
    var userMessage = ChatMessage(query, role: ChatRole.user);
    setState(() {
      messages.add(userMessage);
    });
    var response = await getChatResponse(messages);
    setState(() {
      messages.add(response);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: ChatHistory(messages: messages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: ChatInput(onSubmitted: _sendMessage),
      ),
    );
  }
}
