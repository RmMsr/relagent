import 'dart:io';

import 'package:ini/ini.dart';
import 'package:path/path.dart' as p;

/// Reads and writes the CLI's persisted engine URL at
/// `~/.local/share/org.venkado.relagent-cli/settings.ini`, mirroring the
/// ini-based convention `engine/settings.py` uses for the engine itself.
///
/// Tolerates a missing or invalid file by falling back to the default,
/// matching the engine's own tolerant behavior.
class SettingsStore {
  final File file;

  SettingsStore({File? file}) : file = file ?? _defaultFile();

  static File _defaultFile() {
    final home = Platform.environment['HOME'] ?? '';
    return File(
      p.join(
        home,
        '.local',
        'share',
        'org.venkado.relagent-cli',
        'settings.ini',
      ),
    );
  }

  String? readEngineUrl() {
    if (!file.existsSync()) return null;
    try {
      final config = Config.fromString(file.readAsStringSync());
      return config.get('engine', 'url');
    } catch (_) {
      return null;
    }
  }

  void writeEngineUrl(String url) {
    var config = _readConfig();
    if (!config.hasSection('engine')) config.addSection('engine');
    config.set('engine', 'url', url);
    _writeConfig(config);
  }

  /// Whether the `chat` command should purge the session on exit by
  /// default, without needing `--purge-session` passed each time. `null`
  /// when never set.
  bool? readAlwaysPurgeSession() {
    if (!file.existsSync()) return null;
    try {
      final config = Config.fromString(file.readAsStringSync());
      final value = config.get('chat', 'always_purge_session');
      if (value == null) return null;
      return value == 'true';
    } catch (_) {
      return null;
    }
  }

  void writeAlwaysPurgeSession(bool value) {
    var config = _readConfig();
    if (!config.hasSection('chat')) config.addSection('chat');
    config.set('chat', 'always_purge_session', value.toString());
    _writeConfig(config);
  }

  Config _readConfig() {
    if (!file.existsSync()) return Config();
    try {
      return Config.fromString(file.readAsStringSync());
    } catch (_) {
      return Config();
    }
  }

  void _writeConfig(Config config) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(config.toString());
  }

  /// Removes the persisted settings file, if any.
  void clear() {
    if (file.existsSync()) file.deleteSync();
  }
}
