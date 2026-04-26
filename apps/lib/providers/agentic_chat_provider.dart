import 'package:flutter/foundation.dart';
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
  final SensitivityLevel sensitivityLevel;

  const AgenticChatState({
    required this.messages,
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.error,
    this.showAssistantPending = false,
    this.sessionTitle,
    this.sensitivityLevel = SensitivityLevel.personal,
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
    SensitivityLevel? sensitivityLevel,
  }) {
    return AgenticChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      error: error,
      showAssistantPending: showAssistantPending ?? this.showAssistantPending,
      sessionTitle: clearSessionTitle
          ? null
          : (sessionTitle ?? this.sessionTitle),
      sensitivityLevel: sensitivityLevel ?? this.sensitivityLevel,
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
      final apiKey = await settingsNotifier.getEngineApiKey();

      final messages = await getMessageHistory(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        fromId: fromId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
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
        state = state.copyWith(messages: messages, isLoadingHistory: false);
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
    final sessionId =
        settings.agenticSessionId; // May be null for first message

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
      final apiKey = await settingsNotifier.getEngineApiKey();

      final chatResponse = await sendAgenticMessage(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId, // null on first message, engine will create one
        content: text,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      final response = chatResponse.message;

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
        sensitivityLevel: chatResponse.sensitivityLevel,
      );

      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      Logger.debug(
        'AgenticChat: Received response [id=${response.id}]: $preview',
      );

      // Auto-queue for TTS if in auto-playback mode (only for assistant text)
      if (settings.isAutoPlayback &&
          response.role == AgenticRole.assistant) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.localId);
      }
    } catch (e) {
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails = e is EngineApiException
          ? e.technicalDetails
          : null;

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
      final apiKey = await settingsNotifier.getEngineApiKey();

      final sessionInfo = await getSessionInfo(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      state = state.copyWith(sessionTitle: sessionInfo.title);
      Logger.debug('AgenticChat: Loaded session title: ${sessionInfo.title}');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to load session info: $e');
    }
  }

  /// Change the session sensitivity level.
  /// Optimistic update — reverts on API failure.
  /// Marks any pending approval messages as stale.
  Future<void> changeSensitivity(SensitivityLevel newLevel) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    final previousLevel = state.sensitivityLevel;

    // Optimistic update
    state = state.copyWith(sensitivityLevel: newLevel);

    // Mark pending approval messages as stale
    final updatedMessages = state.messages.map((msg) {
      if (msg.role == AgenticRole.system &&
          msg.approvals != null &&
          msg.approvals!.any((a) => a.resolution == ApprovalResolution.pending)) {
        final newApprovals = msg.approvals!.map((a) =>
          a.resolution == ApprovalResolution.pending
              ? a.copyWith(resolution: ApprovalResolution.stale)
              : a,
        ).toList();
        return msg.copyWith(isStale: true, approvals: newApprovals);
      }
      return msg;
    }).toList();

    state = state.copyWith(messages: updatedMessages);

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      await setSensitivityLevel(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        sensitivityValue: newLevel.value,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      Logger.debug('AgenticChat: Sensitivity changed to ${newLevel.label}');
    } catch (e) {
      // Revert on failure
      state = state.copyWith(sensitivityLevel: previousLevel);
      Logger.debug('AgenticChat: Failed to change sensitivity: $e');
      rethrow;
    }
  }

  /// Grant a specific approval. Calls the session or global grant API.
  Future<void> grantApproval({
    required String approvalId,
    required GrantRequest grant,
    required bool isGlobal,
  }) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      if (isGlobal) {
        await createGlobalGrant(
          baseUrl: settings.engineBaseUrl,
          grant: grant,
          authType: settings.engineAuthType,
          username: settings.engineUsername,
          password: password,
          apiKey: apiKey,
        );
      } else {
        await createSessionGrant(
          baseUrl: settings.engineBaseUrl,
          sessionId: sessionId,
          grant: grant,
          authType: settings.engineAuthType,
          username: settings.engineUsername,
          password: password,
          apiKey: apiKey,
        );
      }

      _updateApprovalResolution(
        approvalId,
        ApprovalResolution.granted,
        expiresAt: grant.expiresAt,
      );

      Logger.debug('AgenticChat: Granted approval $approvalId');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to grant approval: $e');
      rethrow;
    }
  }

  /// Skip a specific approval — tells the engine to reject it.
  Future<void> skipApproval(String approvalId) async {
    _updateApprovalResolution(approvalId, ApprovalResolution.skipped);

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      await rejectSessionApprovals(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        approvalIds: [approvalId],
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      Logger.debug('AgenticChat: Skipped approval $approvalId');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to skip approval: $e');
      rethrow;
    }
  }

  /// Continue the session — triggers an agent run with current state.
  Future<void> triggerContinuation() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    state = state.copyWith(
      isLoading: true,
      showAssistantPending: true,
    );

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final chatResponse = await continueSession(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      state = state.copyWith(
        messages: [...state.messages, chatResponse.message],
        isLoading: false,
        showAssistantPending: false,
        sensitivityLevel: chatResponse.sensitivityLevel,
      );

      Logger.debug('AgenticChat: Continuation response received');
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

      Logger.debug('AgenticChat: Continuation failed: $e');
    }
  }

  void _updateApprovalResolution(
    String approvalId,
    ApprovalResolution resolution, {
    DateTime? expiresAt,
  }) {
    final updatedMessages = state.messages.map((msg) {
      if (msg.role == AgenticRole.system && msg.approvals != null) {
        bool changed = false;
        final newApprovals = msg.approvals!.map((a) {
          if (a.id == approvalId) {
            changed = true;
            return a.copyWith(resolution: resolution, expiresAt: expiresAt);
          }
          return a;
        }).toList();
        if (changed) return msg.copyWith(approvals: newApprovals);
      }
      return msg;
    }).toList();

    state = state.copyWith(messages: updatedMessages);
    _triggerContinuationIfAllResolved();
  }

  @visibleForTesting
  void setStateForTest(AgenticChatState s) => state = s;

  /// Auto-continue once every approval in the latest actionable group is resolved.
  void _triggerContinuationIfAllResolved() {
    final messages = state.messages;

    // Find the last system message with approvals that is not stale
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.role == AgenticRole.system &&
          msg.approvals != null &&
          msg.approvals!.isNotEmpty &&
          !msg.isStale) {
        final allResolved = msg.approvals!.every(
          (a) => a.resolution != ApprovalResolution.pending,
        );
        if (allResolved) {
          triggerContinuation();
        }
        return; // Only check the most recent approval group
      }
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
