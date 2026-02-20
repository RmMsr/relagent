import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/pages/agentic_chat_page.dart';
import '/pages/chat_page.dart';
import '/providers/settings_provider.dart';

class ChatRouterPage extends ConsumerWidget {
  const ChatRouterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return settings.selectedBackend == ChatBackendType.relagentEngine
        ? const AgenticChatPage()
        : const ChatPage();
  }
}
