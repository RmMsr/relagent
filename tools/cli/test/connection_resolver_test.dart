import 'dart:io';

import 'package:agentic_client/agentic_client.dart';
import 'package:path/path.dart' as p;
import 'package:relagent_cli/connection_resolver.dart';
import 'package:relagent_cli/settings_store.dart';
import 'package:relagent_cli/token_store.dart';
import 'package:test/test.dart';

class _FakeTokenStore implements TokenStore {
  String? stored;
  _FakeTokenStore({this.stored});

  @override
  Future<String?> readToken() async => stored;

  @override
  Future<bool> deleteToken() async {
    stored = null;
    return true;
  }

  @override
  Future<bool> writeToken(String token) async {
    stored = token;
    return true;
  }
}

void main() {
  late Directory tempDir;
  late SettingsStore settingsStore;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('relagent_cli_test_');
    settingsStore = SettingsStore(
      file: File(p.join(tempDir.path, 'settings.ini')),
    );
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('ConnectionResolver precedence', () {
    test('flag overrides env var and persisted value', () async {
      settingsStore.writeEngineUrl('http://persisted:8000');
      final resolver = ConnectionResolver(
        settingsStore: settingsStore,
        tokenStore: _FakeTokenStore(stored: 'persisted-token'),
      );

      final resolved = await resolver.resolve(
        flagUrl: 'http://flag:8000',
        flagToken: 'flag-token',
      );

      expect(resolved.engineUrl, 'http://flag:8000');
      expect(resolved.token, 'flag-token');
      expect(resolved.authType, AuthType.apiKey);
    });

    test('env var overrides persisted value', () async {
      settingsStore.writeEngineUrl('http://persisted:8000');
      final resolver = ConnectionResolver(
        settingsStore: settingsStore,
        tokenStore: _FakeTokenStore(stored: 'persisted-token'),
        environment: const {
          'ENGINE_URL': 'http://env:8000',
          'ENGINE_TOKEN': 'env-token',
        },
      );

      final resolved = await resolver.resolve();

      expect(resolved.engineUrl, 'http://env:8000');
      expect(resolved.token, 'env-token');
    });

    test('persisted value is used when no flag or env var is given', () async {
      settingsStore.writeEngineUrl('http://persisted:8000');
      final resolver = ConnectionResolver(
        settingsStore: settingsStore,
        tokenStore: _FakeTokenStore(stored: 'persisted-token'),
      );

      final resolved = await resolver.resolve();

      expect(resolved.engineUrl, 'http://persisted:8000');
      expect(resolved.token, 'persisted-token');
    });

    test(
      'falls back to the default engine URL when nothing else is set',
      () async {
        final resolver = ConnectionResolver(
          settingsStore: settingsStore,
          tokenStore: _FakeTokenStore(),
        );

        final resolved = await resolver.resolve();

        expect(resolved.engineUrl, defaultEngineBaseUrl);
        expect(resolved.token, isNull);
        expect(resolved.authType, AuthType.none);
      },
    );
  });
}
