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
        final merged = _mergeRefresh(state.messages, messages);
        state = state.copyWith(
          messages: merged,
          isLoadingHistory: false,
        );
        Logger.debug(
          'AgenticChat: Refreshed from index $fromId — ${messages.length} fetched',
        );
        // Incremental refresh is SSE-driven and may settle the cycle.
        _dispatchQueuedIfAny();
      } else {
        // Full load is not a settle event — do not auto-dispatch.
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

    // Strict-ordering: if a cycle is in flight, hold the message in the
    // single queue slot. Auto-dispatched once the in-flight cycle settles.
    if (state.isAwaiting) {
      state = state.copyWith(queuedMessage: text);
      Logger.debug('AgenticChat: Cycle in flight — queued message');
      return;
    }

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final sessionId =
        settings.agenticSessionId; // May be null for first message

    // Add user message locally (in-flight: isFinal defaults to false)
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

      // Only flip the in-flight chain when the response itself settles the
      // cycle. A SystemAction response (isFinal=false) keeps it in-flight.
      final appended = [...state.messages, response];
      final newMessages = response.isFinal
          ? _markTrailingFinal(appended)
          : appended;
      state = state.copyWith(
        messages: newMessages,
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

      if (response.isFinal) _dispatchQueuedIfAny();
    } catch (e) {
      final errorText = e is EngineApiException ? e.userMessage : e.toString();
      final technicalDetails = e is EngineApiException
          ? e.technicalDetails
          : null;

      final errorMessage = AgenticMessage.error(
        errorText,
        technicalDetails: technicalDetails,
      );

      // Error settles the cycle: flip in-flight messages final so the user
      // can retry without staying stuck in awaiting.
      final appended = [...state.messages, errorMessage];
      state = state.copyWith(
        messages: _markTrailingFinal(appended),
        isLoading: false,
        showAssistantPending: false,
      );

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

  /// Merge fetched messages into the cache. Cached `final=true` entries are
  /// immutable and never overwritten; cached `final=false` entries are
  /// replaced with the fetched version; absent entries are appended in
  /// fetched order at the end.
  List<AgenticMessage> _mergeRefresh(
    List<AgenticMessage> current,
    List<AgenticMessage> fetched,
  ) {
    final out = List<AgenticMessage>.from(current);
    final indexById = <int, int>{
      for (int i = 0; i < out.length; i++)
        if (out[i].id != null) out[i].id!: i,
    };
    for (final msg in fetched) {
      final id = msg.id;
      if (id == null) {
        out.add(msg);
        continue;
      }
      final idx = indexById[id];
      if (idx == null) {
        indexById[id] = out.length;
        out.add(msg);
      } else if (!out[idx].isFinal) {
        out[idx] = msg;
      }
    }
    return out;
  }

  /// Settle the in-flight chain that ends in [messages.last]. The caller MUST
  /// only invoke this after appending a settlement event (an AssistantMessage
  /// or an error). Walks back from the second-to-last entry, flipping every
  /// non-final message to final, stopping at the prior cycle boundary.
  List<AgenticMessage> _markTrailingFinal(List<AgenticMessage> messages) {
    final out = List<AgenticMessage>.from(messages);
    if (out.isEmpty) return out;
    for (int i = out.length - 2; i >= 0; i--) {
      if (out[i].isFinal) break;
      out[i] = out[i].copyWith(isFinal: true);
    }
    return out;
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
      rethrow;
    }
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

      final merged = _mergeRefresh(state.messages, settled);
      state = state.copyWith(
        messages: merged,
        isLoading: false,
        showAssistantPending: false,
      );

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
      final appended = [...state.messages, response];
      final newMessages = response.isFinal
          ? _markTrailingFinal(appended)
          : appended;
      state = state.copyWith(
        messages: newMessages,
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

  @visibleForTesting
  List<AgenticMessage> mergeRefreshForTest(
    List<AgenticMessage> current,
    List<AgenticMessage> fetched,
  ) => _mergeRefresh(current, fetched);

  @visibleForTesting
  List<AgenticMessage> markTrailingFinalForTest(List<AgenticMessage> messages) =>
      _markTrailingFinal(messages);

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
  /// Otherwise re-POST any trailing user messages with no engine id.
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

    // Otherwise: collect trailing user messages (no engine id) as the
    // texts to resend, then strip them along with the errors and
    // re-POST.
    final unsentUserMessages = <String>[];
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.role == AgenticRole.error) continue;
      if (msg.role == AgenticRole.user && msg.id == null) {
        unsentUserMessages.insert(0, msg.text);
        continue;
      }
      break;
    }

    if (unsentUserMessages.isEmpty) {
      Logger.debug('AgenticChat: No unsent messages to retry');
      // Nothing to resend — at minimum drop the trailing error so the
      // user is not stuck looking at a stale failure card.
      final cleanIndex = trailingNonErrorIndex + 1;
      if (cleanIndex < messages.length) {
        state =
            state.copyWith(messages: messages.sublist(0, cleanIndex));
      }
      return;
    }

    Logger.debug(
      'AgenticChat: Retrying ${unsentUserMessages.length} unsent message(s)',
    );

    // Strip everything from the first unsent user message to the end
    // (the user records + any trailing error).
    final firstUnsentIndex = messages.length - unsentUserMessages.length;
    // Walk back further to skip any error messages immediately before
    // the user records (defensive — usually they're after).
    int stripFrom = firstUnsentIndex;
    while (stripFrom > 0 &&
        messages[stripFrom - 1].role == AgenticRole.error) {
      stripFrom--;
    }
    state = state.copyWith(messages: messages.sublist(0, stripFrom));

    for (final text in unsentUserMessages) {
      await sendMessage(text);
      if (state.messages.isNotEmpty &&
          state.messages.last.role == AgenticRole.error) {
        break;
      }
    }
  }
}
