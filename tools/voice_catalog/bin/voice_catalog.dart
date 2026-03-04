// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/catalog_index.dart';
import '../lib/discovery.dart';
import '../lib/download_service.dart';
import '../lib/evaluator.dart';
import '../lib/filter.dart';
import '../lib/status_reporter.dart';

void main(List<String> rawArgs) async {
  // Pre-process: '--eval' without an explicit value gets 'pending' injected so
  // that bare '--eval' keeps working alongside '--eval failed' / '--eval evaluated'.
  final args = <String>[];
  for (var i = 0; i < rawArgs.length; i++) {
    args.add(rawArgs[i]);
    final next = i + 1 < rawArgs.length ? rawArgs[i + 1] : null;
    final nextIsFlag = next == null || next.startsWith('-');
    if (rawArgs[i] == '--eval' && nextIsFlag) args.add('pending');
    if (rawArgs[i] == '--list' && nextIsFlag) args.add('approved');
  }

  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help')
    ..addFlag(
      'discover',
      negatable: false,
      help: 'Fetch new model entries from GitHub releases',
    )
    ..addOption(
      'eval',
      help: 'Filter + download + smoke-test entries with the given status\n'
          '(bare --eval defaults to pending)',
      valueHelp: 'STATUS',
      allowed: ['pending', 'failed', 'approved'],
    )
    ..addFlag(
      'status',
      negatable: false,
      help: 'Print catalog status summary (also shown after --discover/--eval)',
    )
    ..addOption(
      'list',
      help: 'List entries matching a state (with language filter applied)\n'
          'States: ignored, pending, failed, approved',
      valueHelp: 'STATE',
      defaultsTo: 'approved',
      allowed: ['ignored', 'pending', 'failed', 'approved'],
    )
    ..addFlag(
      'names-only',
      negatable: false,
      help: 'With --list: print only IDs, one per line (for shell piping)',
    )
    ..addFlag(
      'with-notes',
      negatable: false,
      help: 'With --names-only: append notes as (note) after each ID',
    )
    ..addMultiOption(
      'recheck',
      help: 'Reset and re-evaluate a specific model by ID\n'
          '(clears its status and notes, implies eval for those entries)',
      valueHelp: 'ID',
    )
    ..addFlag(
      'debug',
      negatable: false,
      help: 'Print stack traces and file inspection details during eval',
    )
    ..addFlag(
      'keep',
      negatable: false,
      help: 'Keep downloaded model files after evaluation (skip auto-delete)',
    )
    ..addOption(
      'type',
      abbr: 't',
      help: 'Filter by model type (default: all)',
      valueHelp: 'TYPE',
      allowed: ['asr', 'tts'],
    )
    ..addMultiOption(
      'lang',
      abbr: 'l',
      help: 'Language codes to include (repeat or comma-separate)\n'
          'Use "all" to disable the language filter\n'
          '(default: en)',
      valueHelp: 'LANG',
    )
    ..addOption(
      'catalog',
      abbr: 'c',
      help: 'Path to voice-models.json\n'
          '(default: auto-detected from project root)',
      valueHelp: 'FILE',
    )
    ..addOption(
      'fixtures-dir',
      help: 'Directory with reference WAV clips (en.wav, de.wav, …)\n'
          '(default: auto-detected from project root)',
      valueHelp: 'DIR',
    );

  ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln(_usage(parser));
    exit(1);
  }

  final doDiscover = parsed['discover'] as bool;
  final doEval = parsed.wasParsed('eval');
  final evalStatus = parsed['eval'] as String? ?? 'pending';
  final doStatus = parsed['status'] as bool;
  final listState =
      parsed.wasParsed('list') ? parsed['list'] as String : null;
  final namesOnly = parsed['names-only'] as bool;
  final withNotes = parsed['with-notes'] as bool;
  final typeFilter = parsed['type'] as String?;
  final recheckIds = (parsed['recheck'] as List<String>)
      .expand((s) => s.split(','))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final debug = parsed['debug'] as bool;

  if ((parsed['help'] as bool) ||
      (!doDiscover && !doEval && !doStatus &&
          listState == null && recheckIds.isEmpty)) {
    print(_usage(parser));
    exit(0);
  }

  // Resolve catalog path.
  var catalogPath = parsed['catalog'] as String? ?? _detectCatalogPath();
  if (catalogPath == null && doDiscover) {
    // For --discover on a fresh checkout, fall back to the assets directory.
    final assetsDir = _detectAssetsDir();
    if (assetsDir != null) {
      catalogPath = p.join(assetsDir, 'voice-models.json');
      if (!namesOnly) print('Creating new catalog at $catalogPath\n');
    }
  }
  if (catalogPath == null) {
    stderr.writeln(
      'Error: Cannot locate voice-models.json.\n'
      'Run from inside the project or pass --catalog <path>.',
    );
    exit(1);
  }

  // Resolve models cache directory (XDG_CACHE_HOME / ~/.cache).
  final cacheBase = Platform.environment['XDG_CACHE_HOME'] ??
      p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '/tmp',
        '.cache',
      );
  final modelsDir = p.join(cacheBase, 'relagent', 'models');

  // Resolve fixtures directory.
  final fixturesDir =
      parsed['fixtures-dir'] as String? ?? _detectFixturesDir();

  final keep = parsed['keep'] as bool;

  // Resolve language filter (default: en; --lang all → no filter).
  final langArgs = parsed['lang'] as List<String>;
  final Set<String> languages;
  if (langArgs.isEmpty) {
    languages = {'en'};
  } else {
    final codes =
        langArgs.expand((s) => s.split(',')).map((s) => s.trim()).toSet();
    languages = codes.contains('all') ? {} : codes;
  }

  final catalogIndex = CatalogIndex(catalogPath);

  if (!namesOnly) {
    print('=== Voice Catalog Tool ===');
    print('Catalog:     $catalogPath');
    if (doEval || recheckIds.isNotEmpty) {
      print('Models dir:  $modelsDir');
      print(
        'Fixtures:    ${fixturesDir ?? "(not found — ASR evaluation will fail)"}',
      );
      if (keep) print('Downloads:   retained (--keep)');
      if (debug) print('Debug:       enabled');
    }
    print('');
  }

  var entries = await catalogIndex.load();
  if (!namesOnly) {
    print('Loaded ${entries.length} existing entries');
    print('');
  }

  // Phase 1: Discover.
  if (doDiscover) {
    print('--- Phase 1: Discovery ---');
    final discovery = VoiceCatalogDiscovery(catalogIndex);
    entries = await discovery.discover(entries);
    await catalogIndex.save(entries);
    print('');
  }

  // Recheck: reset specified entries before filter/eval.
  if (recheckIds.isNotEmpty) {
    print('--- Recheck: resetting ${recheckIds.length} entries ---');
    for (final entry in entries) {
      if (recheckIds.contains(entry['id'] as String)) {
        entry['status'] = 'untested';
        entry['notes'] = '';
        entry['fileStructure'] = <String, String>{};
        print('  Reset: ${entry['id']}');
      }
    }
    await catalogIndex.save(entries);
    print('');
  }

  // Phase 2+3: Filter then Evaluate.
  if (doEval || recheckIds.isNotEmpty) {
    // Filter step only runs for pending (untested) entries.
    if (doEval && evalStatus == 'pending') {
      print('--- Phase 2: Filter ---');
      final filter = VoiceCatalogFilter();
      entries = filter.filter(entries);
      await catalogIndex.save(entries);
      print('');
    }

    print('--- Phase 3: Evaluate ---');
    if (fixturesDir == null) {
      stderr.writeln(
        'Warning: fixture WAV directory not found. '
        'Pass --fixtures-dir to enable ASR evaluation.',
      );
    }

    initSherpaOnnx(
      libDir: Platform.environment['VOICE_CATALOG_SHERPA_LIB_DIR'],
    );

    // When --recheck is used without --eval, limit evaluation to those IDs.
    final limitToIds = (!doEval && recheckIds.isNotEmpty) ? recheckIds : null;

    final downloader = ModelDownloadService(modelsDir);
    final evaluator = VoiceCatalogEvaluator(
      index: catalogIndex,
      downloader: downloader,
      fixtureDir: fixturesDir ?? Directory.systemTemp.path,
      keep: keep,
      debug: debug,
      limitToIds: limitToIds,
      typeFilter: typeFilter,
      languages: languages,
      evalStatus: evalStatus,
    );
    entries = await evaluator.evaluate(entries);
    print('');
  }

  final reporter = VoiceCatalogStatusReporter(languages: languages);
  if (!namesOnly && listState == null) reporter.report(entries);

  if (listState != null) {
    if (!namesOnly) {
      print('=== List: $listState ===');
      print('');
    }
    reporter.list(entries, listState, namesOnly: namesOnly, withNotes: withNotes, typeFilter: typeFilter);
  }

  exit(0);
}


String _usage(ArgParser parser) => '''
Usage: voice-catalog --discover [OPTIONS]
       voice-catalog --eval [pending|failed|approved] [OPTIONS]
       voice-catalog --status [OPTIONS]
       voice-catalog --list <ignored|pending|failed|approved> [OPTIONS]

Manage the Relagent voice-models.json catalog.

Phases (enabled with explicit flags):
  --discover  Fetch new model entries from GitHub releases and add them as
              untested. Runs before --eval when both flags are set.

  --eval      Download and smoke-test entries with the given status.
              Omitting the value defaults to --eval pending.
              pending   Apply filter criteria then test untested entries (default)
              failed    Re-test previously failed entries (skips filter step)
              approved  Re-test already-approved entries (skips filter step)
              Downloads are deleted after each test (use --keep to retain them).

              Filter criteria (pending only):
                • Size:         ≤ 1 GB download
                • Architecture: transducer | ctc | onlineNemoCtc |
                                vitsPiper | kokoro | offlineNemoTransducer
                • Piper quality: medium or higher (excludes _low / x_low models)

  --status    Print a two-column summary table (selected language filter vs all)
              showing discovered, ignored, pending, failed, approved
              and recommended counts. Also printed at the end of every run.

  --list      List entries matching a state (language filter applied).
              Combine with --status to see the table and the list together.
              Use --names-only to print just IDs for shell piping.

Options:
${parser.usage}

Examples:
  voice-catalog --status                Show catalog status for English (default)
  voice-catalog --status --lang en,de   Show status for English + German filter
  voice-catalog --status --lang all     Show status without language filter
  voice-catalog --list <ignored|pending|failed|approved>
  voice-catalog --list ignored          List ignored entries (English filter)
  voice-catalog --list pending          List untested candidates
  voice-catalog --list approved         List approved models
  voice-catalog --list ignored --lang all    List all ignored entries
  voice-catalog --list pending --type asr   List untested ASR models only
  voice-catalog --list approved --type tts  List approved TTS models only
  voice-catalog --list pending --names-only           IDs only, for piping
  voice-catalog --list failed --names-only --with-notes  IDs with notes, for review
  voice-catalog --list pending --names-only | grep kokoro
  voice-catalog --discover              Add new models from GitHub releases
  voice-catalog --discover              Creates voice-models.json if missing
  voice-catalog --eval                  Filter + test all untested models
  voice-catalog --eval failed           Re-test all failed models
  voice-catalog --eval approved         Re-test all previously approved models
  voice-catalog --discover --eval       Full pipeline: discover, filter, test
  voice-catalog --eval --keep           Test without deleting downloads
  voice-catalog --eval --lang en,de     Test English and German models
  voice-catalog --recheck kokoro-en-v0_19        Re-test a specific model
  voice-catalog --recheck <id> --debug           Re-test with full error details
  voice-catalog --catalog /path/voice-models.json --status
''';

/// Walk up to find `apps/assets/voice-models.json`.
String? _detectCatalogPath() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = File(
      p.join(dir.path, 'apps', 'assets', 'voice-models.json'),
    );
    if (candidate.existsSync()) return candidate.path;
    final direct = File(p.join(dir.path, 'assets', 'voice-models.json'));
    if (direct.existsSync()) return direct.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Walk up to find the `apps/assets/` (or `assets/`) directory.
/// Used by --discover to locate where to create voice-models.json.
String? _detectAssetsDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory(p.join(dir.path, 'apps', 'assets'));
    if (candidate.existsSync()) return candidate.path;
    final direct = Directory(p.join(dir.path, 'assets'));
    if (direct.existsSync()) return direct.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Walk up to find `tools/voice_catalog/fixtures/`.
String? _detectFixturesDir() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory(
      p.join(dir.path, 'tools', 'voice_catalog', 'fixtures'),
    );
    if (candidate.existsSync()) return candidate.path;
    final direct = Directory(
      p.join(dir.path, 'voice_catalog', 'fixtures'),
    );
    if (direct.existsSync()) return direct.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
