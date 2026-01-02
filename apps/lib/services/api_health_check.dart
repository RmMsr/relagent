import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:relagent/chat/auth_detection.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/utils/logger.dart';

/// Result of API health check
class HealthCheckResult {
  final HealthCheckStatus status;
  final String message;
  final AuthType? detectedAuthType;
  final String? realm;
  final String? loginUrl;
  final DateTime timestamp;
  final int? httpStatusCode;

  HealthCheckResult({
    required this.status,
    required this.message,
    this.detectedAuthType,
    this.realm,
    this.loginUrl,
    this.httpStatusCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory HealthCheckResult.success({int? httpStatusCode}) {
    return HealthCheckResult(
      status: HealthCheckStatus.success,
      message: 'API connection successful',
      httpStatusCode: httpStatusCode,
    );
  }

  factory HealthCheckResult.authRequired({
    required AuthType authType,
    String? realm,
    String? loginUrl,
    int? httpStatusCode,
  }) {
    String message;
    if (authType == AuthType.basic) {
      message = 'Authentication required: HTTP Basic Auth';
      if (realm != null) message += ' (Realm: $realm)';
    } else {
      message = 'Authentication required';
    }

    return HealthCheckResult(
      status: HealthCheckStatus.authRequired,
      message: message,
      detectedAuthType: authType,
      realm: realm,
      loginUrl: loginUrl,
      httpStatusCode: httpStatusCode,
    );
  }

  factory HealthCheckResult.authFailed(String details, {int? httpStatusCode}) {
    return HealthCheckResult(
      status: HealthCheckStatus.authFailed,
      message: 'Authentication failed: $details',
      httpStatusCode: httpStatusCode,
    );
  }

  factory HealthCheckResult.connectionFailed(String error) {
    return HealthCheckResult(
      status: HealthCheckStatus.connectionFailed,
      message: 'Connection failed: $error',
    );
  }

  factory HealthCheckResult.timeout() {
    return HealthCheckResult(
      status: HealthCheckStatus.timeout,
      message: 'Connection timeout - check your network and API URL',
    );
  }

  factory HealthCheckResult.invalidEndpoint(String details, {int? httpStatusCode}) {
    return HealthCheckResult(
      status: HealthCheckStatus.invalidEndpoint,
      message: 'Invalid endpoint: $details',
      httpStatusCode: httpStatusCode,
    );
  }

  bool get isSuccess => status == HealthCheckStatus.success;
  bool get requiresAuth => status == HealthCheckStatus.authRequired;
  bool get hasFailed =>
      status == HealthCheckStatus.connectionFailed ||
      status == HealthCheckStatus.timeout ||
      status == HealthCheckStatus.invalidEndpoint;
}

enum HealthCheckStatus {
  success,
  authRequired,
  authFailed,
  connectionFailed,
  timeout,
  invalidEndpoint,
}

/// Service for checking API health and connectivity
class ApiHealthCheckService {
  static const Duration _defaultTimeout = Duration(seconds: 30);
  HealthCheckResult? _cachedResult;
  String? _cachedUrl;
  final http.Client? _httpClient;

  ApiHealthCheckService({http.Client? httpClient}) : _httpClient = httpClient;

  /// Perform health check on API endpoint
  ///
  /// Makes a minimal request to /chat/completions to validate:
  /// - Network connectivity
  /// - Endpoint validity
  /// - Authentication requirements
  /// - API availability
  Future<HealthCheckResult> performHealthCheck({
    required String baseUrl,
    required String model,
    AuthType authType = AuthType.none,
    String? username,
    String? password,
    Duration timeout = _defaultTimeout,
  }) async {
    // Return cached result if URL hasn't changed
    if (_cachedResult != null && _cachedUrl == baseUrl) {
      final age = DateTime.now().difference(_cachedResult!.timestamp);
      if (age.inMinutes < 5) {
        return _cachedResult!;
      }
    }

    final uri = Uri.parse('$baseUrl/chat/completions');

    // Build minimal request body (match actual chat request format)
    final body = {
      'messages': [
        {'role': 'user', 'content': 'test'}
      ],
      'model': model,
      'max_completion_tokens': 100,
    };

    // Build headers with authentication
    final headers = <String, String>{'content-type': 'application/json'};

    if (authType == AuthType.basic && username != null && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      headers['authorization'] = 'Basic $credentials';
    }

    // Log request details
    Logger.info('Health check request: POST $uri');
    Logger.info('Request body: ${jsonEncode(body)}');
    Logger.info('Auth type: ${authType.name}');

    http.Response response;
    try {
      if (_httpClient != null) {
        response = await _httpClient
            .post(
              uri,
              body: jsonEncode(body),
              headers: headers,
            )
            .timeout(timeout);
      } else {
        response = await http
            .post(
              uri,
              body: jsonEncode(body),
              headers: headers,
            )
            .timeout(timeout);
      }

      // Log response details
      Logger.info('Health check response: HTTP ${response.statusCode}');
      Logger.info('Response body: ${response.body}');
      Logger.info('Response headers: ${response.headers}');
    } on http.ClientException catch (e) {
      Logger.error('Health check HTTP client error: $e');
      final result = HealthCheckResult.connectionFailed(e.toString());
      _cacheResult(baseUrl, result);
      return result;
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        Logger.error('Health check timeout after ${timeout.inSeconds}s');
        final result = HealthCheckResult.timeout();
        _cacheResult(baseUrl, result);
        return result;
      }

      Logger.error('Health check error: $e');
      final result = HealthCheckResult.connectionFailed(e.toString());
      _cacheResult(baseUrl, result);
      return result;
    }

    // Check response status
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success - API is reachable and authentication worked
      final result = HealthCheckResult.success(
        httpStatusCode: response.statusCode,
      );
      _cacheResult(baseUrl, result);
      return result;
    }

    // Detect authentication requirements from redirects or auth errors
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 302 ||
        response.statusCode == 307) {
      final authDetection = detectAuthType(response);

      if (!authDetection.isSuccess) {
        // Unsupported auth type
        final result = HealthCheckResult.authFailed(
          authDetection.errorMessage ?? 'Unknown auth error',
          httpStatusCode: response.statusCode,
        );
        _cacheResult(baseUrl, result);
        return result;
      }

      if (authDetection.authType == AuthType.none) {
        // Auth failed but no specific type detected
        final result = HealthCheckResult.authFailed(
          'Invalid credentials or access denied',
          httpStatusCode: response.statusCode,
        );
        _cacheResult(baseUrl, result);
        return result;
      }

      // Auth required
      final result = HealthCheckResult.authRequired(
        authType: authDetection.authType,
        realm: authDetection.realm,
        httpStatusCode: response.statusCode,
      );
      _cacheResult(baseUrl, result);
      return result;
    }

    // Handle other errors
    if (response.statusCode == 404) {
      final result = HealthCheckResult.invalidEndpoint(
        'Endpoint not found - check your API URL',
        httpStatusCode: response.statusCode,
      );
      _cacheResult(baseUrl, result);
      return result;
    }

    if (response.statusCode >= 500) {
      final result = HealthCheckResult.connectionFailed(
        'Server error (HTTP ${response.statusCode})',
      );
      _cacheResult(baseUrl, result);
      return result;
    }

    // Unexpected status code
    final result = HealthCheckResult.connectionFailed(
      'Unexpected response (HTTP ${response.statusCode})',
    );
    _cacheResult(baseUrl, result);
    return result;
  }

  void _cacheResult(String url, HealthCheckResult result) {
    _cachedUrl = url;
    _cachedResult = result;
  }

  /// Clear cached health check result
  void clearCache() {
    _cachedResult = null;
    _cachedUrl = null;
  }
}
