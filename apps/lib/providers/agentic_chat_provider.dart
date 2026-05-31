import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '/agentic/models.dart';
import '/agentic/services.dart';
import '/providers/sessions_provider.dart';
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
  /// At most one user message awaiting dispatch while a cycle is in flight.
  final String? queuedMessage;

  const AgenticChatState({
    required this.messages,
    this.isLoading = false,
    this.isLoadingHistory = false,
    this.error,
    this.showAssistantPending = false,
    this.sessionTitle,
    this.sensitivityLevel = SensitivityLevel.personal,
    this.queuedMessage,
  });

  factory AgenticChatState.initial() {
    return const AgenticChatState(messages: []);
  }

  /// True while the engine is processing a cycle: either an HTTP call is in
  /// flight or the trailing persisted message is non-final. Errors are
  /// local-only UI events and are skipped when looking at the tail.
  bool get isAwaiting {
    if (isLoading) return true;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == AgenticRole.error) continue;
      return !messages[i].isFinal;
    }
    return false;
  }

  /// Input is disabled while a queued message exists; the user must edit or
  /// let the cycle settle first.
  bool get inputEnabled => queuedMessage == null;

  AgenticChatState copyWith({
    List<AgenticMessage>? messages,
    bool? isLoading,
    bool? isLoadingHistory,
    String? error,
    bool? showAssistantPending,
    String? sessionTitle,
    bool clearSessionTitle = false,
    SensitivityLevel? sensitivityLevel,
    String? queuedMessage,
    bool clearQueuedMessage = false,
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
      queuedMessage: clearQueuedMessage
          ? null
          : (queuedMessage ?? this.queuedMessage),
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
    // The queued message is per-session by intent (it's about to be sent on
    // *this* session). Drop it whenever the active session id changes so a
    // queue created in session A can never auto-dispatch to session B.
    ref.listen(
      settingsProvider.select((s) => s.agenticSessionId),
      (previous, next) {
        if (previous != next && state.queuedMessage != null) {
          Logger.debug(
            'AgenticChat: Active session changed — dropping queued message',
          );
          state = state.copyWith(clearQueuedMessage: true);
        }
      },
    );
    // Clear chat whenever the engine URL changes so stale messages from the
    // previous server are not shown. This avoids the circular dependency that
    // arises when SettingsNotifier tries to reach into agenticChatProvider.
    ref.listen(
      settingsProvider.select((s) => s.engineBaseUrl),
      (previous, next) {
        if (previous != null && previous != next) {
          clearMessages();
        }
      },
    );
    return AgenticChatState.initial();
  }

  @visibleForTesting
  Future<void> loadHistory({
    String? afterMessageId,
    @visibleForTesting http.Client? client,
  }) async {
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

      final historyData = await getMessageHistory(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        afterMessageId: afterMessageId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
        client: client,
      );

      final sensitivityLevel = historyData.sensitivityLevel;
      final messages = historyData.messages;

      if (afterMessageId != null) {
        _ingestMessages(messages);
        state = state.copyWith(
          isLoadingHistory: false,
          sensitivityLevel: sensitivityLevel,
        );
        // If the fetch settled the in-flight cycle, clear the pending indicator
        // before auto-dispatching so the UI doesn't flash real-message + bubble.
        _clearPendingIfSettled();
        Logger.debug(
          'AgenticChat: Refreshed after $afterMessageId — ${messages.length} fetched',
        );
        // Incremental refresh is SSE-driven and may settle the cycle.
        _dispatchQueuedIfAny();
      } else {
        // Full load replaces state entirely — do not auto-dispatch.
        state = state.copyWith(
          messages: messages,
          isLoadingHistory: false,
          sensitivityLevel: sensitivityLevel,
        );
        // Same pending-clear for the full-load path (e.g. SSE fires before
        // POST response for a new session, cursor is null → full load arrives
        // with settled messages while showAssistantPending is still true).
        _clearPendingIfSettled();
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

    // Strict-ordering: if a cycle is in flight, hold the message in the
    // single queue slot. Auto-dispatched once the in-flight cycle settles.
    if (state.isAwaiting) {
      state = state.copyWith(queuedMessage: text);
      Logger.debug('AgenticChat: Cycle in flight — queued message');
      return;
    }

    await _dispatchUserMessage(AgenticMessage.user(text));
  }

  Future<void> _dispatchUserMessage(AgenticMessage userMessage) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    // Optimistic add (in-flight: isFinal defaults to false)
    _ingestMessages([userMessage]);
    state = state.copyWith(isLoading: true, error: null, showAssistantPending: true);

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final chatResponse = await sendAgenticMessage(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        content: userMessage.text,
        messageId: userMessage.messageId,
        sensitivityLevel: state.sensitivityLevel,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      final response = chatResponse.message;
      final bool isNewSession =
          response.sessionId != null && response.sessionId != sessionId;

      if (isNewSession) {
        await settingsNotifier.setAgenticSessionId(response.sessionId!);
        Logger.debug('AgenticChat: Stored new session ID: ${response.sessionId}');

        // Apply locally-chosen sensitivity to the newly created session
        if (state.sensitivityLevel != chatResponse.sensitivityLevel) {
          try {
            await setSensitivityLevel(
              baseUrl: settings.engineBaseUrl,
              sessionId: response.sessionId!,
              sensitivityValue: state.sensitivityLevel.value,
              authType: settings.engineAuthType,
              username: settings.engineUsername,
              password: password,
              apiKey: apiKey,
            );
            Logger.debug(
              'AgenticChat: Applied sensitivity ${state.sensitivityLevel.label} '
              'to new session',
            );
          } catch (e) {
            Logger.debug('AgenticChat: Failed to apply sensitivity: $e');
          }
        }
      }

      if (response.isFinal) {
        final settled = state.messages
            .where((m) => !m.isFinal)
            .map((m) => m.copyWith(isFinal: true))
            .toList();
        _ingestMessages([...settled, response]);
      } else {
        _ingestMessages([response]);
      }
      state = state.copyWith(
        isLoading: false,
        showAssistantPending: false,
        sensitivityLevel:
            isNewSession ? state.sensitivityLevel : chatResponse.sensitivityLevel,
      );

      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      Logger.debug('AgenticChat: Received response [id=${response.messageId}]: $preview');

      if (settings.isAutoPlayback && response.role == AgenticRole.assistant) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.localId);
      }

      if (response.isFinal) _dispatchQueuedIfAny();
    } catch (e) {
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails = e is EngineApiException ? e.technicalDetails : null;

      final errorMessage = AgenticMessage.error(errorText, technicalDetails: technicalDetails);

      // Error settles the cycle so the user is not stuck in awaiting.
      final settled = state.messages
          .where((m) => !m.isFinal)
          .map((m) => m.copyWith(isFinal: true))
          .toList();
      _ingestMessages([...settled, errorMessage]);
      state = state.copyWith(isLoading: false, showAssistantPending: false);

      Logger.debug('AgenticChat: Error sending message: $e');
    }
  }

  /// Pop the queued text into the input field. Caller is responsible for
  /// merging with any text the user has typed (UI policy lives in the page).
  String? editQueued() {
    final text = state.queuedMessage;
    if (text == null) return null;
    state = state.copyWith(clearQueuedMessage: true);
    return text;
  }

  /// Merge incoming messages into state. Contract: append-if-new,
  /// skip-if-known-and-final, replace-if-known-and-non-final.
  void _ingestMessages(List<AgenticMessage> incoming) {
    final out = List<AgenticMessage>.from(state.messages);
    final indexById = <String, int>{
      for (int i = 0; i < out.length; i++) out[i].messageId: i,
    };
    for (final msg in incoming) {
      final idx = indexById[msg.messageId];
      if (idx == null) {
        indexById[msg.messageId] = out.length;
        out.add(msg);
      } else if (!out[idx].isFinal) {
        final existing = out[idx];
        // Guard: preserve approvals if the incoming update lost them.
        out[idx] = (existing.approvals != null && msg.approvals == null)
            ? msg.copyWith(approvals: existing.approvals)
            : msg;
      }
    }
    state = state.copyWith(messages: out);
  }

  /// If a `loadHistory` fetch settled the pending cycle (trailing non-error
  /// message is now final), clear the loading indicators so the UI does not
  /// briefly render both the real assistant message and the pending bubble.
  void _clearPendingIfSettled() {
    if (!state.showAssistantPending) return;
    for (int i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].role == AgenticRole.error) continue;
      if (state.messages[i].isFinal) {
        state = state.copyWith(isLoading: false, showAssistantPending: false);
      }
      return;
    }
  }

  void _dispatchQueuedIfAny() {
    final queued = state.queuedMessage;
    if (queued == null) return;
    state = state.copyWith(clearQueuedMessage: true);
    Logger.debug('AgenticChat: Dispatching queued message');
    // ignore: discarded_futures
    sendMessage(queued);
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

  /// Deletes the current session on the server, removes it from the sessions
  /// list, then starts a fresh empty session.
  Future<void> purgeSession() async {
    final settings = ref.read(settingsProvider);
    final sessionId = settings.agenticSessionId;

    if (sessionId != null) {
      try {
        final settingsNotifier = ref.read(settingsProvider.notifier);
        final password = await settingsNotifier.getEnginePassword();
        final apiKey = await settingsNotifier.getEngineApiKey();

        await deleteSessionApi(
          baseUrl: settings.engineBaseUrl,
          sessionId: sessionId,
          authType: settings.engineAuthType,
          username: settings.engineUsername,
          password: password,
          apiKey: apiKey,
        );

        ref.read(sessionsProvider.notifier).removeSession(sessionId);

        Logger.debug('AgenticChat: Purged session $sessionId');
      } catch (e) {
        // Continue with clearing chat even if deletion fails
        Logger.debug('AgenticChat: Failed to purge session: $e');
      }
    }

    await clearChat();
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
    final sessionId = settings.agenticSessionId;
    final previousLevel = state.sensitivityLevel;

    // Optimistic update
    state = state.copyWith(sensitivityLevel: newLevel);

    if (sessionId == null) return;

    final settingsNotifier = ref.read(settingsProvider.notifier);

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

  /// Grant a specific approval via the per-approval endpoint.
  ///
  /// For session scope, the [grant] body is sent so the engine registers the
  /// session-scoped grant alongside marking the approval granted. For global
  /// scope, the global /grants endpoint is called first and then the
  /// per-approval endpoint records the decision (no grant body — already
  /// satisfied by the global grant).
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
      }

      await grantSessionApproval(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        approvalId: approvalId,
        grant: isGlobal ? null : grant,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      _updateApprovalResolution(
        approvalId,
        ApprovalResolution.granted,
        expiresAt: grant.expiresAt,
      );

      Logger.debug('AgenticChat: Granted approval $approvalId');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to grant approval: $e');
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails =
          e is EngineApiException ? e.technicalDetails : null;
      _ingestMessages([
        AgenticMessage.error(errorText, technicalDetails: technicalDetails),
      ]);
    }
  }

  /// Decline all listed approvals server-side before triggering continuation,
  /// so /continue never races ahead of the decline API calls.
  Future<void> declineAllAndContinue(List<String> approvalIds) async {
    for (final id in approvalIds) {
      _updateApprovalResolution(id, ApprovalResolution.declined,
          skipAutoTrigger: true);
    }

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      await Future.wait([
        for (final id in approvalIds)
          declineSessionApproval(
            baseUrl: settings.engineBaseUrl,
            sessionId: sessionId,
            approvalId: id,
            authType: settings.engineAuthType,
            username: settings.engineUsername,
            password: password,
            apiKey: apiKey,
          ),
      ]);

      Logger.debug('AgenticChat: Declined ${approvalIds.length} approval(s), continuing');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to decline approvals: $e');
      rethrow;
    }

    await triggerContinuation();
  }

  /// Decline a specific approval — records granted=false on the in-flight
  /// SystemAction. Replaces the prior "skip" affordance.
  Future<void> declineApproval(String approvalId) async {
    _updateApprovalResolution(approvalId, ApprovalResolution.declined);

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      await declineSessionApproval(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        approvalId: approvalId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      Logger.debug('AgenticChat: Declined approval $approvalId');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to decline approval: $e');
      rethrow;
    }
  }

  /// Stop the in-flight cycle — engine settles by declining undecided
  /// approvals and marking all in-flight messages final. No assistant
  /// response is produced for the stopped cycle.
  Future<void> stopCycle() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId = settings.agenticSessionId;

    if (sessionId == null) return;

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final settled = await stopSession(
        baseUrl: settings.engineBaseUrl,
        sessionId: sessionId,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      _ingestMessages(settled);
      state = state.copyWith(isLoading: false, showAssistantPending: false);

      Logger.debug('AgenticChat: Stopped cycle on session $sessionId');
      _dispatchQueuedIfAny();
    } catch (e) {
      Logger.debug('AgenticChat: Failed to stop cycle: $e');
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

      final response = chatResponse.message;
      if (response.isFinal) {
        final settled = state.messages
            .where((m) => !m.isFinal)
            .map((m) => m.copyWith(isFinal: true))
            .toList();
        _ingestMessages([...settled, response]);
      } else {
        _ingestMessages([response]);
      }
      state = state.copyWith(
        isLoading: false,
        showAssistantPending: false,
        sensitivityLevel: chatResponse.sensitivityLevel,
      );

      Logger.debug('AgenticChat: Continuation response received');
      if (response.isFinal) _dispatchQueuedIfAny();
    } catch (e) {
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails =
          e is EngineApiException ? e.technicalDetails : null;

      final errorMessage = AgenticMessage.error(
        errorText,
        technicalDetails: technicalDetails,
      );

      // Continuation errors leave the engine cycle in-flight (the
      // SystemAction is still final=false on the engine). Do NOT locally
      // mark the trailing chain final here — that would hide the stuck
      // state and make a /messages retry hit a 409. Recovery is handled
      // by retryFailedMessages re-issuing /continue.
      _ingestMessages([errorMessage]);
      state = state.copyWith(isLoading: false, showAssistantPending: false);

      Logger.debug('AgenticChat: Continuation failed: $e');
    }
  }

  void _updateApprovalResolution(
    String approvalId,
    ApprovalResolution resolution, {
    DateTime? expiresAt,
    bool skipAutoTrigger = false,
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
    if (!skipAutoTrigger) _triggerContinuationIfAllResolved();
  }

  @visibleForTesting
  void setStateForTest(AgenticChatState s) => state = s;

  @visibleForTesting
  void ingestMessagesForTest(List<AgenticMessage> incoming) =>
      _ingestMessages(incoming);

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

  /// Recovery for the trailing error. Stuck continuation -> /continue.
  /// Otherwise re-POST any trailing user messages with no settled response.
  /// Idempotent POST (keyed on messageId) handles engine-side dedup on retry.
  Future<void> retryFailedMessages() async {
    final messages = state.messages;

    AgenticMessage? trailingNonError;
    int trailingNonErrorIndex = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role != AgenticRole.error) {
        trailingNonError = messages[i];
        trailingNonErrorIndex = i;
        break;
      }
    }

    final isStuckContinuation = trailingNonError != null &&
        trailingNonError.role == AgenticRole.system &&
        !trailingNonError.isFinal &&
        (trailingNonError.approvals?.isNotEmpty ?? false) &&
        trailingNonError.approvals!.every(
          (a) => a.resolution != ApprovalResolution.pending,
        );

    if (isStuckContinuation) {
      // Strip just the trailing error(s) — the granted SystemAction
      // stays so that /continue can pick up where it left off.
      state = state.copyWith(
        messages: messages.sublist(0, trailingNonErrorIndex + 1),
      );
      Logger.debug('AgenticChat: Retrying continuation for stuck cycle');
      await triggerContinuation();
      return;
    }

    // Collect trailing user messages with no subsequent final engine response
    // (assistant or system). Idempotent POST reuses the existing messageId.
    final retryMessages = <AgenticMessage>[];
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.role == AgenticRole.error) continue;
      if (msg.role == AgenticRole.user) {
        bool hasResponse = false;
        for (int j = i + 1; j < messages.length; j++) {
          if (messages[j].role == AgenticRole.error) continue;
          if (messages[j].role == AgenticRole.assistant ||
              messages[j].role == AgenticRole.system) {
            hasResponse = true;
          }
          break;
        }
        if (!hasResponse) {
          retryMessages.insert(0, msg);
          continue;
        }
      }
      break;
    }

    if (retryMessages.isEmpty) {
      Logger.debug('AgenticChat: No unsent messages to retry');
      final cleanIndex = trailingNonErrorIndex + 1;
      if (cleanIndex < messages.length) {
        state = state.copyWith(messages: messages.sublist(0, cleanIndex));
      }
      return;
    }

    Logger.debug('AgenticChat: Retrying ${retryMessages.length} message(s)');

    // Strip from the first retry message to the end (includes trailing errors).
    int stripFrom = messages.indexOf(retryMessages.first);
    while (stripFrom > 0 && messages[stripFrom - 1].role == AgenticRole.error) {
      stripFrom--;
    }
    state = state.copyWith(messages: messages.sublist(0, stripFrom));

    for (final userMsg in retryMessages) {
      await _dispatchUserMessage(userMsg);
      if (state.messages.isNotEmpty &&
          state.messages.last.role == AgenticRole.error) {
        break;
      }
    }
  }

  /// Strip trailing error messages and clear the queued message.
  /// Leaves all prior messages intact so the user can see what was said.
  void cancelFailedMessages() {
    final messages = state.messages;
    int lastNonError = messages.length - 1;
    while (lastNonError >= 0 &&
        messages[lastNonError].role == AgenticRole.error) {
      lastNonError--;
    }
    final cleaned = messages.sublist(0, lastNonError + 1);
    state = state.copyWith(
      messages: cleaned,
      clearQueuedMessage: true,
    );
    Logger.debug('AgenticChat: Cancelled failed messages');
  }
}
