import 'dart:isolate';
import 'package:flutter/foundation.dart';

/// Utility to run expensive operations in background isolates to prevent ANR
class BackgroundInitializer {
  static bool _initialized = false;

  /// Initialize heavy components in background to prevent main thread blocking
  static Future<void> initializeInBackground(
    Future<void> Function() operation, {
    String? operationName,
  }) async {
    if (_initialized) return;

    final name = operationName ?? 'Background operation';
    debugPrint('BackgroundInitializer: Starting $name in background...');

    try {
      // Run in a temporary isolate to avoid blocking main thread
      await Isolate.run(() async {
        await operation();
      });
      _initialized = true;
      debugPrint('BackgroundInitializer: ✓ $name completed');
    } catch (e) {
      debugPrint('BackgroundInitializer: ✗ $name failed: $e');
      rethrow;
    }
  }

  /// Run a quick non-blocking operation
  static Future<void> runQuickOperation(
    Future<void> Function() operation, {
    String? operationName,
  }) async {
    final name = operationName ?? 'Quick operation';
    debugPrint('BackgroundInitializer: Starting $name...');

    try {
      await operation();
      debugPrint('BackgroundInitializer: ✓ $name completed');
    } catch (e) {
      debugPrint('BackgroundInitializer: ✗ $name failed: $e');
    }
  }
}
