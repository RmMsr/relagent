import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/health_check.dart';
import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '/utils/logger.dart';

class EngineHealthCheckState {
  final EngineHealthResult? lastResult;
  final bool isChecking;

  const EngineHealthCheckState({
    this.lastResult,
    this.isChecking = false,
  });

  EngineHealthCheckState copyWith({
    EngineHealthResult? lastResult,
    bool? isChecking,
  }) {
    return EngineHealthCheckState(
      lastResult: lastResult ?? this.lastResult,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

final engineHealthCheckProvider =
    NotifierProvider<EngineHealthCheckNotifier, EngineHealthCheckState>(() {
  return EngineHealthCheckNotifier();
});

class EngineHealthCheckNotifier extends Notifier<EngineHealthCheckState> {
  final _service = EngineHealthCheckService();
  Timer? _retryTimer;
  static const _retryInterval = Duration(seconds: 15);

  @override
  EngineHealthCheckState build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
    });
    return const EngineHealthCheckState();
  }

  Future<void> triggerHealthCheck() async {
    if (state.isChecking) return;

    final settings = ref.read(settingsProvider);

    // Don't run if Relagent Engine backend is not active
    if (settings.selectedBackend != ChatBackendType.relagentEngine) return;

    state = state.copyWith(isChecking: true);
    try {
      final settingsNotifier = ref.read(settingsProvider.notifier);
      final password = await settingsNotifier.getEnginePassword();
      final apiKey = await settingsNotifier.getEngineApiKey();

      final result = await _service.checkStatus(
        baseUrl: settings.engineBaseUrl,
        authType: settings.engineAuthType,
        username: settings.engineUsername,
        password: password,
        apiKey: apiKey,
      );

      state = EngineHealthCheckState(
        lastResult: result,
        isChecking: false,
      );

      // Schedule periodic retry if check failed
      _scheduleRetryIfNeeded(result);
    } catch (e) {
      Logger.error('Engine health check error: $e');
      state = EngineHealthCheckState(
        lastResult: EngineHealthResult.connectionFailed(e.toString()),
        isChecking: false,
      );
      _scheduleRetryIfNeeded(state.lastResult!);
    }
  }

  void _scheduleRetryIfNeeded(EngineHealthResult result) {
    _retryTimer?.cancel();
    if (!result.isSuccess) {
      _retryTimer = Timer(_retryInterval, () {
        triggerHealthCheck();
      });
    }
  }

  void clearResult() {
    _retryTimer?.cancel();
    state = const EngineHealthCheckState();
  }
}
