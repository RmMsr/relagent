import 'dart:io';

import 'package:agentic_client/agentic_client.dart';
import 'package:args/command_runner.dart';

import 'connection_resolver.dart';
import 'cycle_runner.dart';

/// Non-interactive single-turn command for automation: prompt via
/// positional argument or stdin, final assistant reply on stdout, pending
/// approvals auto-declined, non-zero exit on failure. See the
/// cli-single-turn spec.
class AskCommand extends Command<int> {
  @override
  final name = 'ask';
  @override
  final description =
      'Send a single prompt to the engine and print the reply.';

  final ConnectionResolver connectionResolver;

  AskCommand({ConnectionResolver? connectionResolver})
    : connectionResolver = connectionResolver ?? ConnectionResolver() {
    argParser.addOption('engine-url', help: 'Engine base URL.');
    argParser.addOption('token', help: 'Engine auth token.');
    argParser.addFlag(
      'purge-session',
      help: 'Delete the session from the engine after the reply is printed.',
      defaultsTo: false,
    );
  }

  @override
  String get invocation => 'relagent ask [prompt]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final prompt = rest.isNotEmpty ? rest.join(' ') : stdin.readLineSync();

    if (prompt == null || prompt.trim().isEmpty) {
      stderr.writeln('No prompt given (pass it as an argument or on stdin).');
      return 1;
    }

    final resolved = await connectionResolver.resolve(
      flagUrl: argResults!['engine-url'] as String?,
      flagToken: argResults!['token'] as String?,
    );
    final connection = EngineConnection(
      baseUrl: resolved.engineUrl,
      authType: resolved.authType,
      apiKey: resolved.token,
    );

    try {
      final response = await runCycle(
        connection: connection,
        sessionId: null,
        content: prompt,
        decideApproval: (_) async => const ApprovalDecision.decline(),
      );
      stdout.write(response.text);
      if (!response.text.endsWith('\n')) stdout.writeln();

      final sessionId = response.sessionId;
      if (argResults!['purge-session'] as bool && sessionId != null) {
        try {
          await deleteSessionApi(
            baseUrl: connection.baseUrl,
            sessionId: sessionId,
            authType: connection.authType,
            apiKey: connection.apiKey,
          );
        } catch (e) {
          stderr.writeln('Could not purge session: $e');
        }
      }

      return 0;
    } on EngineApiException catch (e) {
      stderr.writeln(e.userMessage);
      return 1;
    } catch (e) {
      stderr.writeln('Error: $e');
      return 1;
    }
  }
}
