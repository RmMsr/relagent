import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/models.dart';
import '/agentic/services.dart';
import '/providers/settings_provider.dart';
import '/providers/tts_provider.dart';
import '../utils/logger.dart';

class AgenticChatState {
  final List<AgenticMessage> messages;
  final bool isLoading;
  final bool isLoadingHistory;
  final String? error;
  final bool showAssistantPending;
  final String? sessionTitle;

  const AgenticChatState({
    required this.messages,
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.error,
    this.showAssistantPending = false,
    this.sessionTitle,
  });

  factory AgenticChatState.initial() {
    return const AgenticChatState(messages: []);
  }

  AgenticChatState copyWith({
    List<AgenticMessage>? messages,
    bool? isLoading,
    bool? isLoadingHistory,
    String? error,
    bool? showAssistantPending,
    String? sessionTitle,
    bool clearSessionTitle = false,
  }) {
    return AgenticChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      error: error,
      showAssistantPending: showAssistantPending ?? this.showAssistantPending,
      sessionTitle: clearSessionTitle ? null : (sessionTitle ?? this.sessionTitle),
    );
  }
}

final agenticChatProvider =
    NotifierProvider<AgenticChatNotifier, AgenticChatState>(() {
  return AgenticChatNotifier();
});

class AgenticChatNotifier extends Notifier<AgenticChatState> {
  @override
  AgenticChatState build() {
    return AgenticChatState.initial();
  }

  Future<void> loadHistory({int? fromId}) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    // No session yet - nothing to load
    if (sessionId == null) {
      Logger.debug('AgenticChat: No session ID, skipping history load');
      return;
    }

    state = state.copyWith(isLoadingHistory: true, error: null);

    try {
      final password = await settingsNotifier.getEnginePassword();

      final messages = await getMessageHistory(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        fromId: fromId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
      );

      if (fromId != null && fromId > 0) {
        // Incremental load - append only messages not already present locally
        final existingIds = {
          for (final m in state.messages)
            if (m.id != null) m.id,
        };
        final newMessages =
            messages.where((m) => m.id == null || !existingIds.contains(m.id)).toList();
        state = state.copyWith(
          messages: [...state.messages, ...newMessages],
          isLoadingHistory: false,
        );
        Logger.debug(
          'AgenticChat: Appended ${newMessages.length} messages from index $fromId'
          ' (${messages.length - newMessages.length} duplicates skipped)',
        );
      } else {
        // Full load - replace all messages
        state = state.copyWith(
          messages: messages,
          isLoadingHistory: false,
        );
        Logger.debug(
          'AgenticChat: Loaded ${messages.length} messages for session $sessionId',
        );
      }
    } catch (e) {
      Logger.debug('AgenticChat: Failed to load history: $e');
      state = state.copyWith(
        isLoadingHistory: false,
        error: e is EngineApiException ? e.userMessage : e.toString(),
      );
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId; // May be null for first message

    // Add user message locally
    final userMessage = AgenticMessage.user(text);
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
      showAssistantPending: true,
    );

    try {
      final password = await settingsNotifier.getEnginePassword();

      final response = await sendAgenticMessage(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId, // null on first message, engine will create one
        content: text,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
      );

      // Store session_id from response if we got a new one
      if (response.sessionId != null && response.sessionId != sessionId) {
        await settingsNotifier.setAgenticSessionId(response.sessionId!);
        Logger.debug(
          'AgenticChat: Stored new session ID: ${response.sessionId}',
        );
      }

      state = state.copyWith(
        messages: [...state.messages, response],
        isLoading: false,
        showAssistantPending: false,
      );

      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      Logger.debug(
        'AgenticChat: Received response [id=${response.id}]: $preview',
      );

      // Auto-queue for TTS if in auto-playback mode
      if (settings.isAutoPlayback) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.localId);
      }
    } catch (e) {
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails =
          e is EngineApiException ? e.technicalDetails : null;

      final errorMessage = AgenticMessage.error(
        errorText,
        technicalDetails: technicalDetails,
      );

      state = state.copyWith(
        messages: [...state.messages, errorMessage],
        isLoading: false,
        showAssistantPending: false,
      );

      Logger.debug('AgenticChat: Error sending message: $e');
    }
  }

  Future<void> clearChat() async {
    // Clear session ID so next message starts a new session
    await ref.read(settingsProvider.notifier).clearAgenticSessionId();

    // Clear messages and session title
    state = AgenticChatState.initial();

    // Clear TTS queue
    ref.read(ttsProvider.notifier).onChatCleared();

    Logger.debug('AgenticChat: Chat cleared and session reset');
  }

  void clearMessages() {
    state = AgenticChatState.initial();
    ref.read(ttsProvider.notifier).onChatCleared();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> loadSessionInfo() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) {
      return;
    }

    try {
      final password = await settingsNotifier.getEnginePassword();

      final sessionInfo = await getSessionInfo(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
      );

      state = state.copyWith(sessionTitle: sessionInfo.title);
      Logger.debug('AgenticChat: Loaded session title: ${sessionInfo.title}');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to load session info: $e');
    }
  }

  /// Retry sending all user messages that haven't been acknowledged by the engine.
  /// This finds user messages after the last assistant response and resends them.
  Future<void> retryFailedMessages() async {
    // Find the index of the last assistant message (which means engine received prior messages)
    int lastAssistantIndex = -1;
    for (int i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].role == AgenticRole.assistant) {
        lastAssistantIndex = i;
        break;
      }
    }

    // Collect user messages after the last assistant response
    final unsentUserMessages = <String>[];
    for (int i = lastAssistantIndex + 1; i < state.messages.length; i++) {
      final msg = state.messages[i];
      if (msg.role == AgenticRole.user) {
        unsentUserMessages.add(msg.text);
      }
    }

    if (unsentUserMessages.isEmpty) {
      Logger.debug('AgenticChat: No unsent messages to retry');
      return;
    }

    Logger.debug(
      'AgenticChat: Retrying ${unsentUserMessages.length} unsent message(s)',
    );

    // Remove all messages after last assistant (user messages and errors)
    final messagesUpToLastAssistant = lastAssistantIndex >= 0
        ? state.messages.sublist(0, lastAssistantIndex + 1)
        : <AgenticMessage>[];

    state = state.copyWith(messages: messagesUpToLastAssistant);

    // Resend each user message
    for (final text in unsentUserMessages) {
      await sendMessage(text);

      // If we got an error, stop retrying
      if (state.messages.isNotEmpty &&
          state.messages.last.role == AgenticRole.error) {
        break;
      }
    }
  }
}
