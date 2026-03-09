import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '/agentic/self_test_service.dart';
import '/models/self_test_result.dart';
import '/models/settings.dart';
import '/providers/settings_provider.dart';

class SelfTestState {
  final List<SelfTestResult> results;
  final bool isRunning;

  const SelfTestState({this.results = const [], this.isRunning = false});

  SelfTestState copyWith({List<SelfTestResult>? results, bool? isRunning}) {
    return SelfTestState(
      results: results ?? this.results,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

final selfTestProvider = NotifierProvider<SelfTestNotifier, SelfTestState>(
  SelfTestNotifier.new,
);

class SelfTestNotifier extends Notifier<SelfTestState> {
  @override
  SelfTestState build() => const SelfTestState();

  Future<void> runSelfTests() async {
    if (state.isRunning) return;

    final initialResults = [
      const SelfTestResult(
        id: 'engine-reachable',
        label: 'Engine reachable',
        status: SelfTestStatus.pending,
      ),
      const SelfTestResult(
        id: 'engine-auth',
        label: 'Engine authentication',
        status: SelfTestStatus.pending,
      ),
      const SelfTestResult(
        id: 'engine-version',
        label: 'Version match',
        status: SelfTestStatus.pending,
      ),
      const SelfTestResult(
        id: 'engine-tests',
        label: 'Engine self-tests',
        status: SelfTestStatus.pending,
      ),
    ];

    state = SelfTestState(results: initialResults, isRunning: true);

    final settings = ref.read(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final baseUrl = settings.engineBaseUrl;
    final authType = settings.engineAuthType;
    final username = settings.engineUsername;
    final password = await settingsNotifier.getEnginePassword();
    final apiKey = await settingsNotifier.getEngineApiKey();

    // Test 1: Engine reachable
    _setStatus('engine-reachable', SelfTestStatus.running);
    final elapsed = await fetchEngineHealth(baseUrl: baseUrl);
    if (elapsed == null) {
      _setResult(
        SelfTestResult(
          id: 'engine-reachable',
          label: 'Engine reachable',
          status: SelfTestStatus.error,
          detail:
              'Could not reach $baseUrl/health — check the engine base URL in settings',
        ),
      );
      _skipRemaining(['engine-auth', 'engine-version', 'engine-tests']);
      state = state.copyWith(isRunning: false);
      return;
    }
    _setResult(
      SelfTestResult(
        id: 'engine-reachable',
        label: 'Engine reachable',
        status: SelfTestStatus.ok,
        detail:
            'responded in ${(elapsed.inMilliseconds / 1000).toStringAsFixed(3)}s',
      ),
    );

    // Test 2: Engine auth (also fetches version for test 3)
    _setStatus('engine-auth', SelfTestStatus.running);
    Map<String, dynamic>? statusData;
    try {
      statusData = await fetchEngineStatus(
        baseUrl: baseUrl,
        authType: authType,
        username: username,
        password: password,
        apiKey: apiKey,
      );
      final authDetail = _describeAuth(authType, username, apiKey);
      _setResult(
        SelfTestResult(
          id: 'engine-auth',
          label: 'Engine authentication',
          status: authDetail.isWarning
              ? SelfTestStatus.warning
              : SelfTestStatus.ok,
          detail: authDetail.text,
        ),
      );
    } on SelfTestAuthException catch (e) {
      _setResult(
        SelfTestResult(
          id: 'engine-auth',
          label: 'Engine authentication',
          status: SelfTestStatus.error,
          detail:
              '${e.message} — check the connection settings on the settings page',
        ),
      );
      _skipRemaining(['engine-version', 'engine-tests']);
      state = state.copyWith(isRunning: false);
      return;
    } on SelfTestServiceException catch (e) {
      _setResult(
        SelfTestResult(
          id: 'engine-auth',
          label: 'Engine authentication',
          status: SelfTestStatus.error,
          detail: e.message,
        ),
      );
      _skipRemaining(['engine-version', 'engine-tests']);
      state = state.copyWith(isRunning: false);
      return;
    }

    // Test 3: Version match
    _setStatus('engine-version', SelfTestStatus.running);
    await _runVersionCheck(statusData);

    // Test 4: Engine self-tests
    _setStatus('engine-tests', SelfTestStatus.running);
    await _runEngineSelfTests(
      baseUrl: baseUrl,
      authType: authType,
      username: username,
      password: password,
      apiKey: apiKey,
    );

    state = state.copyWith(isRunning: false);
  }

  Future<void> _runVersionCheck(Map<String, dynamic> statusData) async {
    final engineVersion = statusData['version'] as String?;
    if (engineVersion == null) {
      _setResult(
        const SelfTestResult(
          id: 'engine-version',
          label: 'Version match',
          status: SelfTestStatus.warning,
          detail: 'Engine version not available',
        ),
      );
      return;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final appVersion = packageInfo.version;

    final appParts = appVersion.split('.');
    final engineParts = engineVersion.split('.');

    final appMajor = appParts.isNotEmpty ? appParts[0] : '0';
    final appMinor = appParts.length > 1 ? appParts[1] : '0';
    final appPatch = appParts.length > 2 ? appParts[2] : '0';
    final engineMajor = engineParts.isNotEmpty ? engineParts[0] : '0';
    final engineMinor = engineParts.length > 1 ? engineParts[1] : '0';
    final enginePatch = engineParts.length > 2 ? engineParts[2] : '0';

    final SelfTestStatus status;
    final String detail;
    if (appMajor != engineMajor || appMinor != engineMinor) {
      status = SelfTestStatus.error;
      final appIsLower =
          '$appMajor.$appMinor'.compareTo('$engineMajor.$engineMinor') < 0;
      final hint = appIsLower ? 'update the app' : 'update the engine';
      detail =
          'versions differ, app $appVersion · engine $engineVersion — $hint to match';
    } else if (appPatch != enginePatch) {
      status = SelfTestStatus.warning;
      detail = 'patch versions differ, app $appVersion · engine $engineVersion';
    } else {
      status = SelfTestStatus.ok;
      detail = 'app and engine on $appVersion';
    }

    _setResult(
      SelfTestResult(
        id: 'engine-version',
        label: 'Version match',
        status: status,
        detail: detail,
      ),
    );
  }

  Future<void> _runEngineSelfTests({
    required String baseUrl,
    required AuthType authType,
    String? username,
    String? password,
    String? apiKey,
  }) async {
    try {
      final engineResults = await fetchEngineSelfTests(
        baseUrl: baseUrl,
        authType: authType,
        username: username,
        password: password,
        apiKey: apiKey,
      );

      final expanded = engineResults.asMap().entries.map((entry) {
        final i = entry.key;
        final r = entry.value;
        final name = r['name'] as String? ?? 'Test ${i + 1}';
        final statusStr = r['status'] as String? ?? 'error';
        final detail = r['detail'] as String?;
        final status = switch (statusStr) {
          'ok' => SelfTestStatus.ok,
          'warning' => SelfTestStatus.warning,
          _ => SelfTestStatus.error,
        };
        return SelfTestResult(
          id: 'engine-test-$i',
          label: name,
          status: status,
          detail: detail,
        );
      }).toList();

      final updatedResults = List<SelfTestResult>.from(state.results);
      final placeholderIndex = updatedResults.indexWhere(
        (r) => r.id == 'engine-tests',
      );
      if (placeholderIndex >= 0) {
        updatedResults.replaceRange(
          placeholderIndex,
          placeholderIndex + 1,
          expanded,
        );
      }
      state = state.copyWith(results: updatedResults);
    } on SelfTestServiceException catch (e) {
      _setResult(
        SelfTestResult(
          id: 'engine-tests',
          label: 'Engine self-tests',
          status: SelfTestStatus.error,
          detail: e.message,
        ),
      );
    }
  }

  void _setStatus(String id, SelfTestStatus status) {
    final updated = state.results.map((r) {
      return r.id == id ? r.copyWith(status: status) : r;
    }).toList();
    state = state.copyWith(results: updated);
  }

  void _setResult(SelfTestResult result) {
    final updated = state.results.map((r) {
      return r.id == result.id ? result : r;
    }).toList();
    state = state.copyWith(results: updated);
  }

  void _skipRemaining(List<String> ids) {
    final updated = state.results.map((r) {
      if (ids.contains(r.id) && r.status == SelfTestStatus.pending) {
        return r.copyWith(status: SelfTestStatus.error, detail: 'Skipped');
      }
      return r;
    }).toList();
    state = state.copyWith(results: updated);
  }

  void clearResults() {
    state = const SelfTestState();
  }

  _AuthDetail _describeAuth(
    AuthType authType,
    String? username,
    String? apiKey,
  ) {
    final parts = <String>[];
    if (authType == AuthType.basic && username != null) {
      parts.add('Basic Auth as $username');
    }
    if (apiKey != null) {
      parts.add('using API key');
    }
    if (parts.isEmpty) {
      return _AuthDetail('no authentication configured', isWarning: true);
    }
    return _AuthDetail(parts.join(' and '), isWarning: false);
  }
}

class _AuthDetail {
  final String text;
  final bool isWarning;
  const _AuthDetail(this.text, {required this.isWarning});
}
