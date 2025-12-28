import 'package:flutter/foundation.dart';

/// Log levels for controlling output verbosity
enum LogLevel { debug, info, warning, error }

/// Minimalistic logger with configurable levels
/// Default: debug level in debug builds, no output in release
class Logger {
  static LogLevel _minLevel = LogLevel.debug;

  /// Set minimum log level (e.g., LogLevel.info to hide debug messages)
  static void setLogLevel(LogLevel level) {
    _minLevel = level;
  }

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
