import 'package:flutter/foundation.dart';

/// Log levels for controlling output verbosity
enum LogLevel { debug, info, warning, error }

/// Minimalistic logger with configurable levels
/// Debug builds log at debug level; release builds log at info level and above
/// Test runs default to warning level (info and debug suppressed) unless verbose logging enabled
class Logger {
  static final LogLevel _minLevel = kReleaseMode
      ? LogLevel.info
      : const bool.fromEnvironment('debug_logs_enabled', defaultValue: false) ==
            false
      ? LogLevel.warning
      : LogLevel.debug;

  /// Whether debug-level logging is active (i.e. built with
  /// `--dart-define=debug_logs_enabled=true`). Used to gate diagnostic-only
  /// work (not just log lines) that shouldn't run in normal builds, such as
  /// dumping raw audio to disk — see [dumpDebugWav] in `utils/files.dart`.
  static bool get debugLogsEnabled => _minLevel == LogLevel.debug;

  static void debug(String message) {
    _log(LogLevel.debug, message);
  }

  static void info(String message) {
    _log(LogLevel.info, message);
  }

  static void warning(String message) {
    _log(LogLevel.warning, message);
  }

  static void error(String message) {
    _log(LogLevel.error, message);
  }

  static void _log(LogLevel level, String message) {
    if (level.index >= _minLevel.index) {
      debugPrint('[${level.name.toUpperCase()}] $message');
    }
  }
}
