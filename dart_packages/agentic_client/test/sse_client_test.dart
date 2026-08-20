import 'dart:async';
import 'dart:convert';

import 'package:agentic_client/agentic_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Creates a [MockClient] that captures the request and streams SSE data
/// from the returned [StreamController].
({MockClient client, StreamController<List<int>> controller})
    _createStreamingMock({void Function(http.BaseRequest request)? onRequest}) {
  final controller = StreamController<List<int>>();
  final client = MockClient.streaming((request, bodyStream) async {
    onRequest?.call(request);
    return http.StreamedResponse(controller.stream, 200);
  });
  return (client: client, controller: controller);
}

void main() {
  group('SseEvent.fromSse parsing', () {
    test('parses session.updated into SessionUpdatedEvent', () {
      final event = SseEvent.fromSse(
        'session.updated',
        '7',
        '{"session_id": "abc-123", "created_at": "2025-01-01T00:00:00Z"}',
      );

      expect(event, isA<SessionUpdatedEvent>());
      final typed = event as SessionUpdatedEvent;
      expect(typed.id, 7);
      expect(typed.sessionId, 'abc-123');
    });

    test('parses session.messages.appended into MessagesAppendedEvent', () {
      final event = SseEvent.fromSse(
        'session.messages.appended',
        '42',
        '{"session_id": "sess-1", "created_at": "2025-01-01T00:00:00Z"}',
      );

      expect(event, isA<MessagesAppendedEvent>());
      final typed = event as MessagesAppendedEvent;
      expect(typed.id, 42);
      expect(typed.sessionId, 'sess-1');
    });

    test('parses unknown event type into UnknownEvent', () {
      final event = SseEvent.fromSse(
        'some.future.event',
        '3',
        '{"foo": "bar", "created_at": "2025-01-01T00:00:00Z"}',
      );

      expect(event, isA<UnknownEvent>());
      final typed = event as UnknownEvent;
      expect(typed.id, 3);
      expect(typed.eventType, 'some.future.event');
    });

    test('parses id from string correctly', () {
      final event = SseEvent.fromSse(
        'session.updated',
        '12345',
        '{"session_id": "x", "created_at": "2025-01-01T00:00:00Z"}',
      );

      expect(event.id, 12345);
    });

    test('parses created_at from the event envelope', () {
      final event = SseEvent.fromSse(
        'session.updated',
        '1',
        '{"session_id": "x", "created_at": "2025-06-15T12:30:00Z"}',
      );

      expect(event.createdAt, DateTime.utc(2025, 6, 15, 12, 30));
    });
  });

  group('SseClient connection and event streaming', () {
    test('SSE lines are parsed into typed events on the stream', () async {
      final mock = _createStreamingMock();

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      final events = <SseEvent>[];
      client.events.listen(events.add);

      await client.connect();

      mock.controller.add(
        utf8.encode(
          'event: session.updated\n'
          'id: 1\n'
          'data: {"session_id": "abc", "created_at": "2025-01-01T00:00:00Z"}\n'
          '\n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events.first, isA<SessionUpdatedEvent>());
      final typed = events.first as SessionUpdatedEvent;
      expect(typed.id, 1);
      expect(typed.sessionId, 'abc');

      client.disconnect();
      await mock.controller.close();
    });

    test('Last-Event-ID header is sent when lastEventId > 0', () async {
      http.BaseRequest? capturedRequest;
      final mock = _createStreamingMock(
        onRequest: (request) => capturedRequest = request,
      );

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        lastEventId: 42,
        httpClient: mock.client,
      );

      await client.connect();

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers['Last-Event-ID'], '42');

      client.disconnect();
      await mock.controller.close();
    });

    test('Last-Event-ID header is NOT sent when lastEventId is 0', () async {
      http.BaseRequest? capturedRequest;
      final mock = _createStreamingMock(
        onRequest: (request) => capturedRequest = request,
      );

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      await client.connect();

      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.headers.containsKey('Last-Event-ID'), isFalse);

      client.disconnect();
      await mock.controller.close();
    });

    test('Basic auth header is sent when authType is basic', () async {
      http.BaseRequest? capturedRequest;
      final mock = _createStreamingMock(
        onRequest: (request) => capturedRequest = request,
      );

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.basic,
        username: 'user',
        password: 'pass',
        httpClient: mock.client,
      );

      await client.connect();

      expect(capturedRequest, isNotNull);
      final authHeader = capturedRequest!.headers['Authorization'];
      expect(authHeader, isNotNull);
      final expectedCredentials = base64Encode(utf8.encode('user:pass'));
      expect(authHeader, 'Basic $expectedCredentials');

      client.disconnect();
      await mock.controller.close();
    });

    test('lastEventId updates after receiving events', () async {
      final mock = _createStreamingMock();

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      expect(client.lastEventId, 0);

      await client.connect();

      mock.controller.add(
        utf8.encode(
          'event: session.updated\n'
          'id: 5\n'
          'data: {"session_id": "x", "created_at": "2025-01-01T00:00:00Z"}\n'
          '\n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.lastEventId, 5);

      client.disconnect();
      await mock.controller.close();
    });

    test('heartbeat comments are ignored', () async {
      final mock = _createStreamingMock();

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      final events = <SseEvent>[];
      client.events.listen(events.add);

      await client.connect();

      mock.controller.add(
        utf8.encode(
          ': heartbeat\n'
          '\n'
          'event: session.updated\n'
          'id: 1\n'
          'data: {"session_id": "x", "created_at": "2025-01-01T00:00:00Z"}\n'
          '\n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, hasLength(1));
      expect(events.first, isA<SessionUpdatedEvent>());

      client.disconnect();
      await mock.controller.close();
    });

    test('incomplete events are not emitted', () async {
      final mock = _createStreamingMock();

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      final events = <SseEvent>[];
      client.events.listen(events.add);

      await client.connect();

      // Event with missing data field
      mock.controller.add(
        utf8.encode(
          'event: session.updated\n'
          'id: 1\n'
          '\n',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);

      client.disconnect();
      await mock.controller.close();
    });
  });

  group('disconnect prevents reconnection', () {
    test('disconnect sets isConnected to false', () async {
      final mock = _createStreamingMock();

      final client = SseClient(
        baseUrl: 'http://localhost:8000/',
        authType: AuthType.none,
        httpClient: mock.client,
      );

      await client.connect();
      expect(client.isConnected, isTrue);

      client.disconnect();
      expect(client.isConnected, isFalse);

      await mock.controller.close();
    });
  });
}
