import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/models.dart';
import '/agentic/services.dart';
import '/providers/displayed_session_provider.dart';
import '/providers/settings_provider.dart';
import '../utils/logger.dart';

class SessionListItem {
  final SessionInfo sessionInfo;
  final bool isActive;

  const SessionListItem({required this.sessionInfo, this.isActive = false});
}

class SessionsState {
  final List<SessionListItem> sessions;
  final bool isLoading;
  final String? error;

  const SessionsState({
    this.sessions = const [],
    this.isLoading = false,
    this.error,
  });

  factory SessionsState.initial() {
    return const SessionsState();
  }

  SessionsState copyWith({
    List<SessionListItem>? sessions,
    bool? isLoading,
    String? error,
  }) {
    return SessionsState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final sessionsProvider = NotifierProvider<SessionsNotifier, SessionsState>(() {
  return SessionsNotifier();
});

class SessionsNotifier extends Notifier<SessionsState> {
  @override
  SessionsState build() {
    return SessionsState.initial();
  }

  Future<void> loadSessions() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    state = state.copyWith(isLoading: true, error: null);

    try {
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final sessions = await getSessionsList(
        baseUrl: settings.engineBaseUrl,
        limit: 100,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      final activeSessionId = ref.read(displayedSessionProvider);

      final sessionItems = sessions.map((session) {
        return SessionListItem(
          sessionInfo: session,
          isActive: session.sessionId == activeSessionId,
        );
      }).toList();

      state = state.copyWith(sessions: sessionItems, isLoading: false);

      Logger.debug('Sessions: Loaded ${sessions.length} sessions');
    } catch (e) {
      Logger.debug('Sessions: Failed to load sessions: $e');
      state = state.copyWith(
        isLoading: false,
        error: e is EngineApiException ? e.userMessage : e.toString(),
      );
    }
  }

  Future<bool> deleteSession(String sessionId) async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    try {
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

      // Remove from local list
      final updatedSessions = state.sessions
          .where((item) => item.sessionInfo.sessionId != sessionId)
          .toList();

      state = state.copyWith(sessions: updatedSessions);

      Logger.debug('Sessions: Deleted session $sessionId');
      return true;
    } catch (e) {
      Logger.debug('Sessions: Failed to delete session: $e');
      state = state.copyWith(
        error: e is EngineApiException ? e.userMessage : e.toString(),
      );
      return false;
    }
  }

  void addSession(SessionInfo sessionInfo) {
    // Check if session already exists
    final existingIndex = state.sessions.indexWhere(
      (item) => item.sessionInfo.sessionId == sessionInfo.sessionId,
    );

    if (existingIndex >= 0) {
      // Update existing session
      final updatedSessions = [...state.sessions];
      updatedSessions[existingIndex] = SessionListItem(
        sessionInfo: sessionInfo,
        isActive: updatedSessions[existingIndex].isActive,
      );
      state = state.copyWith(sessions: updatedSessions);
    } else {
      // Add new session at the beginning
      final newItem = SessionListItem(
        sessionInfo: sessionInfo,
        isActive: false,
      );
      state = state.copyWith(sessions: [newItem, ...state.sessions]);
    }
  }

  void updateSession(SessionInfo sessionInfo) {
    final index = state.sessions.indexWhere(
      (item) => item.sessionInfo.sessionId == sessionInfo.sessionId,
    );

    if (index >= 0) {
      // Get the current isActive state before removing
      final isActive = state.sessions[index].isActive;

      // Remove the old entry
      final updatedSessions = state.sessions
          .where((item) => item.sessionInfo.sessionId != sessionInfo.sessionId)
          .toList();

      // Add the updated session at the beginning (most recently updated)
      final newItem = SessionListItem(
        sessionInfo: sessionInfo,
        isActive: isActive,
      );
      updatedSessions.insert(0, newItem);

      state = state.copyWith(sessions: updatedSessions);
      Logger.debug(
        'Sessions: Updated and reordered session ${sessionInfo.sessionId}',
      );
    }
  }

  /// Lightweight update for a session with no live `agenticChatProvider`
  /// instance: bump its last-activity timestamp and move it to the top,
  /// without a `getSessionInfo()` fetch. Used when a `messages.appended`
  /// SSE event arrives for a session nothing is currently displaying (see
  /// `specs/agentic-chat/spec.md`'s Sessions List Reflects Background
  /// Activity requirement).
  ///
  /// No-ops if the session isn't in the list, or if [timestamp] is not
  /// strictly newer than what's already shown — events can arrive
  /// out of order across an SSE reconnect, and an older timestamp must
  /// not regress an already-newer displayed one.
  void bumpActivity(String sessionId, DateTime timestamp) {
    final index = state.sessions.indexWhere(
      (item) => item.sessionInfo.sessionId == sessionId,
    );
    if (index < 0) return;

    final current = state.sessions[index];
    if (!timestamp.isAfter(current.sessionInfo.updatedAt)) return;

    final bumped = SessionListItem(
      sessionInfo: SessionInfo(
        sessionId: current.sessionInfo.sessionId,
        title: current.sessionInfo.title,
        createdAt: current.sessionInfo.createdAt,
        updatedAt: timestamp,
      ),
      isActive: current.isActive,
    );

    final updatedSessions = state.sessions
        .where((item) => item.sessionInfo.sessionId != sessionId)
        .toList();
    updatedSessions.insert(0, bumped);

    state = state.copyWith(sessions: updatedSessions);
    Logger.debug('Sessions: Bumped activity for $sessionId');
  }

  void removeSession(String sessionId) {
    final updatedSessions = state.sessions
        .where((item) => item.sessionInfo.sessionId != sessionId)
        .toList();
    state = state.copyWith(sessions: updatedSessions);
  }

  void updateActiveSession(String? sessionId) {
    final updatedSessions = state.sessions.map((item) {
      return SessionListItem(
        sessionInfo: item.sessionInfo,
        isActive: item.sessionInfo.sessionId == sessionId,
      );
    }).toList();
    state = state.copyWith(sessions: updatedSessions);
  }

  void clearSessions() {
    state = SessionsState.initial();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}
