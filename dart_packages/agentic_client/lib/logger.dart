import 'dart:io';

/// Minimal print-based logger. Debug-level output is gated behind the
/// `AGENTIC_CLIENT_DEBUG` environment variable; everything else always
/// prints.
class Logger {
  static final bool _debugEnabled = _readDebugEnabled();

  // Platform.environment throws UnsupportedError on web/wasm; treat that as
  // "debug disabled" rather than crashing every caller.
  static bool _readDebugEnabled() {
    try {
      return Platform.environment['AGENTIC_CLIENT_DEBUG'] == '1';
    } catch (_) {
      return false;
    }
  }

  static void debug(String message) {
    if (_debugEnabled) print('[DEBUG] $message');
  }

  static void info(String message) => print('[INFO] $message');

  static void warning(String message) => print('[WARNING] $message');

  static void error(String message) => print('[ERROR] $message');
}
