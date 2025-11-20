import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/settings.dart';

const _settingsKey = 'user_settings';

/// Provider for accessing SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Settings provider that persists to SharedPreferences
final settingsProvider = StateNotifierProvider<SettingsNotifier, Settings>((
  ref,
) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

class SettingsNotifier extends StateNotifier<Settings> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(Settings.defaults()) {
    _loadSettings();
  }

  void _loadSettings() {
    try {
      final jsonString = _prefs.getString(_settingsKey);
      if (jsonString != null) {
        debugPrint('Loading settings from SharedPreferences...');
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        state = Settings.fromJson(json);
        debugPrint('Settings loaded successfully: ${state.simpleChatBaseUrl}');
      } else {
        debugPrint('No saved settings found, using defaults');
      }
    } catch (e, stackTrace) {
      // If loading fails, keep defaults
      debugPrint('Failed to load settings: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<bool> updateSimpleChatBaseUrl(String url) async {
    state = state.copyWith(simpleChatBaseUrl: url);
    return await _saveSettings();
  }

  Future<bool> updateSimpleChatModel(String model) async {
    state = state.copyWith(simpleChatModel: model);
    return await _saveSettings();
  }

  Future<bool> updateSettings({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
  }) async {
    state = state.copyWith(
      simpleChatBaseUrl: simpleChatBaseUrl,
      simpleChatModel: simpleChatModel,
    );
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
          debugPrint('WARNING: Save verification failed - data may not be persisted');
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

  Future<bool> resetToDefaults() async {
    state = Settings.defaults();
    return await _saveSettings();
  }
}
