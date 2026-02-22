import '/services/secure_credential_service.dart';

class CredentialsManager {
  final SecureCredentialService _credentialService;

  CredentialsManager(this._credentialService);

  Future<void> storePassword(String url, String password) async {
    await _credentialService.storePassword(url, password);
  }

  Future<String?> getPassword(String url) async {
    return await _credentialService.getPassword(url);
  }

  Future<void> clearCredentials(String url) async {
    await _credentialService.clearCredentials(url);
  }

  Future<void> storeEnginePassword(
    String engineBaseUrl,
    String password,
  ) async {
    await _credentialService.storePassword('engine:$engineBaseUrl', password);
  }

  Future<String?> getEnginePassword(String engineBaseUrl) async {
    return await _credentialService.getPassword('engine:$engineBaseUrl');
  }

  Future<void> clearEngineCredentials(String engineBaseUrl) async {
    await _credentialService.clearCredentials('engine:$engineBaseUrl');
  }

  Future<void> storeEngineApiKey(String engineBaseUrl, String apiKey) async {
    await _credentialService.storeApiKey('engine:$engineBaseUrl', apiKey);
  }

  Future<String?> getEngineApiKey(String engineBaseUrl) async {
    return await _credentialService.getApiKey('engine:$engineBaseUrl');
  }

  Future<void> clearEngineApiKey(String engineBaseUrl) async {
    await _credentialService.clearApiKey('engine:$engineBaseUrl');
  }

  Future<void> storeChatApiKey(String chatUrl, String apiKey) async {
    await _credentialService.storeApiKey('chat:$chatUrl', apiKey);
  }

  Future<String?> getChatApiKey(String chatUrl) async {
    return await _credentialService.getApiKey('chat:$chatUrl');
  }

  Future<void> clearChatApiKey(String chatUrl) async {
    await _credentialService.clearApiKey('chat:$chatUrl');
  }
}
