import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/chat/models.dart';
import '/chat/services.dart';
import '/providers/connectivity_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/tts_provider.dart';
import '../utils/logger.dart';

// Retry configuration constants
const Duration _initialRetryDelay = Duration(seconds: 2);
const Duration _maxRetryDuration = Duration(minutes: 4);
const int _maxRetryAttempts = 10;

extension on Object {
  (String, String?) _extractErrorDetails() {
    if (this is ChatApiException) {
      return (toString(), (this as ChatApiException).technicalDetails);
    }
    return (toString(), null);
  }
}

enum RetryStatus { idle, retrying, failed }

class RetryState {
  final RetryStatus status;
  final String? messageId;
  final String? text;
  final DateTime? firstAttempt;
  final DateTime? nextRetry;
  final int retryCount;
  final String? lastError;
  final String? lastErrorTechnical;

  const RetryState({
    this.status = RetryStatus.idle,
    this.messageId,
    this.text,
    this.firstAttempt,
    this.nextRetry,
    this.retryCount = 0,
    this.lastError,
    this.lastErrorTechnical,
  });

  RetryState copyWith({
    RetryStatus? status,
    String? messageId,
    String? text,
    DateTime? firstAttempt,
    DateTime? nextRetry,
    int? retryCount,
    String? lastError,
    String? lastErrorTechnical,
  }) {
    return RetryState(
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
      text: text ?? this.text,
      firstAttempt: firstAttempt ?? this.firstAttempt,
      nextRetry: nextRetry ?? this.nextRetry,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      lastErrorTechnical: lastErrorTechnical ?? this.lastErrorTechnical,
    );
  }

  bool get shouldRetry =>
      status == RetryStatus.retrying &&
      firstAttempt != null &&
      DateTime.now().difference(firstAttempt!) < _maxRetryDuration &&
      retryCount < _maxRetryAttempts;

  bool get isRetrying => status == RetryStatus.retrying;
  bool get hasFailed => status == RetryStatus.failed;
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final bool showAssistantPending;
  final RetryState retryState;

  const ChatState({
    required this.messages,
    this.isLoading = false,
    this.error,
    this.showAssistantPending = false,
    this.retryState = const RetryState(),
  });

  factory ChatState.initial() {
    return const ChatState(messages: []);
  }

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    bool? showAssistantPending,
    RetryState? retryState,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      showAssistantPending: showAssistantPending ?? this.showAssistantPending,
      retryState: retryState ?? this.retryState,
    );
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    // Listen to connectivity changes to retry pending messages
    ref.listen<ConnectivityState>(connectivityProvider, (previous, next) {
      if ((previous == null || !previous.isOnline) &&
          next.isOnline &&
          state.retryState.isRetrying) {
        _retryPendingMessage();
      }
    });

    return ChatState.initial();
  }

  void _markRetryFailed(String reason) {
    // Add error message to chat with technical details
    final technicalDetails = state.retryState.firstAttempt != null
        ? 'Error: ${state.retryState.lastError ?? reason}\n'
              'Retry attempts: ${state.retryState.retryCount}\n'
              'First attempt: ${state.retryState.firstAttempt}\n'
              'Message ID: ${state.retryState.messageId}'
              '${state.retryState.lastErrorTechnical != null ? '\n\nTechnical Details:\n${state.retryState.lastErrorTechnical}' : ''}'
        : null;
    final errorMessage = ChatMessage.error(
      reason,
      technicalDetails: technicalDetails,
    );
    state = state.copyWith(
      retryState: const RetryState(), // Reset to idle
      messages: [...state.messages, errorMessage],
      showAssistantPending: false, // Hide pending indicator on final failure
    );

    Logger.debug('ChatProvider: Retry failed: $reason');
  }

  void _retryPendingMessage() {
    Logger.debug(
      'ChatProvider: Connectivity restored, checking if retry should be scheduled',
    );

    // Check if the message has already timed out
    if (state.retryState.firstAttempt != null &&
        DateTime.now().difference(state.retryState.firstAttempt!) >=
            _maxRetryDuration) {
      Logger.debug(
        'ChatProvider: Message ${state.retryState.messageId} has timed out, failing permanently',
      );
      _markRetryFailed(
        'Message delivery timed out after ${_maxRetryDuration.inMinutes} minutes',
      );
      return;
    }

    // Only schedule a retry if we're in retrying state and no retry is currently scheduled
    if (state.retryState.isRetrying && state.retryState.nextRetry == null) {
      Logger.debug(
        'ChatProvider: Scheduling postponed retry for message ${state.retryState.messageId}',
      );
      _scheduleRetry(state.retryState);
    } else if (state.retryState.nextRetry != null) {
      Logger.debug(
        'ChatProvider: Retry already scheduled for ${DateTime.now().difference(state.retryState.nextRetry!).inMilliseconds}ms from now',
      );
    }
  }

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
      Logger.debug('ChatProvider: Received message [${response.id}]: $preview');

      // Auto-queue the assistant response for TTS playback if in auto-playback mode
      if (settings.isAutoPlayback) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.id);
      }
    } catch (e) {
      await _handleSendError(userMessage.id, text, e);
    }
  }

  Future<void> _handleSendError(
    String messageId,
    String text,
    Object error,
  ) async {
    // Check if it's a network-related error that should be retried
    final isRetryableError =
        error is ChatApiException &&
        error.userMessage.contains('Network connection error');

    if (isRetryableError) {
      // Network error - start retry process (only for initial failure)
      _startRetry(messageId, text);
      Logger.debug(
        'ChatProvider: Started retry process for message $messageId',
      );
    } else {
      // Non-retryable error - show error immediately
      _showErrorMessage(error);
    }
  }

  void _startRetry(String messageId, String text) {
    final firstAttempt = DateTime.now();
    final retryState = RetryState(
      status: RetryStatus.retrying,
      messageId: messageId,
      text: text,
      firstAttempt: firstAttempt,
      retryCount: 0,
    );

    state = state.copyWith(
      retryState: retryState,
      isLoading: false,
      showAssistantPending: true,
    );

    // Schedule overall timeout
    Future.delayed(_maxRetryDuration, () {
      if (state.retryState.messageId == messageId &&
          state.retryState.isRetrying) {
        Logger.debug(
          'ChatProvider: Message $messageId timed out after ${_maxRetryDuration.inMinutes} minutes',
        );
        _markRetryFailed(
          'Message delivery timed out after ${_maxRetryDuration.inMinutes} minutes',
        );
      }
    });

    _scheduleRetry(retryState);
  }

  void _updateRetryError(String errorMessage, String? technicalDetails) {
    // Update the retry state with the latest error information
    // but keep the pending indicator visible
    final updatedRetry = state.retryState.copyWith(
      lastError: errorMessage,
      lastErrorTechnical: technicalDetails,
    );

    state = state.copyWith(retryState: updatedRetry);
    Logger.debug('ChatProvider: Retry error updated: $errorMessage');
  }

  void _showErrorMessage(Object error) {
    final (errorText, technicalDetails) = error._extractErrorDetails();
    final errorMessage = ChatMessage.error(
      errorText,
      technicalDetails: technicalDetails,
    );
    state = state.copyWith(
      messages: [...state.messages, errorMessage],
      isLoading: false,
      showAssistantPending: false,
    );
    Logger.debug('ChatProvider: Error: $errorText');
  }

  void _scheduleRetry(RetryState retryState) {
    if (!retryState.shouldRetry) {
      // Mark as permanently failed
      _markRetryFailed('Message failed after multiple retry attempts');
      return;
    }

    final connectivityState = ref.read(connectivityProvider);

    // If we have connectivity, schedule immediate retry with backoff
    if (connectivityState.isOnline) {
      final backoffMs =
          _initialRetryDelay.inMilliseconds *
          (1 << retryState.retryCount); // 2s, 4s, 8s, 16s...
      final nextRetry = DateTime.now().add(Duration(milliseconds: backoffMs));

      final updatedRetry = retryState.copyWith(
        nextRetry: nextRetry,
        retryCount: retryState.retryCount + 1,
      );

      state = state.copyWith(
        retryState: updatedRetry,
        showAssistantPending:
            true, // Show pending indicator while retry is scheduled
      );

      // Schedule the actual retry
      Future.delayed(Duration(milliseconds: backoffMs), () {
        if (state.retryState.messageId == retryState.messageId &&
            state.retryState.isRetrying) {
          _attemptSendMessage(retryState.messageId!, retryState.text!);
        }
      });

      Logger.debug(
        'ChatProvider: Scheduled retry in ${backoffMs}ms for message ${retryState.messageId}',
      );
    } else {
      // No connectivity - don't schedule retry yet, keep current state
      // The connectivity listener will schedule it when connectivity is restored
      Logger.debug(
        'ChatProvider: No connectivity, will retry when connection is restored for message ${retryState.messageId}',
      );
    }
  }

  Future<void> _handleRetryError(
    String messageId,
    String text,
    Object error,
  ) async {
    // Update the retry state with error information but keep retrying
    final (errorText, technicalDetails) = error._extractErrorDetails();
    _updateRetryError(errorText, technicalDetails);

    // Increment retry count and check if we should continue retrying
    final currentRetry = state.retryState;
    final newRetryCount = currentRetry.retryCount + 1;

    if (newRetryCount >= _maxRetryAttempts) {
      // Max retries reached - fail permanently
      _markRetryFailed(
        'Message failed after maximum retry attempts ($_maxRetryAttempts)',
      );
      return;
    }

    // Schedule next retry attempt
    final updatedRetry = currentRetry.copyWith(
      retryCount: newRetryCount,
      nextRetry: null, // Clear any existing scheduled retry
    );

    state = state.copyWith(retryState: updatedRetry);
    _scheduleRetry(updatedRetry);
  }

  Future<void> _attemptSendMessage(String messageId, String text) async {
    // Show pending indicator while attempting to send
    state = state.copyWith(showAssistantPending: true);

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

      // Success - clear retry state and pending indicator
      state = state.copyWith(
        messages: [...state.messages, response],
        retryState: const RetryState(), // Reset to idle
        showAssistantPending: false,
      );

      // Debug: Show message ID and preview
      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      Logger.debug(
        'ChatProvider: Retry successful, received message [${response.id}]: $preview',
      );

      // Auto-queue the assistant response for TTS playback if in auto-playback mode
      if (settings.isAutoPlayback) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.id);
      }
    } catch (e) {
      // Hide pending indicator while handling the error
      state = state.copyWith(showAssistantPending: false);

      // This is a retry attempt that failed - schedule next retry or fail permanently
      await _handleRetryError(messageId, text, e);
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
}
