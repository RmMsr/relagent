import 'dart:io';

import 'package:agentic_client/agentic_client.dart';
import 'package:args/command_runner.dart';
import 'package:dart_console/dart_console.dart';

import 'config_command.dart';
import 'connection_resolver.dart';
import 'cycle_runner.dart';
import 'live_input.dart';

/// Interactive REPL: scrolling transcript, a live-redrawn expanding input
/// box, inline grant/decline prompts for tool-call approvals. See the
/// cli-chat-repl spec.
class ChatCommand extends Command<int> {
  @override
  final name = 'chat';
  @override
  final description = 'Start an interactive chat session with the engine.';

  final ConnectionResolver connectionResolver;

  ChatCommand({ConnectionResolver? connectionResolver})
    : connectionResolver = connectionResolver ?? ConnectionResolver() {
    argParser.addOption('engine-url', help: 'Engine base URL.');
    argParser.addOption('token', help: 'Engine auth token.');
    argParser.addFlag(
      'purge-session',
      help: 'Delete the session from the engine when the chat ends. '
          'Defaults to the "always purge session" setting from `relagent '
          'config` when not passed.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    final flagUrl = argResults!['engine-url'] as String?;
    final flagToken = argResults!['token'] as String?;

    // First run: nothing configured yet and no override given for this
    // invocation either — walk through `config` before starting the chat,
    // rather than silently falling back to the default engine URL.
    final nothingConfiguredYet =
        flagUrl == null &&
        connectionResolver.environment['ENGINE_URL'] == null &&
        connectionResolver.settingsStore.readEngineUrl() == null;
    if (nothingConfiguredYet) {
      stdout.writeln("No engine configured yet — let's set that up.\n");
      final configExitCode = await ConfigCommand(
        settingsStore: connectionResolver.settingsStore,
        tokenStore: connectionResolver.tokenStore,
      ).run();
      if (configExitCode != 0) {
        stderr.writeln(
          'Configuration incomplete — run `relagent config` to retry.',
        );
        return configExitCode;
      }
      stdout.writeln();
    }

    final resolved = await connectionResolver.resolve(
      flagUrl: flagUrl,
      flagToken: flagToken,
    );
    final connection = EngineConnection(
      baseUrl: resolved.engineUrl,
      authType: resolved.authType,
      apiKey: resolved.token,
    );
    final purgeOnExit = argResults!.wasParsed('purge-session')
        ? argResults!['purge-session'] as bool
        : connectionResolver.settingsStore.readAlwaysPurgeSession() ?? false;

    stdout.writeln(
      'Connected to ${connection.baseUrl}. /exit or Ctrl+D to quit.\n',
    );

    final interactive = stdin.hasTerminal;

    // Raw mode with echo disabled is held for the whole session (not just
    // while actively reading a line): input is echoed by LiveInput's own
    // box redraw instead of the terminal, which is what lets it show
    // keystrokes typed while a cycle is in flight without them
    // interleaving with the response being printed concurrently.
    //
    // This must happen *before* constructing Console: it snapshots the
    // terminal's current mode as "original" and restores exactly that
    // after every readKey()-style raw read, so if Console were built
    // first, the approval prompt would silently flip echo back on.
    if (interactive) {
      try {
        stdin.echoMode = false;
        stdin.lineMode = false;
      } on StdinException {
        // Not actually a controllable terminal; fall through untouched.
      }
    }
    final console = Console();
    LiveInput? liveInput;
    if (interactive) {
      liveInput = LiveInput(console)..start();
      liveInput.showInitialPrompt();
    }

    String? sessionId;

    try {
      while (true) {
        final input = interactive
            ? await liveInput!.nextMessage()
            : stdin.readLineSync();

        if (input == null) break; // EOF
        final trimmed = input.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed == '/exit') break;

        // Sequential turn enforcement: only one cycle is ever in flight.
        // A message submitted while this one runs is queued by LiveInput
        // and handed back on the next nextMessage() call, not sent now.
        liveInput?.busy = true;
        try {
          final response = await runCycle(
            connection: connection,
            sessionId: sessionId,
            content: input,
            onIntermediateMessage: (message) {
              final notification = message.notification;
              if (notification == null || notification.isEmpty) return;
              liveInput?.hideForPrint();
              stdout.writeln('* $notification');
              liveInput?.showAfterPrint();
            },
            decideApproval: (approval) => _promptApproval(
              liveInput,
              approval,
              interactive: interactive,
            ),
          );
          sessionId = response.sessionId ?? sessionId;

          final label = response.role == AgenticRole.error
              ? 'error'
              : 'assistant';
          liveInput?.hideForPrint();
          stdout.writeln('$label: ${response.text}\n');
          liveInput?.showAfterPrint();
        } on EngineApiException catch (e) {
          liveInput?.hideForPrint();
          stderr.writeln('Error: ${e.userMessage}\n');
          liveInput?.showAfterPrint();
        } catch (e) {
          liveInput?.hideForPrint();
          stderr.writeln('Error: $e\n');
          liveInput?.showAfterPrint();
        } finally {
          liveInput?.busy = false;
        }
      }
    } finally {
      if (interactive) {
        try {
          stdin.lineMode = true;
          stdin.echoMode = true;
        } on StdinException {}
      }
    }

    if (purgeOnExit && sessionId != null) {
      try {
        await deleteSessionApi(
          baseUrl: connection.baseUrl,
          sessionId: sessionId,
          authType: connection.authType,
          apiKey: connection.apiKey,
        );
        stdout.writeln('Session purged.');
      } catch (e) {
        stderr.writeln('Could not purge session: $e');
      }
    }

    return 0;
  }

  /// Mirrors `approval_card.dart`'s grant / continue-without semantics as a
  /// single-keypress prompt. Falls back to a plain line read (defaulting
  /// anything other than an explicit "g"/"grant" to decline) when stdin
  /// isn't an interactive terminal.
  Future<ApprovalDecision> _promptApproval(
    LiveInput? liveInput,
    ApprovalData approval, {
    required bool interactive,
  }) async {
    final component = approval.component;
    final requestLine =
        'Approval requested: ${approval.purpose}'
        '${component != null ? ' (component: $component)' : ''}';

    if (!interactive) {
      stdout.writeln(requestLine);
      stdout.write('[g] Grant   [c] Continue without: ');
      final line = stdin.readLineSync()?.trim().toLowerCase() ?? '';
      stdout.writeln(line);
      if (line == 'g' || line == 'grant') {
        return ApprovalDecision.grant(
          GrantRequest.fromApproval(
            approval,
            maxSensitivity: approval.sensitivity,
          ),
        );
      }
      return const ApprovalDecision.decline();
    }

    liveInput!.hideForPrint();
    stdout.writeln(requestLine);
    stdout.write('[g] Grant   [c] Continue without: ');
    final char = await liveInput.readApprovalKey();
    if (char == 'g') {
      return ApprovalDecision.grant(
        GrantRequest.fromApproval(
          approval,
          maxSensitivity: approval.sensitivity,
        ),
      );
    }
    return const ApprovalDecision.decline();
  }
}
