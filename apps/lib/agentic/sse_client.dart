import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '/models/settings.dart';
import '/utils/logger.dart';

sealed class SseEvent {
  final int id;
  const SseEvent({required this.id});

  factory SseEvent.fromSse(String eventType, String id, String data) {
    final parsedId = int.parse(id);
    final json = jsonDecode(data) as Map<String, dynamic>;
    return switch (eventType) {
      'session.created' => SessionCreatedEvent(
        id: parsedId,
        sessionId: json['session_id'] as String,
      ),
      'session.deleted' => SessionDeletedEvent(
        id: parsedId,
        sessionId: json['session_id'] as String,
      ),
      'session.updated' => SessionUpdatedEvent(
        id: parsedId,
        sessionId: json['session_id'] as String,
      ),
      'session.messages.appended' => MessagesAppendedEvent(
        id: parsedId,
        sessionId: json['session_id'] as String,
        latestSequenceId: json['latest_sequence_id'] as int,
      ),
      _ => UnknownEvent(id: parsedId, eventType: eventType),
    };
  }
}

class SessionCreatedEvent extends SseEvent {
  final String sessionId;
  const SessionCreatedEvent({required super.id, required this.sessionId});
  @override
  String toString() => 'SessionCreatedEvent(id=$id, session=$sessionId)';
}

class SessionDeletedEvent extends SseEvent {
  final String sessionId;
  const SessionDeletedEvent({required super.id, required this.sessionId});
  @override
  String toString() => 'SessionDeletedEvent(id=$id, session=$sessionId)';
}

class SessionUpdatedEvent extends SseEvent {
  final String sessionId;
  const SessionUpdatedEvent({required super.id, required this.sessionId});
  @override
  String toString() => 'SessionUpdatedEvent(id=$id, session=$sessionId)';
}

class MessagesAppendedEvent extends SseEvent {
  final String sessionId;
  final int latestSequenceId;
  const MessagesAppendedEvent({
    required super.id,
    required this.sessionId,
    required this.latestSequenceId,
  });
  @override
  String toString() =>
      'MessagesAppendedEvent(id=$id, session=$sessionId, sequenceId=$latestSequenceId)';
}

class UnknownEvent extends SseEvent {
  final String eventType;
  const UnknownEvent({required super.id, required this.eventType});
  @override
  String toString() => 'UnknownEvent(id=$id, type=$eventType)';
}

class SseClient {
  final String baseUrl;
  final AuthType authType;
  final String? username;
  final String? password;

  http.Client? _client;
  StreamSubscription<String>? _subscription;
  int _lastEventId;
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 60);

  final StreamController<SseEvent> _eventController =
      StreamController<SseEvent>.broadcast();

  Stream<SseEvent> get events => _eventController.stream;
  bool get isConnected => _isConnected;
  int get lastEventId => _lastEventId;

  final http.Client? _injectedClient;

  SseClient({
    required this.baseUrl,
    required this.authType,
    this.username,
    this.password,
    int lastEventId = 0,
    http.Client? httpClient,
  }) : _lastEventId = lastEventId,
       _injectedClient = httpClient;

  Future<void> connect() async {
    if (_isConnected) return;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (!_shouldReconnect) return;
    _reconnectScheduled = false;

    // Clean up previous connection resources
    _subscription?.cancel();
    _subscription = null;
    if (_injectedClient == null) {
      _client?.close();
    }
    _client = null;

    try {
      _client = _injectedClient ?? http.Client();
      final url = _buildUrl();
      final headers = _buildHeaders();

      Logger.debug('SSE: Connecting to $url (lastEventId=$_lastEventId)');

      final request = http.Request('GET', Uri.parse(url));
      headers.forEach((key, value) => request.headers[key] = value);

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        throw Exception('SSE connection failed: ${response.statusCode}');
      }

      _isConnected = true;
      _reconnectAttempts = 0;
      Logger.debug('SSE: Connected');

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onError: _handleError,
            onDone: _handleDone,
            cancelOnError: false,
          );
    } catch (e) {
      Logger.debug('SSE: Connection error: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  String _buildUrl() {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return '$url/api/v1/events';
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
    };

    if (_lastEventId > 0) {
      headers['Last-Event-ID'] = _lastEventId.toString();
    }

    if (authType == AuthType.basic && username != null && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      headers['Authorization'] = 'Basic $credentials';
    }

    return headers;
  }

  String? _currentEventType;
  String? _currentId;
  String? _currentData;

  void _handleLine(String line) {
    if (line.isEmpty) {
      // Empty line = end of event
      if (_currentEventType != null &&
          _currentId != null &&
          _currentData != null) {
        try {
          final event = SseEvent.fromSse(
            _currentEventType!,
            _currentId!,
            _currentData!,
          );
          _lastEventId = event.id;
          _eventController.add(event);
          Logger.debug('SSE: Received event: $event, data: $_currentData');
        } catch (e) {
          Logger.debug('SSE: Failed to parse event: $e');
        }
      }
      _currentEventType = null;
      _currentId = null;
      _currentData = null;
      return;
    }

    if (line.startsWith(':')) {
      // Comment (heartbeat)
      return;
    }

    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) return;

    final field = line.substring(0, colonIndex);
    var value = line.substring(colonIndex + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _currentEventType = value;
      case 'id':
        _currentId = value;
      case 'data':
        _currentData = value;
    }
  }

  bool _reconnectScheduled = false;

  void _handleError(dynamic error) {
    Logger.debug('SSE: Stream error: $error');
    _isConnected = false;
    _scheduleReconnectOnce();
  }

  void _handleDone() {
    Logger.debug('SSE: Stream closed');
    _isConnected = false;
    _scheduleReconnectOnce();
  }

  void _scheduleReconnectOnce() {
    if (_reconnectScheduled) return;
    _reconnectScheduled = true;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      Logger.debug('SSE: Max reconnect attempts reached');
      return;
    }

    final backoff = _calculateBackoff();
    _reconnectAttempts++;
    Logger.debug(
      'SSE: Reconnecting in ${backoff.inSeconds}s (attempt $_reconnectAttempts)',
    );

    Future.delayed(backoff, () {
      if (_shouldReconnect) {
        _doConnect();
      }
    });
  }

  Duration _calculateBackoff() {
    final seconds = _initialBackoff.inSeconds * (1 << _reconnectAttempts);
    return Duration(seconds: seconds.clamp(1, _maxBackoff.inSeconds));
  }

  void disconnect() {
    Logger.debug('SSE: Disconnecting');
    _shouldReconnect = false;
    _subscription?.cancel();
    _client?.close();
    _isConnected = false;
  }

  void dispose() {
    disconnect();
    _eventController.close();
  }
}
