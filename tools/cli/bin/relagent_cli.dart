import 'dart:io';

import 'package:args/command_runner.dart';

import '../lib/ask_command.dart';
import '../lib/chat_command.dart';
import '../lib/config_command.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>(
    'relagent',
    "Terminal client for the Relagent engine's chat API.",
  )
    ..addCommand(ConfigCommand())
    ..addCommand(AskCommand())
    ..addCommand(ChatCommand());

  // Bare invocation defaults to `chat`; ChatCommand itself walks the user
  // through `config` first if nothing is configured yet.
  final effectiveArgs = args.isEmpty ? ['chat'] : args;

  final exitCode = await runner.run(effectiveArgs) ?? 0;
  exit(exitCode);
}
