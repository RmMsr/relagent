import 'dart:io';

import 'package:agentic_client/agentic_client.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';

import 'config_wizard.dart';
import 'settings_store.dart';
import 'token_store.dart';

/// Setup wizard: asks for the engine URL and auth token, blank input keeps
/// the current value, runs a connection test at the end. See the
/// cli-config spec.
class ConfigCommand extends Command<int> {
  @override
  final name = 'config';
  @override
  final description = 'Interactively configure the engine connection.';

  final SettingsStore settingsStore;
  final TokenStore tokenStore;
  final EngineHealthCheckService healthCheck;

  ConfigCommand({
    SettingsStore? settingsStore,
    TokenStore? tokenStore,
    EngineHealthCheckService? healthCheck,
  }) : settingsStore = settingsStore ?? SettingsStore(),
       tokenStore = tokenStore ?? SecretServiceTokenStore(),
       healthCheck = healthCheck ?? EngineHealthCheckService() {
    argParser.addFlag(
      'clear',
      help:
          'Remove the persisted engine URL and stored auth token, '
          'resetting to defaults.',
      negatable: false,
    );
  }

  @override
  Future<int> run() async {
    if (argResults!['clear'] as bool) {
      settingsStore.clear();
      final tokenCleared = await tokenStore.deleteToken();
      stdout.writeln('Cleared the persisted engine URL.');
      if (tokenCleared) {
        stdout.writeln('Cleared the stored auth token.');
      } else {
        stderr.writeln(
          'Warning: could not clear the stored token '
          '(Secret Service unavailable).',
        );
      }
      return 0;
    }

    final currentUrl = settingsStore.readEngineUrl() ?? defaultEngineBaseUrl;
    final hasToken = await tokenStore.readToken() != null;
    final currentAlwaysPurgeSession =
        settingsStore.readAlwaysPurgeSession() ?? false;

    stdout.write('Engine URL [$currentUrl]: ');
    final urlInput = stdin.readLineSync() ?? '';

    stdout.write(
      'Auth token [${hasToken ? 'set — leave blank to keep' : 'not set'}]: ',
    );
    final tokenInput = _readMaskedLine();

    stdout.write(
      'Always purge session when chat ends? '
      '[${currentAlwaysPurgeSession ? 'y' : 'N'}]: ',
    );
    final alwaysPurgeSessionInput = stdin.readLineSync() ?? '';

    final decision = decideConfigWizardAnswers(
      currentUrl: currentUrl,
      urlInput: urlInput,
      tokenInput: tokenInput,
      currentAlwaysPurgeSession: currentAlwaysPurgeSession,
      alwaysPurgeSessionInput: alwaysPurgeSessionInput,
    );

    if (decision.urlChanged) {
      settingsStore.writeEngineUrl(decision.engineUrl);
    }
    settingsStore.writeAlwaysPurgeSession(decision.alwaysPurgeSession);
    if (decision.newToken != null) {
      final stored = await tokenStore.writeToken(decision.newToken!);
      if (!stored) {
        stderr.writeln(
          'Warning: could not store the token securely '
          '(Secret Service unavailable) — it will not persist.',
        );
      }
    }

    final token = decision.newToken ?? await tokenStore.readToken();

    stdout.writeln('Testing connection to ${decision.engineUrl} ...');
    final result = await healthCheck.checkStatus(
      baseUrl: decision.engineUrl,
      authType: token != null ? AuthType.apiKey : AuthType.none,
      apiKey: token,
    );

    if (result.isSuccess) {
      stdout.writeln('Connection succeeded.');
      return 0;
    }
    stdout.writeln('Connection failed: ${result.message}');
    return 1;
  }

  /// Reads a line from the terminal without echoing typed characters,
  /// printing `*` per character instead. Falls back to a plain (unmasked)
  /// line read when stdin isn't an interactive terminal.
  String _readMaskedLine() {
    if (!stdin.hasTerminal) {
      return stdin.readLineSync() ?? '';
    }

    final console = Console();
    final buffer = StringBuffer();
    while (true) {
      final key = console.readKey();
      if (key.controlChar == ControlCharacter.enter ||
          key.controlChar == ControlCharacter.ctrlJ) {
        break;
      }
      if (key.controlChar == ControlCharacter.backspace ||
          key.controlChar == ControlCharacter.ctrlH) {
        final current = buffer.toString();
        if (current.isNotEmpty) {
          buffer
            ..clear()
            ..write(current.substring(0, current.length - 1));
          stdout.write('\b \b');
        }
        continue;
      }
      if (key.controlChar == ControlCharacter.ctrlC) {
        stdout.writeln();
        exit(130);
      }
      if (!key.isControl && key.char.isNotEmpty) {
        buffer.write(key.char);
        stdout.write('*');
      }
    }
    stdout.writeln();
    return buffer.toString();
  }
}
