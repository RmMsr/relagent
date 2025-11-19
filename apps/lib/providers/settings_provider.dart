import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/settings.dart';

const _settingsKey = 'user_settings';

/// Provider for accessing SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main.dart');
});

/// Settings provider that persists to SharedPreferences
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, Settings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

class SettingsNotifier extends StateNotifier<Settings> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(Settings.defaults()) {
    _loadSettings();
  }

  void _loadSettings() {
    final jsonString = _prefs.getString(_settingsKey);
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        state = Settings.fromJson(json);
      } catch (e) {
        // If loading fails, keep defaults
        print('Failed to load settings: $e');
      }
    }
  }

  Future<void> updateChatBaseUrl(String url) async {
    state = state.copyWith(chatBaseUrl: url);
    await _saveSettings();
  }

  Future<void> updateChatModel(String model) async {
    state = state.copyWith(chatModel: model);
    await _saveSettings();
  }

  Future<void> updateSettings({String? chatBaseUrl, String? chatModel}) async {
    state = state.copyWith(
      chatBaseUrl: chatBaseUrl,
      chatModel: chatModel,
    );
    await _saveSettings();
  }

  Future<void> _saveSettings() async {
    final jsonString = jsonEncode(state.toJson());
    await _prefs.setString(_settingsKey, jsonString);
  }

  Future<void> resetToDefaults() async {
    state = Settings.defaults();
    await _saveSettings();
  }
}
