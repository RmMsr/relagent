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
    final jsonString = _prefs.getString(_settingsKey);
    if (jsonString != null) {
      try {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        state = Settings.fromJson(json);
      } catch (e) {
        // If loading fails, keep defaults
        debugPrint('Failed to load settings: $e');
      }
    }
  }

  Future<void> updateSimpleChatBaseUrl(String url) async {
    state = state.copyWith(simpleChatBaseUrl: url);
    await _saveSettings();
  }

  Future<void> updateSimpleChatModel(String model) async {
    state = state.copyWith(simpleChatModel: model);
    await _saveSettings();
  }

  Future<void> updateSettings({
    String? simpleChatBaseUrl,
    String? simpleChatModel,
  }) async {
    state = state.copyWith(
      simpleChatBaseUrl: simpleChatBaseUrl,
      simpleChatModel: simpleChatModel,
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
