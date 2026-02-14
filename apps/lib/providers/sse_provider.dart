import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/sse_client.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/settings_provider.dart';
import '/utils/logger.dart';

const _lastEventIdKey = 'sse_last_event_id';

class SseState {
  final bool isConnected;
  final String? error;

  const SseState({this.isConnected = false, this.error});

  SseState copyWith({bool? isConnected, String? error}) {
    return SseState(isConnected: isConnected ?? this.isConnected, error: error);
  }
}

/// Tracks pending messages.appended events and deduplicates them.
///
/// When multiple events arrive before a fetch completes, only the first
/// triggers a fetch. The lowest sequence ID is kept as the fetch origin
/// because a single fetch from the lowest point covers all higher ones.
class MessageEventDedup {
  int? _lastProcessedSequenceId;
  bool _fetchInFlight = false;

  /// Evaluate whether a messages.appended event should trigger a fetch.
  ///
  /// Returns the `fromId` to fetch from, or `null` to indicate a full load.
  /// Returns `skip` if the event is a duplicate or a fetch is already in-flight.
  /// Seed with the highest sequence ID already loaded locally.
  ///
  /// Events with sequence IDs at or below this value will be skipped.
  void seed(int? sequenceId) {
    if (sequenceId == null) return;
    if (_lastProcessedSequenceId == null ||
        sequenceId > _lastProcessedSequenceId!) {
      _lastProcessedSequenceId = sequenceId;
    }
  }

  ({int? fromId, bool skip}) onEvent(int latestSequenceId) {
    if (_lastProcessedSequenceId != null &&
        latestSequenceId <= _lastProcessedSequenceId!) {
      return (fromId: null, skip: true);
    }

    if (_fetchInFlight) {
      // A fetch is already in-flight from a lower sequence ID and will
      // cover this event's data too. Just absorb the higher sequence ID.
      _lastProcessedSequenceId = latestSequenceId;
      return (fromId: null, skip: true);
    }

    final fromId = _lastProcessedSequenceId != null
        ? _lastProcessedSequenceId! + 1
        : null;
    _lastProcessedSequenceId = latestSequenceId;
    _fetchInFlight = true;
    return (fromId: fromId, skip: false);
  }

  void fetchComplete() {
    _fetchInFlight = false;
  }

  void reset() {
    _lastProcessedSequenceId = null;
    _fetchInFlight = false;
  }
}

final sseProvider = NotifierProvider<SseNotifier, SseState>(() {
  return SseNotifier();
});

class SseNotifier extends Notifier<SseState> {
  SseClient? _client;
  StreamSubscription<SseEvent>? _eventSubscription;
  final _messageDedup = MessageEventDedup();

  @override
  SseState build() {
    ref.onDispose(() {
      _eventSubscription?.cancel();
      _client?.dispose();
    });
    return const SseState();
  }

  Future<void> connect() async {
    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final prefs = ref.read(sharedPreferencesProvider);

    // Disconnect existing client and reset dedup state
    _eventSubscription?.cancel();
    _client?.dispose();
    _messageDedup.reset();

    final password = await settingsNotifier.getEnginePassword();
    final lastEventId = prefs.getInt(_lastEventIdKey) ?? 0;
    Logger.debug('SSE: Persisted lastEventId=$lastEventId');

    _client = SseClient(
      baseUrl: settings.engineBaseUrl,
      authType: settings.engineAuthType,
      username: settings.engineUsername,
      password: password,
      lastEventId: lastEventId,
    );

    _eventSubscription = _client!.events.listen(_handleEvent);

    await _client!.connect();
    state = state.copyWith(isConnected: true);
  }

  void _handleEvent(SseEvent event) {
    _persistLastEventId(event.id);

    final settings = ref.read(settingsProvider);
    final currentSessionId = settings.agenticSessionId;

    switch (event) {
      case SessionUpdatedEvent(:final sessionId):
        if (currentSessionId == null || sessionId != currentSessionId) {
          Logger.debug(
            'SSE: Ignoring session.updated for different session: $sessionId',
          );
          return;
        }
        Logger.debug('SSE: Session updated, refreshing session info...');
        ref.read(agenticChatProvider.notifier).loadSessionInfo();
      case MessagesAppendedEvent(:final sessionId, :final latestSequenceId):
        if (currentSessionId == null || sessionId != currentSessionId) {
          Logger.debug(
            'SSE: Ignoring messages.appended for different session: $sessionId',
          );
          return;
        }
        _seedDedupFromChat();
        final result = _messageDedup.onEvent(latestSequenceId);
        if (result.skip) {
          Logger.debug(
            'SSE: Skipping messages.appended (sequenceId=$latestSequenceId)',
          );
          return;
        }
        Logger.debug(
          'SSE: Messages appended, fetching from ${result.fromId ?? "start"} up to $latestSequenceId',
        );
        ref
            .read(agenticChatProvider.notifier)
            .loadHistory(fromId: result.fromId)
            .whenComplete(_messageDedup.fetchComplete);
      case UnknownEvent(:final eventType):
        Logger.debug('SSE: Unknown event type: $eventType');
    }
  }

  void _persistLastEventId(int eventId) {
    Logger.debug('SSE: Persisting lastEventId=$eventId');
    ref.read(sharedPreferencesProvider).setInt(_lastEventIdKey, eventId);
  }

  void _seedDedupFromChat() {
    final messages = ref.read(agenticChatProvider).messages;
    if (messages.isEmpty) return;
    final maxId = messages.last.id;
    if (maxId != null) _messageDedup.seed(maxId);
  }

  void disconnect() {
    _eventSubscription?.cancel();
    _client?.disconnect();
    state = state.copyWith(isConnected: false);
  }
}
