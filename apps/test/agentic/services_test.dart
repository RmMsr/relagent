import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relagent/agentic/models.dart';
import 'package:relagent/agentic/services.dart';

void main() {
  final uri = Uri.parse('http://engine.test/api/v1/sessions/s-1/messages');

  group('tryParseConflict', () {
    test('maps session_in_flight to SessionInFlightException with fields', () {
      final body = jsonEncode({
        'detail': {
          'error': 'session_in_flight',
          'session_id': 's-1',
          'trailing_message_id': 'some-uuid-here',
        },
      });

      final result = tryParseConflict(body, uri);

      expect(result, isA<SessionInFlightException>());
      final ex = result as SessionInFlightException;
      expect(ex.sessionId, 's-1');
      expect(ex.trailingMessageId, 'some-uuid-here');
      expect(ex.url, uri.toString());
      expect(ex.technicalDetails, body);
    });

    test('session_in_flight without trailing_message_id keeps null', () {
      final body = jsonEncode({
        'detail': {
          'error': 'session_in_flight',
          'session_id': 's-2',
        },
      });

      final ex = tryParseConflict(body, uri) as SessionInFlightException;

      expect(ex.sessionId, 's-2');
      expect(ex.trailingMessageId, isNull);
    });

    test('maps no_in_flight_cycle to NoInFlightCycleException with fields', () {
      final body = jsonEncode({
        'detail': {
          'error': 'no_in_flight_cycle',
          'session_id': 's-3',
        },
      });

      final result = tryParseConflict(body, uri);

      expect(result, isA<NoInFlightCycleException>());
      final ex = result as NoInFlightCycleException;
      expect(ex.sessionId, 's-3');
      expect(ex.url, uri.toString());
      expect(ex.technicalDetails, body);
    });

    test('returns null for unknown error discriminator', () {
      final body = jsonEncode({
        'detail': {'error': 'something_else', 'session_id': 's-4'},
      });

      expect(tryParseConflict(body, uri), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(tryParseConflict('not-json', uri), isNull);
    });

    test('returns null when detail is missing or wrong shape', () {
      expect(tryParseConflict(jsonEncode({}), uri), isNull);
      expect(
        tryParseConflict(jsonEncode({'detail': 'plain string'}), uri),
        isNull,
      );
    });

    test('falls back to empty session_id when absent', () {
      final body = jsonEncode({
        'detail': {'error': 'no_in_flight_cycle'},
      });

      final ex = tryParseConflict(body, uri) as NoInFlightCycleException;

      expect(ex.sessionId, '');
    });

    test('maps provider_unavailable to ProviderUnavailableException', () {
      final body = jsonEncode({
        'detail': {
          'error': 'provider_unavailable',
          'reason': 'Inference provider returned HTTP 503',
        },
      });

      final result = tryParseConflict(body, uri);

      expect(result, isA<ProviderUnavailableException>());
      final ex = result as ProviderUnavailableException;
      expect(ex.technicalDetails, 'Inference provider returned HTTP 503');
      expect(ex.userMessage.toLowerCase(), contains('retry'));
      expect(ex.url, uri.toString());
    });

    test('provider_unavailable without reason keeps a non-empty detail', () {
      final body = jsonEncode({
        'detail': {'error': 'provider_unavailable'},
      });

      final ex = tryParseConflict(body, uri) as ProviderUnavailableException;

      expect(ex.technicalDetails, isNotEmpty);
    });
  });

  group('sendAgenticMessage provider availability', () {
    test('maps 503 provider_unavailable body to ProviderUnavailableException',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': {
              'error': 'provider_unavailable',
              'reason': 'Inference provider returned HTTP 503',
            },
          }),
          503,
        );
      });

      expect(
        () => sendAgenticMessage(
          baseUrl: 'http://engine.test',
          content: 'hi',
          client: mockClient,
        ),
        throwsA(isA<ProviderUnavailableException>()),
      );
    });

    test('maps bare 503 (no structured body) to ProviderUnavailableException',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('Service Unavailable', 503);
      });

      expect(
        () => sendAgenticMessage(
          baseUrl: 'http://engine.test',
          content: 'hi',
          client: mockClient,
        ),
        throwsA(isA<ProviderUnavailableException>()),
      );
    });
  });

  group('getMessageHistory', () {
    test('parses sensitivity_level from response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 's-1',
            'messages': [
              {
                'message_id': 'm1',
                'role': 'assistant',
                'timestamp': '2025-01-01T00:00:00Z',
                'content': 'Hello',
                'final': true,
              },
            ],
            'sensitivity_level': 4,
          }),
          200,
        );
      });

      final result = await getMessageHistory(
        baseUrl: 'http://engine.test',
        sessionId: 's-1',
        client: mockClient,
      );

      expect(result.messages.length, 1);
      expect(result.messages[0].text, 'Hello');
      expect(result.sensitivityLevel, SensitivityLevel.confidential);
    });

    test('sensitivity_level is null when absent from response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'session_id': 's-1',
            'messages': [
              {
                'message_id': 'm1',
                'role': 'assistant',
                'timestamp': '2025-01-01T00:00:00Z',
                'content': 'Hello',
                'final': true,
              },
            ],
          }),
          200,
        );
      });

      final result = await getMessageHistory(
        baseUrl: 'http://engine.test',
        sessionId: 's-1',
        client: mockClient,
      );

      expect(result.messages.length, 1);
      expect(result.messages[0].text, 'Hello');
      expect(result.sensitivityLevel, isNull);
    });
  });
}
