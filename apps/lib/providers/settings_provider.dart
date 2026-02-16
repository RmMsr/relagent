import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';
import 'credentials_manager.dart';
import '/services/secure_credential_service.dart';
import 'settings_history_manager.dart';
import 'settings_persistence_manager.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

final secureCredentialServiceProvider = Provider<SecureCredentialService>((
  ref,
) {
  return SecureCredentialService();
});

final settingsPersistenceManagerProvider = Provider<SettingsPersistenceManager>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return SettingsPersistenceManager(prefs);
  },
);

final settingsHistoryManagerProvider = Provider<SettingsHistoryManager>((ref) {
  return SettingsHistoryManager();
});

final credentialsManagerProvider = Provider<CredentialsManager>((ref) {
  final credentialService = ref.watch(secureCredentialServiceProvider);
  return CredentialsManager(credentialService);
});

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<Settings> {
  late final SettingsPersistenceManager _persistenceManager;
  late final SettingsHistoryManager _historyManager;
  late final CredentialsManager _credentialsManager;

  @override
  Settings build() {
    _persistenceManager = ref.watch(settingsPersistenceManagerProvider);
    _historyManager = ref.watch(settingsHistoryManagerProvider);
    _credentialsManager = ref.watch(credentialsManagerProvider);

    return _persistenceManager.loadSettings();
  }

  Future<bool> updateSimpleChatBaseUrl(String url) async {
    if (url != state.simpleChatBaseUrl) {
      await _credentialsManager.clearCredentials(state.simpleChatBaseUrl);
    }

    state = state.copyWith(simpleChatBaseUrl: url);
    _updateHistory(url, state.simpleChatModel);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateSimpleChatModel(String model) async {
    state = state.copyWith(simpleChatModel: model);
    _updateHistory(state.simpleChatBaseUrl, model);
    return await _persistenceManager.saveSettings(state);
  }

  void _updateHistory(String url, String model) {
    final newHistory = _historyManager.addToHistory(state.history, url, model);
    state = state.copyWith(history: newHistory);
  }

  Future<bool> updateTtsSpeakerId(int speakerId) async {
    state = state.copyWith(ttsSpeakerId: speakerId);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateTtsSpeed(double speed) async {
    state = state.copyWith(ttsSpeed: speed);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateVoiceMode(VoiceMode mode) async {
    state = state.copyWith(voiceMode: mode);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateBackgroundListeningDuration(
    BackgroundListeningDuration duration,
  ) async {
    state = state.copyWith(backgroundListeningDuration: duration);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateSettings({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
    String? primeMessage,
    int? ttsSpeakerId,
    double? ttsSpeed,
    VoiceMode? voiceMode,
    BackgroundListeningDuration? backgroundListeningDuration,
  }) async {
    state = state.copyWith(
      simpleChatBaseUrl: simpleChatBaseUrl,
      simpleChatModel: simpleChatModel,
      primeMessage: primeMessage,
      ttsSpeakerId: ttsSpeakerId,
      ttsSpeed: ttsSpeed,
      voiceMode: voiceMode,
      backgroundListeningDuration: backgroundListeningDuration,
    );

    final newUrl = simpleChatBaseUrl ?? state.simpleChatBaseUrl;
    final newModel = simpleChatModel ?? state.simpleChatModel;
    if (simpleChatBaseUrl != null || simpleChatModel != null) {
      _updateHistory(newUrl, newModel);
    }

    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> resetToDefaults() async {
    state = Settings.defaults();
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateAuthType(AuthType type) async {
    state = state.copyWith(authType: type);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateUsername(String? username) async {
    state = state.copyWith(username: username);
    return await _persistenceManager.saveSettings(state);
  }

  Future<void> setPassword(String password) async {
    await _credentialsManager.storePassword(state.simpleChatBaseUrl, password);
  }

  Future<String?> getPassword() async {
    return await _credentialsManager.getPassword(state.simpleChatBaseUrl);
  }

  Future<void> clearCredentials() async {
    await _credentialsManager.clearCredentials(state.simpleChatBaseUrl);
    state = state.copyWith(authType: AuthType.none, username: null);
    await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateEngineBaseUrl(String url) async {
    if (url != state.engineBaseUrl) {
      await clearEngineCredentials();
    }

    state = state.copyWith(engineBaseUrl: url);
    _updateEngineUrlHistory(url);
    return await _persistenceManager.saveSettings(state);
  }

  void _updateEngineUrlHistory(String url) {
    final history = List<String>.from(state.engineUrlHistory);
    history.remove(url);
    history.insert(0, url);
    if (history.length > 5) {
      history.removeRange(5, history.length);
    }
    state = state.copyWith(engineUrlHistory: history);
  }

  Future<bool> updateEngineAuthType(AuthType type) async {
    state = state.copyWith(engineAuthType: type);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateEngineUsername(String? username) async {
    state = state.copyWith(engineUsername: username);
    return await _persistenceManager.saveSettings(state);
  }

  Future<void> setEnginePassword(String password) async {
    await _credentialsManager.storeEnginePassword(
      state.engineBaseUrl,
      password,
    );
  }

  Future<String?> getEnginePassword() async {
    return await _credentialsManager.getEnginePassword(state.engineBaseUrl);
  }

  Future<void> clearEngineCredentials() async {
    await _credentialsManager.clearEngineCredentials(state.engineBaseUrl);
    state = state.copyWith(engineAuthType: AuthType.none, engineUsername: null);
    await _persistenceManager.saveSettings(state);
  }

  Future<bool> setAgenticSessionId(String sessionId) async {
    state = state.copyWith(agenticSessionId: sessionId);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> clearAgenticSessionId() async {
    state = state.copyWith(agenticSessionId: null);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateSelectedBackend(ChatBackendType backend) async {
    state = state.copyWith(selectedBackend: backend);
    return await _persistenceManager.saveSettings(state);
  }
}
