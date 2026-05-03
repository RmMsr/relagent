import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/services.dart';

void main() {
  final uri = Uri.parse('http://engine.test/api/v1/sessions/s-1/messages');

  group('tryParseConflict', () {
    test('maps session_in_flight to SessionInFlightException with fields', () {
      final body = jsonEncode({
        'detail': {
          'error': 'session_in_flight',
          'session_id': 's-1',
          'trailing_sequence_id': 42,
        },
      });

      final result = tryParseConflict(body, uri);

      expect(result, isA<SessionInFlightException>());
      final ex = result as SessionInFlightException;
      expect(ex.sessionId, 's-1');
      expect(ex.trailingSequenceId, 42);
      expect(ex.url, uri.toString());
      expect(ex.technicalDetails, body);
    });

    test('session_in_flight without trailing_sequence_id keeps null', () {
      final body = jsonEncode({
        'detail': {
          'error': 'session_in_flight',
          'session_id': 's-2',
        },
      });

      final ex = tryParseConflict(body, uri) as SessionInFlightException;

      expect(ex.sessionId, 's-2');
      expect(ex.trailingSequenceId, isNull);
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
  });
}
