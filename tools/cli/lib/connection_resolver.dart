import 'dart:io';

import 'package:agentic_client/agentic_client.dart';

import 'settings_store.dart';
import 'token_store.dart';

class ResolvedConnection {
  final String engineUrl;
  final String? token;

  const ResolvedConnection({required this.engineUrl, this.token});

  AuthType get authType => token != null ? AuthType.apiKey : AuthType.none;
}

/// Resolves the engine URL and auth token in precedence order: an explicit
/// flag, then an environment variable, then a persisted value, then a
/// default. See the cli-config spec's "Configuration Resolution
/// Precedence" requirement.
class ConnectionResolver {
  final SettingsStore settingsStore;
  final TokenStore tokenStore;
  final Map<String, String> environment;

  ConnectionResolver({
    SettingsStore? settingsStore,
    TokenStore? tokenStore,
    Map<String, String>? environment,
  }) : settingsStore = settingsStore ?? SettingsStore(),
       tokenStore = tokenStore ?? SecretServiceTokenStore(),
       environment = environment ?? Platform.environment;

  Future<ResolvedConnection> resolve({
    String? flagUrl,
    String? flagToken,
  }) async {
    final url =
        flagUrl ??
        environment['ENGINE_URL'] ??
        settingsStore.readEngineUrl() ??
        defaultEngineBaseUrl;

    final token =
        flagToken ??
        environment['ENGINE_TOKEN'] ??
        await tokenStore.readToken();

    return ResolvedConnection(engineUrl: url, token: token);
  }
}
