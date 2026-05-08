import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/services.dart';
import '/agentic/sse_client.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/sessions_provider.dart';
import '/utils/logger.dart';

const _lastEventIdKey = 'sse_last_event_id';

class SseState {
  final bool isConnected;
  final String? error;
  final String? activeSessionDeleted;

  const SseState({
    this.isConnected = false,
    this.error,
    this.activeSessionDeleted,
  });

  SseState copyWith({
    bool? isConnected,
    String? error,
    String? activeSessionDeleted,
  }) {
    return SseState(
      isConnected: isConnected ?? this.isConnected,
      error: error,
      activeSessionDeleted: activeSessionDeleted ?? this.activeSessionDeleted,
    );
  }

  SseState clearActiveSessionDeleted() {
    return SseState(
      isConnected: isConnected,
      error: error,
      activeSessionDeleted: null,
    );
  }
}


final sseProvider = NotifierProvider<SseNotifier, SseState>(() {
  return SseNotifier();
});

class SseNotifier extends Notifier<SseState> {
  SseClient? _client;
  StreamSubscription<SseEvent>? _eventSubscription;
  bool _fetchInFlight = false;
  bool _refetchPending = false;

  @override
  SseState build() {
    ref.onDispose(() {
      _eventSubscription?.cancel();
      _client?.dispose();
    });
    return const SseState();
  }

  /// Connect if not already connected. Safe to call repeatedly (e.g., on
  /// app lifecycle resume) without tearing down an active connection.
  Future<void> connect() async {
    if (_client != null && _client!.isConnected) return;
    await _connectInternal();
  }

  /// Force a fresh connection, tearing down any existing one. Use after
  /// settings changes that affect the engine URL or credentials.
  Future<void> reconnect() async {
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);

    // Disconnect existing client and reset fetch state
    _eventSubscription?.cancel();
    _client?.dispose();
    _fetchInFlight = false;
    _refetchPending = false;

    final password = await settingsNotifier.getEnginePassword();
    final apiKey = await settingsNotifier.getEngineApiKey();
    final lastEventId = prefs.getInt(_lastEventIdKey) ?? 0;
    Logger.debug('SSE: Persisted lastEventId=$lastEventId');

    _client = SseClient(
      baseUrl: settings.engineBaseUrl,
      authType: settings.engineAuthType,
      username: settings.engineUsername,
      password: password,
      apiKey: apiKey,
      lastEventId: lastEventId,
    );

    _eventSubscription = _client!.events.listen((event) {
      unawaited(_handleEvent(event));
    });

    await _client!.connect();
    state = state.copyWith(isConnected: true);
  }

  /// Fetch messages since the last final message (UUID cursor). Coalesces
  /// concurrent calls: if a fetch is in-flight, marks a re-fetch pending so
  /// one more fetch runs after the current one completes.
  Future<void> fetchSinceCursor() async {
    if (_fetchInFlight) {
      _refetchPending = true;
      return;
    }
    _fetchInFlight = true;
    final messages = ref.read(agenticChatProvider).messages;
    final finalMessages = messages.where((m) => m.isFinal);
    final cursor = finalMessages.isEmpty ? null : finalMessages.last.messageId;
    try {
      await ref
          .read(agenticChatProvider.notifier)
          .loadHistory(afterMessageId: cursor);
    } finally {
      _fetchInFlight = false;
      if (_refetchPending) {
        _refetchPending = false;
        unawaited(fetchSinceCursor());
      }
    }
  }

  Future<void> _handleEvent(SseEvent event) async {
    _persistLastEventId(event.id);

    final settings = ref.read(settingsProvider);
    final currentSessionId = settings.agenticSessionId;

    switch (event) {
      case SessionCreatedEvent(:final sessionId):
        Logger.debug('SSE: Session created: $sessionId');
        // Fetch the new session info and add it to the list
        try {
          final settings = ref.read(settingsProvider);
          final settingsNotifier = ref.read(settingsProvider.notifier);
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

          ref.read(sessionsProvider.notifier).addSession(sessionInfo);

          // Re-read active session ID (may have been set by sendMessage() concurrently)
          final activeSessionId = ref.read(settingsProvider).agenticSessionId;
          if (activeSessionId != null && sessionId == activeSessionId) {
            ref.read(agenticChatProvider.notifier).loadSessionInfo();
          }

          Logger.debug('SSE: Added new session to list: ${sessionInfo.title}');
        } catch (e) {
          Logger.debug('SSE: Failed to fetch new session info: $e');
        }
      case SessionDeletedEvent(:final sessionId):
        Logger.debug('SSE: Session deleted: $sessionId');
        if (currentSessionId != null && sessionId == currentSessionId) {
          Logger.debug(
            'SSE: Active session was deleted, clearing chat state...',
          );
          // Clear the active session from settings
          ref.read(settingsProvider.notifier).clearAgenticSessionId();
          // Clear the chat state to start a new empty session
          ref.read(agenticChatProvider.notifier).clearChat();
          // Remove from sessions list if present
          ref.read(sessionsProvider.notifier).removeSession(sessionId);
          // Set flag to show snackbar notification
          state = state.copyWith(activeSessionDeleted: sessionId);
        } else {
          // Just remove from sessions list if not the active session
          ref.read(sessionsProvider.notifier).removeSession(sessionId);
        }
      case SessionUpdatedEvent(:final sessionId):
        Logger.debug('SSE: Session updated: $sessionId');
        // Fetch updated session info and update in sessions list
        try {
          final settings = ref.read(settingsProvider);
          final settingsNotifier = ref.read(settingsProvider.notifier);
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

          ref.read(sessionsProvider.notifier).updateSession(sessionInfo);

          // Also refresh chat session info if this is the active session
          if (currentSessionId != null && sessionId == currentSessionId) {
            ref.read(agenticChatProvider.notifier).loadSessionInfo();
          }
        } catch (e) {
          Logger.debug('SSE: Failed to fetch updated session info: $e');
        }
      case MessagesAppendedEvent(:final sessionId):
        if (currentSessionId == null || sessionId != currentSessionId) {
          Logger.debug(
            'SSE: Ignoring messages.appended for different session: $sessionId',
          );
          return;
        }
        Logger.debug('SSE: Messages appended, fetching since cursor');
        unawaited(fetchSinceCursor());
      case UnknownEvent(:final eventType):
        Logger.debug('SSE: Unknown event type: $eventType');
    }
  }

  void _persistLastEventId(int eventId) {
    Logger.debug('SSE: Persisting lastEventId=$eventId');
    ref.read(sharedPreferencesProvider).setInt(_lastEventIdKey, eventId);
  }

  void disconnect() {
    _eventSubscription?.cancel();
    _client?.disconnect();
    state = state.copyWith(isConnected: false);
  }

  /// Clear the persisted SSE last event ID from SharedPreferences.
  void clearLastEventId() {
    ref.read(sharedPreferencesProvider).remove(_lastEventIdKey);
  }

  /// Clear the active session deleted flag after showing the notification.
  void clearActiveSessionDeleted() {
    state = state.clearActiveSessionDeleted();
  }
}
