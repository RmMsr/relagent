import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/settings.dart';

const _settingsKey = 'user_settings';
const _historyKey = 'settings_history';
const _maxHistoryEntries = 5;

/// Provider for accessing SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Settings provider that persists to SharedPreferences
final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<Settings> {
  late final SharedPreferences _prefs;
  List<SettingsHistoryEntry> _history = [];

  List<SettingsHistoryEntry> get history => _history;

  @override
  Settings build() {
    _prefs = ref.watch(sharedPreferencesProvider);

    // Try to load settings, fall back to defaults if loading fails
    Settings loadedSettings = _loadSettings();
    _loadHistory();

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

  void _loadHistory() {
    try {
      final jsonString = _prefs.getString(_historyKey);
      if (jsonString != null) {
        debugPrint('Loading settings history from SharedPreferences...');
        final jsonList = jsonDecode(jsonString) as List<dynamic>;
        _history = jsonList
            .map(
              (item) =>
                  SettingsHistoryEntry.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        debugPrint(
          'Settings history loaded successfully: ${_history.length} entries',
        );
      } else {
        debugPrint('No saved settings history found');
        _history = [];
      }
    } catch (e, stackTrace) {
      // If loading fails, start with empty history
      debugPrint('Failed to load settings history: $e');
      debugPrint('Stack trace: $stackTrace');
      _history = [];
    }
  }

  Future<bool> updateSimpleChatBaseUrl(String url) async {
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

  Future<bool> updateSettings({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
    String? primeMessage,
    int? ttsSpeakerId,
    double? ttsSpeed,
    VoiceMode? voiceMode,
  }) async {
    state = state.copyWith(
      simpleChatBaseUrl: simpleChatBaseUrl,
      simpleChatModel: simpleChatModel,
      primeMessage: primeMessage,
      ttsSpeakerId: ttsSpeakerId,
      ttsSpeed: ttsSpeed,
      voiceMode: voiceMode,
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

  Future<bool> _saveHistory() async {
    try {
      debugPrint('Saving settings history to SharedPreferences...');
      final jsonList = _history.map((entry) => entry.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      final success = await _prefs.setString(_historyKey, jsonString);

      if (success) {
        debugPrint(
          'Settings history saved successfully: ${_history.length} entries',
        );
      } else {
        debugPrint('ERROR: Failed to save settings history');
        return false;
      }

      return success;
    } catch (e, stackTrace) {
      debugPrint('ERROR: Failed to save settings history: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  void _addToHistory(String url, String model) {
    final newEntry = SettingsHistoryEntry(url: url, model: model);

    // Remove existing entry if it exists (deduplication)
    _history.removeWhere((entry) => entry == newEntry);

    // Add to the beginning of the list
    _history.insert(0, newEntry);

    // Enforce 5-entry limit
    if (_history.length > _maxHistoryEntries) {
      _history = _history.sublist(0, _maxHistoryEntries);
    }

    // Save to persistence
    _saveHistory();
  }

  Future<bool> resetToDefaults() async {
    state = Settings.defaults();
    return await _saveSettings();
  }
}
