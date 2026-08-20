import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_detection.dart';
import 'auth_type.dart';
import 'logger.dart';

String _normalizeBaseUrl(String baseUrl) {
  var url = baseUrl.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

enum EngineHealthStatus {
  success,
  authRequired,
  authFailed,
  connectionFailed,
  timeout,
  invalidEndpoint,
}

class EngineHealthResult {
  final EngineHealthStatus status;
  final String message;
  final int? httpStatusCode;
  final DateTime timestamp;
  final String? engineName;
  final String? engineVersion;
  final AuthType? detectedAuthType;

  EngineHealthResult({
    required this.status,
    required this.message,
    this.httpStatusCode,
    this.engineName,
    this.engineVersion,
    this.detectedAuthType,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory EngineHealthResult.success({
    int? httpStatusCode,
    String? engineName,
    String? engineVersion,
  }) {
    return EngineHealthResult(
      status: EngineHealthStatus.success,
      message: 'Engine connection successful',
      httpStatusCode: httpStatusCode,
      engineName: engineName,
      engineVersion: engineVersion,
    );
  }

  factory EngineHealthResult.authRequired({
    int? httpStatusCode,
    AuthType? detectedAuthType,
  }) {
    final detail = switch (detectedAuthType) {
      AuthType.apiKey => 'API key required or invalid (X-API-Key header)',
      AuthType.basic => 'Basic Auth required',
      _ => 'credentials required',
    };
    return EngineHealthResult(
      status: EngineHealthStatus.authRequired,
      message: 'Engine requires authentication: $detail',
      httpStatusCode: httpStatusCode,
      detectedAuthType: detectedAuthType,
    );
  }

  factory EngineHealthResult.authFailed({int? httpStatusCode}) {
    return EngineHealthResult(
      status: EngineHealthStatus.authFailed,
      message: 'Engine authentication failed',
      httpStatusCode: httpStatusCode,
    );
  }

  factory EngineHealthResult.connectionFailed(String error) {
    return EngineHealthResult(
      status: EngineHealthStatus.connectionFailed,
      message: 'Connection failed: $error',
    );
  }

  factory EngineHealthResult.timeout() {
    return EngineHealthResult(
      status: EngineHealthStatus.timeout,
      message: 'Connection timeout - check engine URL',
    );
  }

  factory EngineHealthResult.invalidEndpoint({int? httpStatusCode}) {
    return EngineHealthResult(
      status: EngineHealthStatus.invalidEndpoint,
      message: 'Engine endpoint not found',
      httpStatusCode: httpStatusCode,
    );
  }

  bool get isSuccess => status == EngineHealthStatus.success;
  bool get requiresAuth => status == EngineHealthStatus.authRequired;
}

class EngineHealthCheckService {
  static const Duration _defaultTimeout = Duration(seconds: 10);

  Future<EngineHealthResult> checkStatus({
    required String baseUrl,
    AuthType authType = AuthType.none,
    String? username,
    String? password,
    String? apiKey,
    Duration timeout = _defaultTimeout,
  }) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final uri = Uri.parse('$normalizedUrl/api/v1/status');

    final headers = <String, String>{
      'content-type': 'application/json',
      'accept': 'application/json',
    };

    if (authType == AuthType.basic && username != null && password != null) {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      headers['authorization'] = 'Basic $credentials';
    }

    if (apiKey != null) {
      headers['x-api-key'] = apiKey;
    }

    Logger.debug('Engine health check: GET $uri');

    http.Response response;
    try {
      response = await http.get(uri, headers: headers).timeout(timeout);
    } on http.ClientException catch (e) {
      Logger.debug('Engine health check error: $e');
      return EngineHealthResult.connectionFailed(e.toString());
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        Logger.debug('Engine health check timeout');
        return EngineHealthResult.timeout();
      }
      Logger.debug('Engine health check error: $e');
      return EngineHealthResult.connectionFailed(e.toString());
    }

    Logger.debug('Engine health check response: HTTP ${response.statusCode}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      String? engineName;
      String? engineVersion;
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        engineName = json['service_name'] as String?;
        engineVersion = json['version'] as String?;
      } catch (_) {
        // Ignore parse errors, version info is optional
      }
      return EngineHealthResult.success(
        httpStatusCode: response.statusCode,
        engineName: engineName,
        engineVersion: engineVersion,
      );
    }

    if (response.statusCode == 401) {
      final detection = detectAuthType(response);
      if (detection.authType == AuthType.basic ||
          detection.authType == AuthType.apiKey) {
        return EngineHealthResult.authRequired(
          httpStatusCode: response.statusCode,
          detectedAuthType: detection.authType,
        );
      }
      return EngineHealthResult.authFailed(httpStatusCode: response.statusCode);
    }

    if (response.statusCode == 403) {
      return EngineHealthResult.authFailed(httpStatusCode: response.statusCode);
    }

    if (response.statusCode == 404) {
      return EngineHealthResult.invalidEndpoint(
        httpStatusCode: response.statusCode,
      );
    }

    return EngineHealthResult.connectionFailed('HTTP ${response.statusCode}');
  }
}
