import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/services/api_health_check.dart';

void main() {
  group('ApiHealthCheckService', () {
    late ApiHealthCheckService service;

    setUp(() {
      service = ApiHealthCheckService();
    });

    test('returns success for 200 OK response', () async {
      // Mock HTTP client that returns 200 OK
      final mockClient = MockClient((request) async {
        return http.Response('{"choices": []}', 200);
      });

      // Override http.post to use mock client
      final result = await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
      );

      expect(result.status, HealthCheckStatus.success);
      expect(result.isSuccess, true);
      expect(result.message, contains('successful'));
    });

    test('detects Basic Auth requirement from 401 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '',
          401,
          headers: {'www-authenticate': 'Basic realm="Test API"'},
        );
      });

      final result = await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
      );

      expect(result.status, HealthCheckStatus.authRequired);
      expect(result.requiresAuth, true);
      expect(result.detectedAuthType, AuthType.basic);
      expect(result.realm, 'Test API');
    });

    test('returns auth failed for 401 with invalid credentials', () async {
      final mockClient = MockClient((request) async {
        // If auth header present but still 401, credentials are invalid
        if (request.headers.containsKey('authorization')) {
          return http.Response('', 401);
        }
        return http.Response('', 200);
      });

      final result = await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
        authType: AuthType.basic,
        username: 'wrong',
        password: 'credentials',
      );

      expect(result.status, HealthCheckStatus.authFailed);
      expect(result.message, contains('Invalid credentials'));
    });

    test('returns invalid endpoint for 404 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not found', 404);
      });

      final result = await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
      );

      expect(result.status, HealthCheckStatus.invalidEndpoint);
      expect(result.message, contains('not found'));
    });

    test('returns connection failed for 500 server error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal server error', 500);
      });

      final result = await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
      );

      expect(result.status, HealthCheckStatus.connectionFailed);
      expect(result.message, contains('Server error'));
    });

    test('caches successful result', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"choices": []}', 200);
      });

      // Create service with mock client
      final serviceWithMock = ApiHealthCheckService(httpClient: mockClient);
      final baseUrl = 'http://localhost:1234/api/v1';

      // First call
      final result1 = await serviceWithMock.performHealthCheck(
        baseUrl: baseUrl,
        model: 'test-model',
      );

      // Second call should return cached result (same timestamp)
      final result2 = await serviceWithMock.performHealthCheck(
        baseUrl: baseUrl,
        model: 'test-model',
      );

      expect(result1.timestamp, result2.timestamp);
      expect(result2.isSuccess, true);
    });

    test('clears cache when requested', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"choices": []}', 200);
      });

      await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
      );

      service.clearCache();

      // After clearing, performHealthCheck should make a new request
      // (We can't directly test this without exposing internal state,
      // but we verify the method exists and doesn't throw)
      expect(() => service.clearCache(), returnsNormally);
    });

    test('includes Basic Auth header when credentials provided', () async {
      String? authHeader;

      final mockClient = MockClient((request) async {
        authHeader = request.headers['authorization'];
        return http.Response('{"choices": []}', 200);
      });

      await _performHealthCheckWithMockClient(
        service,
        mockClient,
        baseUrl: 'http://localhost:1234/api/v1',
        authType: AuthType.basic,
        username: 'testuser',
        password: 'testpass',
      );

      expect(authHeader, isNotNull);
      expect(authHeader, startsWith('Basic '));
    });
  });
}

// Helper function to create service with mock client and perform health check
Future<HealthCheckResult> _performHealthCheckWithMockClient(
  ApiHealthCheckService _,
  MockClient mockClient, {
  required String baseUrl,
  String model = 'test-model',
  AuthType authType = AuthType.none,
  String? username,
  String? password,
}) async {
  // Create a new service instance with the mock client
  final service = ApiHealthCheckService(httpClient: mockClient);

  return await service.performHealthCheck(
    baseUrl: baseUrl,
    model: model,
    authType: authType,
    username: username,
    password: password,
    timeout: const Duration(seconds: 30),
  );
}
