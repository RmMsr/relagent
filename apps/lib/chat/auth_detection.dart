import 'package:http/http.dart' as http;
import 'package:relagent/models/settings.dart';

/// Result of authentication type detection
class AuthDetectionResult {
  final AuthType authType;
  final String? realm; // For Basic Auth
  final String? errorMessage;

  const AuthDetectionResult({
    required this.authType,
    this.realm,
    this.errorMessage,
  });

  bool get isSuccess => errorMessage == null;
}

/// Detect authentication type from HTTP response
///
/// Analyzes response status code, headers, and content to determine
/// what type of authentication is required (if any).
AuthDetectionResult detectAuthType(http.Response response) {
  // Success - no authentication required
  if (response.statusCode >= 200 && response.statusCode < 300) {
    return const AuthDetectionResult(authType: AuthType.none);
  }

  // 401 Unauthorized - check for authentication scheme
  if (response.statusCode == 401) {
    final wwwAuth = response.headers['www-authenticate'];
    if (wwwAuth != null) {
      // Check for Basic authentication
      if (wwwAuth.toLowerCase().startsWith('basic')) {
        final realm = extractBasicAuthRealm(wwwAuth);
        return AuthDetectionResult(
          authType: AuthType.basic,
          realm: realm,
        );
      }

      // Unsupported authentication schemes
      if (wwwAuth.toLowerCase().contains('bearer') ||
          wwwAuth.toLowerCase().contains('digest') ||
          wwwAuth.toLowerCase().contains('oauth')) {
        return AuthDetectionResult(
          authType: AuthType.none,
          errorMessage: 'Unsupported authentication scheme: $wwwAuth',
        );
      }
    }
  }

  // Default: no authentication or unknown scheme
  return const AuthDetectionResult(authType: AuthType.none);
}

/// Extract realm from WWW-Authenticate Basic header
///
/// Example: "Basic realm=\"My API\"" -> "My API"
String? extractBasicAuthRealm(String wwwAuthHeader) {
  final realmMatch = RegExp(r'realm="([^"]*)"').firstMatch(wwwAuthHeader);
  return realmMatch?.group(1);
}
