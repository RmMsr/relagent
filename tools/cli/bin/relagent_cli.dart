import 'dart:io';

import 'package:args/command_runner.dart';

import '../lib/ask_command.dart';
import '../lib/chat_command.dart';
import '../lib/config_command.dart';

Future<void> main(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'relagent',
          "Terminal client for the Relagent engine's chat API.",
        )
        ..addCommand(ConfigCommand())
        ..addCommand(AskCommand())
        ..addCommand(ChatCommand());

  // Bare invocation defaults to `chat` when stdin is an interactive
  // terminal, and to `ask` when stdin is piped/redirected — a REPL can't
  // read from a non-terminal, and `ask` already knows how to consume
  // piped input as the prompt. ChatCommand itself walks the user through
  // `config` first if nothing is configured yet.
  final effectiveArgs = args.isNotEmpty
      ? args
      : (stdin.hasTerminal ? ['chat'] : ['ask']);

  final exitCode = await runner.run(effectiveArgs) ?? 0;
  exit(exitCode);
}
