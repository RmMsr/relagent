@Tags(['integration'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end smoke test against the engine's demo mode
/// (`uv run python -m engine.api.demo`), exercising the compiled `ask`
/// command as a real subprocess. Skips itself at runtime (rather than
/// failing) when `uv` isn't available or the demo server doesn't come up,
/// since this test depends on a Python toolchain outside the Dart
/// package's own dependency graph.
void main() {
  late String repoRoot;
  late String cliRoot;
  Process? server;

  setUpAll(() async {
    cliRoot = Directory.current.path;
    repoRoot = p.normalize(p.join(cliRoot, '..', '..'));

    if (Process.runSync('which', ['uv']).exitCode != 0) return;

    server = await Process.start('uv', [
      'run',
      'python',
      '-m',
      'engine.api.demo',
    ], workingDirectory: repoRoot);

    final ready = await _waitForStatus(
      'http://127.0.0.1:8000/api/v1/status',
      timeout: const Duration(seconds: 30),
    );
    if (!ready) {
      server?.kill();
      server = null;
    }
  });

  tearDownAll(() {
    server?.kill();
  });

  test('ask: plain prompt gets a reply and exits 0', () async {
    if (server == null) {
      markTestSkipped(
        'demo engine not reachable (uv unavailable or server failed to start)',
      );
      return;
    }
    final result = await _runAsk('hello there', cliRoot);
    expect(result.exitCode, 0);
    expect(result.stdout.toString().trim(), isNotEmpty);
  });

  test(
    'ask: a "search "-triggered approval is auto-declined and the cycle settles',
    () async {
      if (server == null) {
        markTestSkipped(
          'demo engine not reachable (uv unavailable or server failed to start)',
        );
        return;
      }
      final result = await _runAsk('search cats', cliRoot);
      expect(result.exitCode, 0);
      expect(
        result.stdout.toString().toLowerCase(),
        contains('search'),
        reason:
            "the demo agent's decline-path reply explains it cannot search "
            'without an approved web_search call',
      );
    },
  );
}

Future<ProcessResult> _runAsk(String prompt, String cliRoot) {
  return Process.run('dart', [
    'run',
    'bin/relagent_cli.dart',
    'ask',
    prompt,
    '--engine-url',
    'http://127.0.0.1:8000',
  ], workingDirectory: cliRoot);
}

Future<bool> _waitForStatus(String url, {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  final client = HttpClient();
  try {
    while (DateTime.now().isBefore(deadline)) {
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == 200) return true;
      } catch (_) {
        // Not ready yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  } finally {
    client.close(force: true);
  }
}
