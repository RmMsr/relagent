import 'package:agentic_client/agentic_client.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('detectAuthType', () {
    test('detects no authentication for 200 OK', () {
      final response = http.Response('', 200);
      final result = detectAuthType(response);

      expect(result.authType, AuthType.none);
      expect(result.isSuccess, true);
    });

    test('detects Basic Auth from WWW-Authenticate header', () {
      final response = http.Response(
        '',
        401,
        headers: {'www-authenticate': 'Basic realm="My API"'},
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.basic);
      expect(result.realm, 'My API');
      expect(result.isSuccess, true);
    });

    test('detects Basic Auth with case-insensitive header', () {
      final response = http.Response(
        '',
        401,
        headers: {'www-authenticate': 'BASIC realm="Test"'},
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.basic);
      expect(result.realm, 'Test');
    });

    test('returns error for unsupported Bearer authentication', () {
      final response = http.Response(
        '',
        401,
        headers: {'www-authenticate': 'Bearer realm="OAuth"'},
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.none);
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Unsupported'));
      expect(result.errorMessage, contains('Bearer'));
    });

    test('returns error for unsupported Digest authentication', () {
      final response = http.Response(
        '',
        401,
        headers: {
          'www-authenticate': 'Digest realm="Test", qop="auth", nonce="123"',
        },
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.none);
      expect(result.isSuccess, false);
      expect(result.errorMessage, contains('Unsupported'));
    });

    test(
        'detects API key requirement from 401 with JSON content-type and no WWW-Authenticate',
        () {
      final response = http.Response(
        '{"detail": "API key required"}',
        401,
        headers: {'content-type': 'application/json'},
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.apiKey);
      expect(result.isSuccess, true);
    });

    test('detects API key from 401 with JSON content-type including charset',
        () {
      final response = http.Response(
        '{"error": "unauthorized"}',
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final result = detectAuthType(response);

      expect(result.authType, AuthType.apiKey);
      expect(result.isSuccess, true);
    });

    test('prefers WWW-Authenticate over JSON content-type for Basic Auth', () {
      final response = http.Response(
        '{"detail": "unauthorized"}',
        401,
        headers: {
          'www-authenticate': 'Basic realm="Proxy"',
          'content-type': 'application/json',
        },
      );
      final result = detectAuthType(response);

      // WWW-Authenticate takes precedence
      expect(result.authType, AuthType.basic);
      expect(result.realm, 'Proxy');
    });

    test(
        'returns none for 401 without JSON content-type and without WWW-Authenticate',
        () {
      final response = http.Response('Unauthorized', 401, headers: {});
      final result = detectAuthType(response);

      expect(result.authType, AuthType.none);
    });
  });

  group('extractBasicAuthRealm', () {
    test('extracts realm from standard header', () {
      final realm = extractBasicAuthRealm('Basic realm="My API"');
      expect(realm, 'My API');
    });

    test('extracts realm with special characters', () {
      final realm = extractBasicAuthRealm('Basic realm="Test\'s API: v2.0"');
      expect(realm, 'Test\'s API: v2.0');
    });

    test('returns null for header without realm', () {
      final realm = extractBasicAuthRealm('Basic');
      expect(realm, null);
    });

    test('extracts first realm if multiple present', () {
      final realm = extractBasicAuthRealm(
        'Basic realm="First", realm="Second"',
      );
      expect(realm, 'First');
    });
  });
}
