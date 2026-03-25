import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';
import '/utils/logger.dart';

const _settingsKey = 'user_settings';

class SettingsPersistenceManager {
  final SharedPreferences _prefs;

  SettingsPersistenceManager(this._prefs);

  Settings loadSettings() {
    try {
      final jsonString = _prefs.getString(_settingsKey);
      if (jsonString != null) {
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return Settings.fromJson(json);
      } else {
        return Settings.defaults();
      }
    } catch (e, stackTrace) {
      Logger.error('Failed to load settings: $e\n$stackTrace');
      return Settings.defaults();
    }
  }

  Future<bool> saveSettings(Settings settings) async {
    try {
      final jsonString = jsonEncode(settings.toJson());
      final success = await _prefs.setString(_settingsKey, jsonString);

      if (success) {
        final verified = _prefs.getString(_settingsKey);
        if (verified != jsonString) {
          Logger.warning('Save verification failed - data may not be persisted');
          return false;
        }
      } else {
        Logger.error('setString returned false - save failed');
        return false;
      }

      return success;
    } catch (e, stackTrace) {
      Logger.error('Failed to save settings: $e\n$stackTrace');
      return false;
    }
  }
}
