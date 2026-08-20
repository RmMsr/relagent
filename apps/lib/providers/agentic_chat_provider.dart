import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show KeepAliveLink;
import 'package:http/http.dart' as http;

import '/agentic/models.dart';
import '/agentic/services.dart';
import '/providers/displayed_session_provider.dart';
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

/// One isolated instance per session. A response for session A can never be
/// applied to session B's state, because they are different instances —
/// see `specs/agentic-chat/spec.md`'s Session Isolation requirement.
final agenticChatProvider = NotifierProvider.autoDispose
    .family<AgenticChatNotifier, AgenticChatState, String>(
      (sessionId) => AgenticChatNotifier(sessionId),
    );

class AgenticChatNotifier extends Notifier<AgenticChatState> {
  static const _idleLinger = Duration(milliseconds: 500);

  final String sessionId;
  Timer? _lingerTimer;
  KeepAliveLink? _keepAliveLink;
  // Riverpod forbids reading `state`/`ref` from inside onCancel/onResume
  // (`_debugCallbackStack` guard) — this plain field mirrors
  // `state.isAwaiting` so onCancel can check it without touching `state`.
  bool _isAwaiting = false;

  AgenticChatNotifier(this.sessionId);

  @override
  AgenticChatState build() {
    // Disposal policy: while this session has an unwatched but genuinely
    // idle instance, allow a short linger before disposal so a quick flip
    // back to it reuses the still-warm state. While a cycle is actually in
    // flight, hold indefinitely regardless of watch state — a background
    // approval must not be silently dropped. See design Decision 3.
    ref.onCancel(() {
      if (_isAwaiting) return; // already held indefinitely by the setter
      // Riverpod forbids calling ref.keepAlive() synchronously from within
      // a life-cycle callback (`_debugCallbackStack` guard covers
      // onCancel/onResume/onDispose alike). Defer to the next microtask —
      // by then the callback-stack restriction has cleared — and re-check
      // ref.mounted (a plain getter, unrestricted) since disposal could in
      // principle have already completed by the time this runs.
      scheduleMicrotask(() {
        if (ref.mounted) _armIdleLinger();
      });
    });
    ref.onResume(() {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _keepAliveLink?.close();
      _keepAliveLink = null;
    });
    ref.onDispose(() {
      _lingerTimer?.cancel();
    });

    return AgenticChatState.initial();
  }

  // `listenSelf` isn't reachable from a hand-written (non-codegen) Notifier
  // in this Riverpod version, so the same "react to every state change"
  // hook is done by overriding the setter instead. Does not fire for the
  // initial `build()` return value — the framework sets that via a
  // different internal path — but that value is always non-awaiting, so
  // there is nothing to arm here for it.
  @override
  set state(AgenticChatState value) {
    super.state = value;
    _isAwaiting = value.isAwaiting;
    if (_isAwaiting) {
      _lingerTimer?.cancel();
      _lingerTimer = null;
      _keepAliveLink ??= ref.keepAlive();
    } else {
      _armIdleLinger();
    }
  }

  void _armIdleLinger() {
    _lingerTimer?.cancel();
    _keepAliveLink ??= ref.keepAlive();
    _lingerTimer = Timer(_idleLinger, () {
      _keepAliveLink?.close();
      _keepAliveLink = null;
    });
  }

  /// Seeds a freshly-created session's instance with its first exchange,
  /// right after the engine assigns it a session id (see
  /// `NewChatDraftNotifier.sendMessage`).
  void seedFirstExchange({
    required AgenticMessage userMessage,
    required AgenticMessage response,
    required SensitivityLevel sensitivityLevel,
  }) {
    if (response.isFinal) {
      _ingestMessages([userMessage.copyWith(isFinal: true), response]);
    } else {
      _ingestMessages([userMessage, response]);
    }
    state = state.copyWith(sensitivityLevel: sensitivityLevel);
  }

  bool _refreshInFlight = false;
  bool _refreshPending = false;

  /// Fetch anything new since the last known final message (or everything,
  /// if none is known yet — a fresh instance naturally has none) and merge
  /// it in. The single entry point for "make sure this matches the server":
  /// used on first display, session switch, app resume, and SSE-triggered
  /// refresh alike. Cheap when nothing changed, correct regardless of
  /// source (see design Decision 5).
  ///
  /// Coalesces concurrent calls (e.g. rapid-fire SSE events for this same
  /// session): if a fetch is already in flight, marks one more re-fetch
  /// pending rather than firing overlapping requests.
  Future<void> refreshFromServer({
    @visibleForTesting http.Client? client,
  }) async {
    if (!ref.mounted) return;
    if (_refreshInFlight) {
      _refreshPending = true;
      return;
    }
    _refreshInFlight = true;
    try {
      final finalMessages = state.messages.where((m) => m.isFinal);
      final cursor = finalMessages.isEmpty
          ? null
          : finalMessages.last.messageId;
      await loadHistory(afterMessageId: cursor, client: client);
    } finally {
      _refreshInFlight = false;
      if (_refreshPending) {
        _refreshPending = false;
        if (ref.mounted) unawaited(refreshFromServer(client: client));
      }
    }
  }

  @visibleForTesting
  Future<void> loadHistory({
    String? afterMessageId,
    @visibleForTesting http.Client? client,
  }) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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

      // Disposed mid-flight (e.g. the idle linger ran out while this
      // request was still in the air, or the whole container tore down).
      // Nothing left to apply this to — and touching `state`/`ref` past
      // disposal throws.
      if (!ref.mounted) return;

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
      if (!ref.mounted) return;
      Logger.debug('AgenticChat: Failed to load history: $e');
      state = state.copyWith(
        isLoadingHistory: false,
        error: e is EngineApiException ? e.userMessage : e.toString(),
      );
    }
  }

  Future<void> sendMessage(
    String text, {
    @visibleForTesting http.Client? client,
  }) async {
    if (text.trim().isEmpty) return;

    // Strict-ordering: if a cycle is in flight, hold the message in the
    // single queue slot. Auto-dispatched once the in-flight cycle settles.
    if (state.isAwaiting) {
      state = state.copyWith(queuedMessage: text);
      Logger.debug('AgenticChat: Cycle in flight — queued message');
      return;
    }

    await _dispatchUserMessage(AgenticMessage.user(text), client: client);
  }

  Future<void> _dispatchUserMessage(
    AgenticMessage userMessage, {
    @visibleForTesting http.Client? client,
  }) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
        client: client,
      );

      if (!ref.mounted) return;

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

      final preview = response.text.length > 50
          ? '${response.text.substring(0, 50)}...'
          : response.text;
      Logger.debug('AgenticChat: Received response [id=${response.messageId}]: $preview');

      // Re-read settings rather than reusing the snapshot captured before
      // the request: auto-playback may have been turned on while the
      // response was still in flight, and that must still apply to it.
      if (ref.read(settingsProvider).isAutoPlayback &&
          response.role == AgenticRole.assistant) {
        ref.read(ttsProvider.notifier).enqueue(response.text, response.localId);
      }

      if (response.isFinal) _dispatchQueuedIfAny();
    } catch (e) {
      if (!ref.mounted) return;

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

  /// Deletes this session on the server, removes it from the sessions list,
  /// then hands display back to the "start a new chat" draft.
  Future<void> purgeSession() async {
    final settings = ref.read(settingsProvider);

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

      if (!ref.mounted) return;
      ref.read(sessionsProvider.notifier).removeSession(sessionId);

      Logger.debug('AgenticChat: Purged session $sessionId');
    } catch (e) {
      // Continue with clearing chat even if deletion fails
      Logger.debug('AgenticChat: Failed to purge session: $e');
    }

    if (!ref.mounted) return;
    ref.read(displayedSessionProvider.notifier).show(null);
    await ref.read(settingsProvider.notifier).clearAgenticSessionId();
    if (!ref.mounted) return;
    ref.read(ttsProvider.notifier).onChatCleared();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> loadSessionInfo() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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

      if (!ref.mounted) return;
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
    final previousLevel = state.sensitivityLevel;

    // Optimistic update
    state = state.copyWith(sensitivityLevel: newLevel);

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
      if (ref.mounted) {
        state = state.copyWith(sensitivityLevel: previousLevel);
      }
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
    @visibleForTesting http.Client? client,
  }) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
        client: client,
      );

      if (!ref.mounted) return;
      _updateApprovalResolution(
        approvalId,
        ApprovalResolution.granted,
        expiresAt: grant.expiresAt,
      );

      Logger.debug('AgenticChat: Granted approval $approvalId');
    } catch (e) {
      Logger.debug('AgenticChat: Failed to grant approval: $e');
      if (!ref.mounted) return;
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

    if (!ref.mounted) return;
    await triggerContinuation();
  }

  /// Decline a specific approval — records granted=false on the in-flight
  /// SystemAction. Replaces the prior "skip" affordance.
  Future<void> declineApproval(String approvalId) async {
    _updateApprovalResolution(approvalId, ApprovalResolution.declined);

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
  Future<void> stopCycle({@visibleForTesting http.Client? client}) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
        client: client,
      );

      if (!ref.mounted) return;
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
  Future<void> triggerContinuation({
    @visibleForTesting http.Client? client,
  }) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
        client: client,
      );

      if (!ref.mounted) return;

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
      if (!ref.mounted) return;

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

    // Keep the trailing error(s) in place so the user can follow the sequence
    // of events. The re-POSTed user messages already live in history and are
    // settled, so _dispatchUserMessage's optimistic add is deduped by
    // _ingestMessages — the user message is not duplicated, and the fresh
    // response (or a new error) is appended after the preserved error.
    for (final userMsg in retryMessages) {
      await _dispatchUserMessage(userMsg);
      if (!ref.mounted) break;
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
