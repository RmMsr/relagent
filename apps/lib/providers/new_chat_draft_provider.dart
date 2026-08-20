import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '/agentic/models.dart';
import '/agentic/services.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/displayed_session_provider.dart';
import '/providers/settings_provider.dart';
import '../utils/logger.dart';

/// Pre-session-creation state: composing and sending the first message of a
/// brand-new chat, before the engine has assigned a session id. Once the
/// engine responds with one, the exchange is handed off to that session's
/// own `agenticChatProvider(sessionId)` instance and this resets to empty.
class NewChatDraftState {
  final AgenticMessage? pendingUserMessage;
  final bool isLoading;
  final String? error;
  final SensitivityLevel sensitivityLevel;

  const NewChatDraftState({
    this.pendingUserMessage,
    this.isLoading = false,
    this.error,
    this.sensitivityLevel = SensitivityLevel.personal,
  });

  factory NewChatDraftState.initial() => const NewChatDraftState();

  NewChatDraftState copyWith({
    AgenticMessage? pendingUserMessage,
    bool clearPendingUserMessage = false,
    bool? isLoading,
    String? error,
    SensitivityLevel? sensitivityLevel,
  }) {
    return NewChatDraftState(
      pendingUserMessage: clearPendingUserMessage
          ? null
          : (pendingUserMessage ?? this.pendingUserMessage),
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sensitivityLevel: sensitivityLevel ?? this.sensitivityLevel,
    );
  }
}

final newChatDraftProvider =
    NotifierProvider<NewChatDraftNotifier, NewChatDraftState>(() {
      return NewChatDraftNotifier();
    });

class NewChatDraftNotifier extends Notifier<NewChatDraftState> {
  @override
  NewChatDraftState build() => NewChatDraftState.initial();

  /// Local-only: there is no session yet to apply this to on the engine, so
  /// (matching the pre-refactor behavior) it's just held until the first
  /// send, which applies it to the newly created session if it differs from
  /// the engine's default.
  void changeSensitivity(SensitivityLevel level) {
    state = state.copyWith(sensitivityLevel: level);
  }

  Future<void> sendMessage(
    String text, {
    @visibleForTesting http.Client? client,
  }) async {
    if (text.trim().isEmpty) return;
    // Creating a session is a one-shot operation with nothing yet to queue
    // against; a send while one is already in flight is ignored.
    if (state.isLoading) return;

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final userMessage = AgenticMessage.user(text);
    final chosenSensitivity = state.sensitivityLevel;

    state = state.copyWith(
      pendingUserMessage: userMessage,
      isLoading: true,
      error: null,
    );

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final chatResponse = await sendAgenticMessage(
        baseUrl: settings.engineBaseUrl,
        sessionId: null,
        content: userMessage.text,
        messageId: userMessage.messageId,
        sensitivityLevel: chosenSensitivity,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
        client: client,
      );

      final response = chatResponse.message;
      final newSessionId = response.sessionId;
      if (newSessionId == null) {
        throw EngineApiException(
          userMessage: 'Engine did not return a session ID',
          technicalDetails: 'Missing session_id on first-message response',
          url: settings.engineBaseUrl,
        );
      }

      if (chosenSensitivity != chatResponse.sensitivityLevel) {
        try {
          await setSensitivityLevel(
            baseUrl: settings.engineBaseUrl,
            sessionId: newSessionId,
            sensitivityValue: chosenSensitivity.value,
            authType: settings.engineAuthType,
            username: settings.engineUsername,
            password: password,
            apiKey: apiKey,
          );
        } catch (e) {
          Logger.debug('NewChatDraft: Failed to apply sensitivity: $e');
        }
      }

      // Seed the new session's own instance before anything watches it,
      // then hand off display to it.
      ref
          .read(agenticChatProvider(newSessionId).notifier)
          .seedFirstExchange(
            userMessage: userMessage,
            response: response,
            sensitivityLevel: chosenSensitivity,
          );

      ref.read(displayedSessionProvider.notifier).show(newSessionId);
      await settingsNotifier.setAgenticSessionId(newSessionId);

      state = NewChatDraftState.initial();
      Logger.debug('NewChatDraft: Created session $newSessionId');
    } catch (e) {
      final errorText = e is EngineApiException
          ? e.userMessage
          : e.toString();
      state = state.copyWith(isLoading: false, error: errorText);
      Logger.debug('NewChatDraft: Failed to create session: $e');
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Discards the current draft — the pending user message, any in-flight
  /// "sending" indicator, and any error — so starting a new chat always
  /// shows a genuinely blank composer, even if the previous draft was still
  /// waiting on its first response (no session/assistant reply yet, so
  /// there was nothing for switching `displayedSessionProvider` away to
  /// clear).
  void reset() {
    state = NewChatDraftState.initial();
  }
}
