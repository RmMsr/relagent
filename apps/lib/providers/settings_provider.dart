import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';
import 'chat_provider.dart';
import 'credentials_manager.dart';
import 'displayed_session_provider.dart';
import 'engine_health_check_provider.dart';
import 'model_download_provider.dart';
import '/services/secure_credential_service.dart';
import 'sessions_provider.dart';
import 'settings_history_manager.dart';
import 'settings_persistence_manager.dart';
import '/voice/imported_model_registry.dart';

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

    // Validate selected model IDs against downloaded models once the
    // initial filesystem scan completes, clearing any stale selections.
    ref.listen<ModelDownloadState>(modelDownloadProvider, (previous, next) {
      if ((previous?.isScanning ?? true) && !next.isScanning) {
        _validateModelSelections(next.downloadedModels);
      }
    });

    return _persistenceManager.loadSettings();
  }

  Future<void> _validateModelSelections(Set<String> downloadedModels) async {
    final asrId = state.selectedAsrModelId;
    final ttsId = state.selectedTtsModelId;
    bool changed = false;
    if (asrId != null &&
        !downloadedModels.contains(asrId) &&
        ImportedModelRegistry.findById(asrId) == null) {
      state = state.copyWith(selectedAsrModelId: null);
      changed = true;
    }
    if (ttsId != null &&
        !downloadedModels.contains(ttsId) &&
        ImportedModelRegistry.findById(ttsId) == null) {
      state = state.copyWith(selectedTtsModelId: null);
      changed = true;
    }
    if (changed) {
      await _persistenceManager.saveSettings(state);
    }
  }

  Future<bool> updateSimpleChatBaseUrl(String url) async {
    final urlChanged = url != state.simpleChatBaseUrl;
    if (urlChanged) {
      await _credentialsManager.clearCredentials(state.simpleChatBaseUrl);
      await _credentialsManager.clearChatApiKey(state.simpleChatBaseUrl);
      Future.microtask(
        () => ref.read(chatProvider.notifier).clearChat(),
      );
    }

    state = state.copyWith(
      simpleChatBaseUrl: url,
      simpleChatHasApiKey: urlChanged ? false : state.simpleChatHasApiKey,
    );
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

  Future<bool> updateContinuousVoiceEnabled(bool enabled) async {
    state = state.copyWith(continuousVoiceEnabled: enabled);
    if (!enabled && state.isContinuousRecording) {
      state = state.copyWith(voiceMode: VoiceMode.silent);
    }
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateVoiceMode(VoiceMode mode) async {
    if (!state.continuousVoiceEnabled &&
        (mode == VoiceMode.listening || mode == VoiceMode.conversation)) {
      return false;
    }
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
      // Clear persisted SSE last event ID
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.remove('sse_last_event_id');

      // Restore engine auth from history for the new URL, or reset if unknown
      final match = state.engineUrlHistory.where((e) => e.url == url);
      final entry = match.isNotEmpty ? match.first : null;

      state = state.copyWith(
        engineAuthType: entry?.authType ?? AuthType.none,
        engineUsername: entry?.username,
        agenticSessionId: null,
        engineHasApiKey: entry?.hasApiKey ?? false,
      );

      // Clear runtime state in dependent providers
      ref.read(engineHealthCheckProvider.notifier).clearResult();
      ref.read(sessionsProvider.notifier).clearSessions();
      ref.read(displayedSessionProvider.notifier).show(null);
      // NOT ttsProvider here: it depends on settingsProvider (via
      // ref.listen in its own build()), so settingsProvider reaching back
      // into it — at any timing, deferred or not — trips Riverpod's
      // circular-dependency safety check. It reacts to this same
      // engineBaseUrl change itself instead; see tts_provider.dart.
    }

    state = state.copyWith(engineBaseUrl: url);
    _updateEngineUrlHistory(url);
    return await _persistenceManager.saveSettings(state);
  }

  void _updateEngineUrlHistory(String url) {
    final history = List<EngineUrlEntry>.from(state.engineUrlHistory);
    history.removeWhere((e) => e.url == url);
    history.insert(
      0,
      EngineUrlEntry(
        url: url,
        authType: state.engineAuthType,
        username: state.engineUsername,
        hasApiKey: state.engineHasApiKey,
      ),
    );
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

  Future<String?> getEnginePassword({String? url}) async {
    return await _credentialsManager.getEnginePassword(url ?? state.engineBaseUrl);
  }

  Future<void> clearEngineCredentials() async {
    await _credentialsManager.clearEngineCredentials(state.engineBaseUrl);
    state = state.copyWith(engineAuthType: AuthType.none, engineUsername: null);
    await _persistenceManager.saveSettings(state);
  }

  Future<void> setEngineApiKey(String apiKey) async {
    await _credentialsManager.storeEngineApiKey(state.engineBaseUrl, apiKey);
    state = state.copyWith(engineHasApiKey: true);
    await _persistenceManager.saveSettings(state);
  }

  Future<String?> getEngineApiKey({String? url}) async {
    final targetUrl = url ?? state.engineBaseUrl;
    final key = await _credentialsManager.getEngineApiKey(targetUrl);
    if (key == null && targetUrl == state.engineBaseUrl && state.engineHasApiKey) {
      state = state.copyWith(engineHasApiKey: false);
      await _persistenceManager.saveSettings(state);
    }
    return key;
  }

  Future<void> clearEngineApiKey() async {
    await _credentialsManager.clearEngineApiKey(state.engineBaseUrl);
    state = state.copyWith(engineHasApiKey: false);
    await _persistenceManager.saveSettings(state);
  }

  Future<void> setChatApiKey(String apiKey) async {
    await _credentialsManager.storeChatApiKey(state.simpleChatBaseUrl, apiKey);
    state = state.copyWith(simpleChatHasApiKey: true);
    await _persistenceManager.saveSettings(state);
  }

  Future<String?> getChatApiKey() async {
    final key = await _credentialsManager.getChatApiKey(
      state.simpleChatBaseUrl,
    );
    if (key == null && state.simpleChatHasApiKey) {
      state = state.copyWith(simpleChatHasApiKey: false);
      await _persistenceManager.saveSettings(state);
    }
    return key;
  }

  Future<void> clearChatApiKey() async {
    await _credentialsManager.clearChatApiKey(state.simpleChatBaseUrl);
    state = state.copyWith(simpleChatHasApiKey: false);
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

  Future<bool> updateSelectedAsrModelId(String? modelId) async {
    state = state.copyWith(selectedAsrModelId: modelId);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> updateSelectedTtsModelId(String? modelId) async {
    state = state.copyWith(selectedTtsModelId: modelId);
    return await _persistenceManager.saveSettings(state);
  }

  Future<bool> clearModelSelection(String modelId) async {
    bool changed = false;
    if (state.selectedAsrModelId == modelId) {
      state = state.copyWith(selectedAsrModelId: null);
      changed = true;
    }
    if (state.selectedTtsModelId == modelId) {
      state = state.copyWith(selectedTtsModelId: null);
      changed = true;
    }
    if (changed) {
      return await _persistenceManager.saveSettings(state);
    }
    return true;
  }
}
