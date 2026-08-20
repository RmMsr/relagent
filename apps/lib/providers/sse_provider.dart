import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agentic_client/agentic_client.dart' hide Logger;
import '/providers/agentic_chat_provider.dart';
import '/providers/displayed_session_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/sessions_provider.dart';
import '/providers/tts_provider.dart';
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

    // Disconnect existing client
    _eventSubscription?.cancel();
    _client?.dispose();

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

  @visibleForTesting
  Future<void> handleEventForTest(SseEvent event) => _handleEvent(event);

  Future<void> _handleEvent(SseEvent event) async {
    _persistLastEventId(event.id);

    final displayedSessionId = ref.read(displayedSessionProvider);

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

          // Re-read displayed session (may have been set by the draft
          // flow's sendMessage() concurrently)
          final currentDisplayed = ref.read(displayedSessionProvider);
          if (currentDisplayed != null && sessionId == currentDisplayed) {
            ref.read(agenticChatProvider(sessionId).notifier).loadSessionInfo();
          }

          Logger.debug('SSE: Added new session to list: ${sessionInfo.title}');
        } catch (e) {
          Logger.debug('SSE: Failed to fetch new session info: $e');
        }
      case SessionDeletedEvent(:final sessionId):
        Logger.debug('SSE: Session deleted: $sessionId');
        if (displayedSessionId != null && sessionId == displayedSessionId) {
          Logger.debug(
            'SSE: Displayed session was deleted, clearing chat state...',
          );
          ref.read(displayedSessionProvider.notifier).show(null);
          ref.read(settingsProvider.notifier).clearAgenticSessionId();
          ref.read(ttsProvider.notifier).onChatCleared();
          // Remove from sessions list if present
          ref.read(sessionsProvider.notifier).removeSession(sessionId);
          // Set flag to show snackbar notification
          state = state.copyWith(activeSessionDeleted: sessionId);
        } else {
          // Just remove from sessions list if not the displayed session
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

          // Also refresh chat session info if this is the displayed session
          if (displayedSessionId != null && sessionId == displayedSessionId) {
            ref.read(agenticChatProvider(sessionId).notifier).loadSessionInfo();
          }
        } catch (e) {
          Logger.debug('SSE: Failed to fetch updated session info: $e');
        }
      case MessagesAppendedEvent(:final sessionId, :final createdAt):
        // Route to a live instance if one exists (displayed, in-flight, or
        // within its idle linger) — never instantiate one just to handle
        // this event, or the SSE loop itself would defeat the memory bound
        // `agenticChatProvider`'s disposal policy relies on (design
        // Decision 4). Otherwise, this session has no full state to
        // reconcile right now — just surface that something happened via a
        // lightweight sessions-list activity bump (design Decision 4 /
        // Sessions List Reflects Background Activity).
        if (ref.exists(agenticChatProvider(sessionId))) {
          Logger.debug('SSE: Messages appended, refreshing $sessionId');
          unawaited(
            ref
                .read(agenticChatProvider(sessionId).notifier)
                .refreshFromServer(),
          );
        } else {
          Logger.debug(
            'SSE: Messages appended for inactive session $sessionId, bumping activity',
          );
          ref
              .read(sessionsProvider.notifier)
              .bumpActivity(sessionId, createdAt);
        }
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
