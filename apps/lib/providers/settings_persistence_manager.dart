import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';

const _settingsKey = 'user_settings';

class SettingsPersistenceManager {
  final SharedPreferences _prefs;

  SettingsPersistenceManager(this._prefs);

  Settings loadSettings() {
    try {
      final jsonString = _prefs.getString(_settingsKey);
      if (jsonString != null) {
        debugPrint('Loading settings from SharedPreferences...');
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final loadedSettings = Settings.fromJson(json);
        debugPrint(
          'Settings loaded successfully: ${loadedSettings.simpleChatBaseUrl}',
        );
        return loadedSettings;
      } else {
        debugPrint('No saved settings found, using defaults');
        return Settings.defaults();
      }
    } catch (e, stackTrace) {
      debugPrint('Failed to load settings: $e');
      debugPrint('Stack trace: $stackTrace');
      return Settings.defaults();
    }
  }

  Future<bool> saveSettings(Settings settings) async {
    try {
      debugPrint('Saving settings to SharedPreferences...');
      final jsonString = jsonEncode(settings.toJson());
      final success = await _prefs.setString(_settingsKey, jsonString);

      if (success) {
        debugPrint('Settings saved successfully');
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
}
