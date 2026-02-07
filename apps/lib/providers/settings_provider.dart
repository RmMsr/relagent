import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';
import '/services/secure_credential_service.dart';

const _settingsKey = 'user_settings';
const _maxHistoryEntries = 5;

/// Provider for accessing SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Provider for secure credential storage
final secureCredentialServiceProvider = Provider<SecureCredentialService>((
  ref,
) {
  return SecureCredentialService();
});

/// Settings provider that persists to SharedPreferences
final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<Settings> {
  late final SharedPreferences _prefs;
  late final SecureCredentialService _credentialService;

  @override
  Settings build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    _credentialService = ref.watch(secureCredentialServiceProvider);

    // Try to load settings, fall back to defaults if loading fails
    Settings loadedSettings = _loadSettings();

    return loadedSettings;
  }

  Settings _loadSettings() {
    try {
      final jsonString = _prefs.getString(_settingsKey);
      if (jsonString != null) {
        debugPrint('Loading settings from SharedPreferences...');
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final loadedSettings = Settings.fromJson(json);
        state = loadedSettings;
        debugPrint('Settings loaded successfully: ${state.simpleChatBaseUrl}');
        return loadedSettings;
      } else {
        debugPrint('No saved settings found, using defaults');
        final defaultSettings = Settings.defaults();
        state = defaultSettings;
        return defaultSettings;
      }
    } catch (e, stackTrace) {
      // If loading fails, keep defaults
      debugPrint('Failed to load settings: $e');
      debugPrint('Stack trace: $stackTrace');
      final defaultSettings = Settings.defaults();
      state = defaultSettings;
      return defaultSettings;
    }
  }

  Future<bool> updateSimpleChatBaseUrl(String url) async {
    // Clear credentials when URL changes
    if (url != state.simpleChatBaseUrl) {
      await clearCredentials();
    }

    state = state.copyWith(simpleChatBaseUrl: url);
    _addToHistory(url, state.simpleChatModel);
    return await _saveSettings();
  }

  Future<bool> updateSimpleChatModel(String model) async {
    state = state.copyWith(simpleChatModel: model);
    _addToHistory(state.simpleChatBaseUrl, model);
    return await _saveSettings();
  }

  Future<bool> updateTtsSpeakerId(int speakerId) async {
    state = state.copyWith(ttsSpeakerId: speakerId);
    return await _saveSettings();
  }

  Future<bool> updateTtsSpeed(double speed) async {
    state = state.copyWith(ttsSpeed: speed);
    return await _saveSettings();
  }

  Future<bool> updateVoiceMode(VoiceMode mode) async {
    state = state.copyWith(voiceMode: mode);
    return await _saveSettings();
  }

  Future<bool> updateBackgroundListeningDuration(
    BackgroundListeningDuration duration,
  ) async {
    state = state.copyWith(backgroundListeningDuration: duration);
    return await _saveSettings();
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

    // Add to history if URL or model changed
    final newUrl = simpleChatBaseUrl ?? state.simpleChatBaseUrl;
    final newModel = simpleChatModel ?? state.simpleChatModel;
    if (simpleChatBaseUrl != null || simpleChatModel != null) {
      _addToHistory(newUrl, newModel);
    }

    return await _saveSettings();
  }

  Future<bool> _saveSettings() async {
    try {
      debugPrint('Saving settings to SharedPreferences...');
      final jsonString = jsonEncode(state.toJson());
      final success = await _prefs.setString(_settingsKey, jsonString);

      if (success) {
        debugPrint('Settings saved successfully');
        // Verify the save by reading it back
        final verified = _prefs.getString(_settingsKey);
        if (verified == jsonString) {
          debugPrint('Save verified: data persisted correctly');
        } else {
          debugPrint(
            'WARNING: Save verification failed - data may not be persisted',
          );
          return false;
        }
      } else {
        debugPrint('ERROR: setString returned false - save failed');
        return false;
      }

      return success;
    } catch (e, stackTrace) {
      debugPrint('ERROR: Failed to save settings: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  void _addToHistory(String url, String model) {
    final newEntry = SettingsHistoryEntry(url: url, model: model);

    // Create new history list with deduplication
    final newHistory = List<SettingsHistoryEntry>.from(state.history);

    // Remove existing entry if it exists (deduplication)
    newHistory.removeWhere((SettingsHistoryEntry entry) => entry == newEntry);

    // Add to the beginning of the list
    newHistory.insert(0, newEntry);

    // Enforce 5-entry limit
    final limitedHistory = newHistory.length > _maxHistoryEntries
        ? newHistory.sublist(0, _maxHistoryEntries)
        : newHistory;

    // Update state with new history (will be saved with settings)
    state = state.copyWith(history: limitedHistory);
  }

  Future<bool> resetToDefaults() async {
    state = Settings.defaults();
    return await _saveSettings();
  }

  // Authentication methods

  Future<bool> updateAuthType(AuthType type) async {
    state = state.copyWith(authType: type);
    return await _saveSettings();
  }

  Future<bool> updateUsername(String? username) async {
    state = state.copyWith(username: username);
    return await _saveSettings();
  }

  /// Store password in secure storage (not persisted to SharedPreferences)
  Future<void> setPassword(String password) async {
    await _credentialService.storePassword(state.simpleChatBaseUrl, password);
  }

  /// Retrieve password from secure storage
  Future<String?> getPassword() async {
    return await _credentialService.getPassword(state.simpleChatBaseUrl);
  }

  /// Clear all credentials for current endpoint
  Future<void> clearCredentials() async {
    await _credentialService.clearCredentials(state.simpleChatBaseUrl);
    // Also clear auth type and username from settings
    state = state.copyWith(authType: AuthType.none, username: null);
    await _saveSettings();
  }

  // Engine settings methods

  Future<bool> updateEngineBaseUrl(String url) async {
    // Clear engine credentials when URL changes
    if (url != state.engineBaseUrl) {
      await clearEngineCredentials();
    }

    state = state.copyWith(engineBaseUrl: url);
    return await _saveSettings();
  }

  Future<bool> updateEngineAuthType(AuthType type) async {
    state = state.copyWith(engineAuthType: type);
    return await _saveSettings();
  }

  Future<bool> updateEngineUsername(String? username) async {
    state = state.copyWith(engineUsername: username);
    return await _saveSettings();
  }

  Future<void> setEnginePassword(String password) async {
    await _credentialService.storePassword(
      'engine:${state.engineBaseUrl}',
      password,
    );
  }

  Future<String?> getEnginePassword() async {
    return await _credentialService.getPassword(
      'engine:${state.engineBaseUrl}',
    );
  }

  Future<void> clearEngineCredentials() async {
    await _credentialService.clearCredentials('engine:${state.engineBaseUrl}');
    state = state.copyWith(engineAuthType: AuthType.none, engineUsername: null);
    await _saveSettings();
  }

  // Session management

  Future<bool> setAgenticSessionId(String sessionId) async {
    state = state.copyWith(agenticSessionId: sessionId);
    return await _saveSettings();
  }

  Future<bool> clearAgenticSessionId() async {
    state = state.copyWith(agenticSessionId: null);
    return await _saveSettings();
  }

  // Backend selection

  Future<bool> updateSelectedBackend(ChatBackendType backend) async {
    state = state.copyWith(selectedBackend: backend);
    return await _saveSettings();
  }
}
