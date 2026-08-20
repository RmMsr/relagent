import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '/models/settings.dart';
import '/utils/logger.dart';

const _settingsKey = 'user_settings';

class SettingsPersistenceManager {
  final SharedPreferences _prefs;

  /// Chains saveSettings() calls so they run one at a time. Callers can
  /// trigger a save from independent places (an explicit user edit, the
  /// post-scan model-selection cleanup) around the same time; without this,
  /// two concurrent writes can interleave between one call's setString and
  /// its own read-back verification, making that verification see the
  /// *other* call's value and fail spuriously — or worse, persist whichever
  /// write happened to land last regardless of call order.
  Future<void> _saveQueue = Future.value();

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

  Future<bool> saveSettings(Settings settings) {
    final result = _saveQueue.then((_) => _doSaveSettings(settings));
    _saveQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _doSaveSettings(Settings settings) async {
    try {
      final jsonString = jsonEncode(settings.toJson());
      final success = await _prefs.setString(_settingsKey, jsonString);

      if (success) {
        final verified = _prefs.getString(_settingsKey);
        if (verified != jsonString) {
          Logger.warning(
            'Save verification failed - data may not be persisted',
          );
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
