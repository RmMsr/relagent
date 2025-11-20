import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/chat/widgets.dart';
import '/providers/chat_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Schedule scroll after the current frame to ensure the UI has been built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);

    // Scroll to bottom whenever messages or pending state changes
    ref.listen<ChatState>(chatProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.showAssistantPending != next.showAssistantPending) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Simple Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              onPressed: () {
                ref.read(chatProvider.notifier).clearChat();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  ChatHistory(
                    messages: chatState.messages,
                    showAssistantPending: chatState.showAssistantPending,
                    onRetry: (text) {
                      ref.read(chatProvider.notifier).retryMessage(text);
                    },
                  ),
                ],
              ),
            ),
            ChatInput(
              onSubmitted: (text) {
                ref.read(chatProvider.notifier).sendMessage(text);
              },
            ),
          ],
        ),
      ),
    );
  }
}
