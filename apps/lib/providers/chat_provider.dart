import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/chat/models.dart';
import '/chat/services.dart';
import '/providers/settings_provider.dart';
import '/providers/tts_provider.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final bool showAssistantPending;

  const ChatState({
    required this.messages,
    this.isLoading = false,
    this.error,
    this.showAssistantPending = false,
  });

  factory ChatState.initial() {
    return const ChatState(messages: []);
  }

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    bool? showAssistantPending,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      showAssistantPending: showAssistantPending ?? this.showAssistantPending,
    );
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(ref);
});

class ChatNotifier extends StateNotifier<ChatState> {
  final Ref ref;

  ChatNotifier(this.ref) : super(ChatState.initial());

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    // Add user message
    final userMessage = ChatMessage(text, role: ChatRole.user);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
      showAssistantPending: true,
    );

    try {
      // Get settings for API call
      final settings = ref.read(settingsProvider);

      // Get response from chat service
      final response = await getChatResponse(
        state.messages,
        baseUrl: settings.simpleChatBaseUrl,
        model: settings.simpleChatModel,
        primeMessage: settings.primeMessage,
      );

      // Add assistant response
      state = state.copyWith(
        messages: [...state.messages, response],
        isLoading: false,
        showAssistantPending: false,
      );

      // Debug: Show message ID and preview
      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      debugPrint('ChatProvider: Received message [${response.id}]: $preview');

      // Auto-queue the assistant response for TTS playback if in auto-playback mode
      if (settings.isAutoPlayback) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.id);
      }
    } catch (e) {
      // Handle error - add error message to chat history
      final errorMessage = ChatMessage.error(e.toString());
      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
        showAssistantPending: false,
      );
    }
  }

  void clearChat() {
    state = ChatState.initial();
    // Trigger TTS cleanup when chat is cleared
    ref.read(ttsProvider.notifier).onChatCleared();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  // Retry sending a specific user message
  Future<void> retryMessage(String text) async {
    await sendMessage(text);
  }
}
