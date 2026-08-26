import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '/services/api_health_check.dart';
import '/utils/logger.dart';

/// Provider for automatic API health checks
final healthCheckProvider =
    NotifierProvider<HealthCheckNotifier, HealthCheckState>(() {
      return HealthCheckNotifier();
    });

/// State for health check provider
class HealthCheckState {
  final HealthCheckResult? lastResult;
  final bool isRunning;
  final DateTime? lastCheckTime;

  const HealthCheckState({
    this.lastResult,
    this.isRunning = false,
    this.lastCheckTime,
  });

  HealthCheckState copyWith({
    HealthCheckResult? lastResult,
    bool? isRunning,
    DateTime? lastCheckTime,
  }) {
    return HealthCheckState(
      lastResult: lastResult ?? this.lastResult,
      isRunning: isRunning ?? this.isRunning,
      lastCheckTime: lastCheckTime ?? this.lastCheckTime,
    );
  }
}

class HealthCheckNotifier extends Notifier<HealthCheckState> {
  Timer? _debounceTimer;
  Timer? _retryTimer;
  static const _debounceDuration = Duration(seconds: 2);
  static const _retryInterval = Duration(seconds: 15);

  @override
  HealthCheckState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _retryTimer?.cancel();
    });

    return const HealthCheckState();
  }

  /// Trigger health check with debouncing
  void triggerHealthCheck() {
    final settings = ref.read(settingsProvider);

    // Don't run if OpenAI-compatible backend is not active
    if (settings.selectedBackend != ChatBackendType.openAiCompatible) {
      return;
    }

    // Cancel existing timer
    _debounceTimer?.cancel();

    // Start new debounce timer
    _debounceTimer = Timer(_debounceDuration, () {
      _performHealthCheck();
    });

    Logger.info('Health check scheduled (debounced)');
  }

  /// Trigger startup health check with retry logic for system recovery
  void triggerStartupHealthCheck() {
    Future.microtask(() => _performStartupHealthCheck());
  }

  Future<void> _performStartupHealthCheck() async {
    final settings = ref.read(settingsProvider);

    // Don't run if OpenAI-compatible backend is not active
    if (settings.selectedBackend != ChatBackendType.openAiCompatible) {
      return;
    }

    // Don't run if URL is empty or invalid
    if (settings.simpleChatBaseUrl.trim().isEmpty) {
      return;
    }
    const maxRetries = 3;
    const retryDelays = [
      Duration.zero, // First attempt: immediate
      Duration(seconds: 2), // Second attempt: 2s delay
      Duration(seconds: 5), // Third attempt: 5s delay
      Duration(seconds: 10), // Fourth attempt: 10s delay
    ];

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = retryDelays[attempt];
        Logger.info(
          'Startup health check retry $attempt/$maxRetries in ${delay.inSeconds}s',
        );
        await Future<void>.delayed(delay);
      } else {
        Logger.info('Startup health check: initial attempt');
      }

      await _performHealthCheck();

      // Stop retrying if check succeeded
      if (state.lastResult?.isSuccess == true) {
        Logger.info('Startup health check succeeded');
        return;
      }

      // Log failure reason for this attempt
      if (state.lastResult != null) {
        Logger.info(
          'Startup health check attempt ${attempt + 1} failed: ${state.lastResult!.message}',
        );
      }
    }

    Logger.info('Startup health check: all retries exhausted');
  }

  /// Perform immediate health check (bypass debouncing)
  Future<void> performImmediateHealthCheck() async {
    _debounceTimer?.cancel();
    await _performHealthCheck();
  }

  Future<void> _performHealthCheck() async {
    if (state.isRunning) {
      Logger.info('Health check already running, skipping');
      return;
    }

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    // Don't run if OpenAI-compatible backend is not active
    if (settings.selectedBackend != ChatBackendType.openAiCompatible) {
      Logger.info('Health check skipped: OpenAI-compatible backend not active');
      return;
    }

    // Don't run if URL is empty or invalid
    if (settings.simpleChatBaseUrl.trim().isEmpty) {
      Logger.info('Health check skipped: empty URL');
      return;
    }

    state = state.copyWith(isRunning: true);
    Logger.info('Running automatic health check');

    try {
      final service = ApiHealthCheckService();
      final password = await settingsNotifier.getPassword();
      final apiKey = await settingsNotifier.getChatApiKey();

      final result = await service.performHealthCheck(
        baseUrl: settings.simpleChatBaseUrl,
        model: settings.simpleChatModel,
        authType: settings.authType,
        username: settings.username,
        password: password,
        apiKey: apiKey,
      );

      // Auto-update authType if authentication is detected
      if (result.requiresAuth && result.detectedAuthType != null) {
        Logger.info(
          'Auto-detected auth type: ${result.detectedAuthType!.name}',
        );
        await settingsNotifier.updateAuthType(result.detectedAuthType!);
      }

      state = state.copyWith(
        lastResult: result,
        isRunning: false,
        lastCheckTime: DateTime.now(),
      );

      Logger.info('Health check completed: ${result.status.name}');
      _scheduleRetryIfNeeded(result);
    } catch (e) {
      Logger.error('Health check failed: $e');
      final failResult = HealthCheckResult.connectionFailed(e.toString());
      state = state.copyWith(
        lastResult: failResult,
        isRunning: false,
        lastCheckTime: DateTime.now(),
      );
      _scheduleRetryIfNeeded(failResult);
    }
  }

  void _scheduleRetryIfNeeded(HealthCheckResult result) {
    _retryTimer?.cancel();
    if (!result.isSuccess) {
      _retryTimer = Timer(_retryInterval, () {
        _performHealthCheck();
      });
    }
  }

  /// Clear health check result
  void clearResult() {
    _retryTimer?.cancel();
    state = const HealthCheckState();
  }
}
