import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/agentic/health_check.dart';
import '/providers/settings_provider.dart';

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

  @override
  EngineHealthCheckState build() {
    return const EngineHealthCheckState();
  }

  Future<void> triggerHealthCheck() async {
    if (state.isChecking) return;

    state = state.copyWith(isChecking: true);

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final password = await settingsNotifier.getEnginePassword();

    final result = await _service.checkStatus(
      baseUrl: settings.engineBaseUrl,
      authType: settings.engineAuthType,
      username: settings.engineUsername,
      password: password,
    );

    state = EngineHealthCheckState(
      lastResult: result,
      isChecking: false,
    );
  }

  void clearResult() {
    state = const EngineHealthCheckState();
  }
}
