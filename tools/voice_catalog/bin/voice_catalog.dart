// ignore_for_file: avoid_print
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../lib/catalog_index.dart';
import '../lib/discovery.dart';
import '../lib/download_service.dart';
import '../lib/entry_scope.dart';
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
    ..addMultiOption(
      'arch',
      help:
          'Architecture values to include (repeat or comma-separate)\n'
          'See --list-architectures for valid values\n'
          '(default: all)',
      valueHelp: 'ARCH',
    )
    ..addOption(
      'catalog',
      abbr: 'c',
      help:
          'Path to voice-models.json\n'
          '(default: auto-detected from project root)',
      valueHelp: 'FILE',
    )
    ..addFlag(
      'classify',
      negatable: false,
      hide: true, // documented under "Phase 2" above
      help:
          'Re-derive names/architecture and exclusion notes (see Phase 2).\n'
          'Rare to need directly — implicit on --discover and --recheck.',
    )
    ..addFlag(
      'debug',
      negatable: false,
      help: 'Print stack traces and file inspection details during eval',
    )
    ..addFlag(
      'discover',
      negatable: false,
      hide: true, // documented under "Phase 1" above
      help: 'Fetch new model entries from GitHub releases',
    )
    ..addOption(
      'eval',
      hide: true, // documented under "Phase 3" above
      help:
          'Download and smoke-test entries with the given status\n'
          '(bare --eval defaults to pending)',
      valueHelp: 'STATUS',
      allowed: ['pending', 'failed', 'approved'],
    )
    ..addOption(
      'fixtures-dir',
      help:
          'Directory with reference WAV clips (en.wav, de.wav, …)\n'
          '(default: auto-detected from project root)',
      valueHelp: 'DIR',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help')
    ..addFlag(
      'keep',
      negatable: false,
      help: 'Keep downloaded model files after evaluation (skip auto-delete)',
    )
    ..addMultiOption(
      'lang',
      abbr: 'l',
      help:
          'Language codes to include (repeat or comma-separate)\n'
          'Use "all" to disable the language filter\n'
          '(default: en)',
      valueHelp: 'LANG',
    )
    ..addOption(
      'list',
      hide: true, // documented under "Informational" above
      help:
          'List entries matching a state (with language filter applied)\n'
          'States: ignored, pending, failed, approved',
      valueHelp: 'STATE',
      defaultsTo: 'approved',
      allowed: ['ignored', 'pending', 'failed', 'approved'],
    )
    ..addFlag(
      'list-architectures',
      negatable: false,
      hide: true, // documented under "Informational" above
      help:
          'Print catalog architectures: type, runtime-supported,\n'
          'approved/total. Whole catalog, not scoped.',
    )
    ..addFlag(
      'names-only',
      negatable: false,
      help: 'With --list: print only IDs, one per line (for shell piping)',
    )
    ..addMultiOption(
      'recheck',
      hide: true, // documented under "Phase 3" above
      help:
          'Reset and re-evaluate a specific model by ID\n'
          '(clears its status and notes, implies eval for those entries)',
      valueHelp: 'ID',
    )
    ..addFlag(
      'status',
      negatable: false,
      hide: true, // documented under "Informational" above
      help: 'Print catalog status summary (also shown after --discover/--eval)',
    )
    ..addOption(
      'type',
      abbr: 't',
      help: 'Filter by model type (default: all)',
      valueHelp: 'TYPE',
      allowed: ['asr', 'tts'],
    )
    ..addFlag(
      'with-notes',
      negatable: false,
      help: 'With --names-only: append notes as (note) after each ID',
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
  final doClassify = parsed['classify'] as bool;
  final doListArchitectures = parsed['list-architectures'] as bool;
  final doEval = parsed.wasParsed('eval');
  final evalStatus = parsed['eval'] as String? ?? 'pending';
  final doStatus = parsed['status'] as bool;
  final listState = parsed.wasParsed('list') ? parsed['list'] as String : null;
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
      (!doDiscover &&
          !doClassify &&
          !doListArchitectures &&
          !doEval &&
          !doStatus &&
          listState == null &&
          recheckIds.isEmpty)) {
    print(_usage(parser));
    exit(0);
  }

  // --list-architectures always covers the whole catalog (see its doc) —
  // don't print a scope line for a scope it doesn't apply.
  final scopeApplies =
      doDiscover ||
      doClassify ||
      doEval ||
      doStatus ||
      listState != null ||
      recheckIds.isNotEmpty;

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
  final cacheBase =
      Platform.environment['XDG_CACHE_HOME'] ??
      p.join(
        Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '/tmp',
        '.cache',
      );
  final modelsDir = p.join(cacheBase, 'relagent', 'models');

  // Resolve fixtures directory.
  final fixturesDir = parsed['fixtures-dir'] as String? ?? _detectFixturesDir();

  final keep = parsed['keep'] as bool;

  // Resolve language filter (default: en; --lang all → no filter).
  final langArgs = parsed['lang'] as List<String>;
  final Set<String> languages;
  if (langArgs.isEmpty) {
    languages = {'en'};
  } else {
    final codes = langArgs
        .expand((s) => s.split(','))
        .map((s) => s.trim())
        .toSet();
    languages = codes.contains('all') ? {} : codes;
  }

  // Resolve architecture filter (default: all).
  final archArgs = parsed['arch'] as List<String>;
  final architectures = archArgs
      .expand((s) => s.split(','))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s != 'all')
      .toSet();

  // Single scope applied consistently across every command below.
  final scope = EntryScope(
    type: typeFilter,
    languages: languages,
    architectures: architectures,
  );

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
    if (scopeApplies) {
      print('Scope:');
      for (final line in scope.describeLines()) {
        print('  $line');
      }
    }
    print('');
  }

  // Phase 1: Discover.
  if (doDiscover) {
    print('--- Phase 1: Discover ---');
    final discovery = VoiceCatalogDiscovery(catalogIndex);
    entries = await discovery.discover(entries, scope: scope);
    await catalogIndex.save(entries);
    print('');
  }

  // Recheck: reset specific entries back to untested before classify/eval.
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

  // Phase 2: Classify (optional, but always runs after --discover/--recheck).
  // Re-derives displayName/architecture/origin/sourceUrl and the exclusion
  // verdict (notes) for every untested entry in scope — free, no network or
  // download involved. Runs automatically after --discover (the action
  // where catalog-wide changes are expected) and after --recheck (so a
  // rechecked entry that should still be excluded doesn't slip past --eval
  // with a stale/cleared note); available standalone via --classify to pick
  // up a parser/filter code change without touching the network.
  if (doClassify || doDiscover || recheckIds.isNotEmpty) {
    print('--- Phase 2: Classify ---');
    final discovery = VoiceCatalogDiscovery(catalogIndex);
    final changed = discovery.classify(entries, scope: scope);
    final filter = VoiceCatalogFilter();
    entries = filter.filter(entries, scope: scope);
    await catalogIndex.save(entries);
    print('[Classify] Re-derived $changed entries');
    print('');
  }

  // Phase 3: Evaluate.
  if (doEval || recheckIds.isNotEmpty) {
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
      scope: scope,
      evalStatus: evalStatus,
    );
    entries = await evaluator.evaluate(entries);
    print('');
  }

  final reporter = VoiceCatalogStatusReporter(scope: scope);
  if (!namesOnly && listState == null && !doListArchitectures) {
    reporter.report(entries);
  }

  if (listState != null) {
    if (!namesOnly) {
      print('=== List: $listState ===');
      print('');
    }
    reporter.list(
      entries,
      listState,
      namesOnly: namesOnly,
      withNotes: withNotes,
    );
  }

  if (doListArchitectures) {
    reporter.listArchitectures(entries);
  }

  exit(0);
}

String _usage(ArgParser parser) =>
    '''
Usage: voice-catalog --discover [OPTIONS]
       voice-catalog --eval [pending|failed|approved] [OPTIONS]
       voice-catalog --status [OPTIONS]
       voice-catalog --list <ignored|pending|failed|approved> [OPTIONS]

Manage the Relagent voice-models.json catalog.

Phase 1
  --discover  Fetch new entries from GitHub releases. Implies Classify.

Phase 2 (optional) — implicit on --discover and --recheck
  --classify  Re-derive names/architecture/origin/sourceUrl and the
              exclusion verdict (notes) for untested entries in scope.
              No network/download. Skips entries already evaluated.

              Exclusion criteria:
                • Size:         ≤ 1 GB download
                • Architecture: transducer | ctc | onlineNemoCtc | vitsPiper |
                                kokoro | offlineNemoTransducer | pocket | unknown
                • Piper quality: medium or higher (excludes _low / x_low)
                • float32 skipped when an int8 sibling id exists

Phase 3
  --eval      Download and smoke-test entries by status.
              pending|failed|approved (default: pending)
  --recheck   Reset entries to untested by ID. Implies Classify + Eval
              for just those IDs.

Informational
  --status              Summary table: scope vs. all languages.
  --list                List entries by state: ignored|pending|failed|approved
  --list-architectures  Architecture, type, runtime-supported, approved/
                         total. Whole catalog, not scoped.

Options:
${parser.usage}

Examples:
  voice-catalog --discover              Add new entries from GitHub releases
  voice-catalog --eval                  Test all untested, non-excluded models
  voice-catalog --eval failed           Re-test all failed models
  voice-catalog --eval approved         Re-test all previously approved models
  voice-catalog --eval --keep           Test without deleting downloads
  voice-catalog --eval --lang en,de     Test English and German models
  voice-catalog --recheck <id>          Re-classify + re-test one model
  voice-catalog --status                Catalog status for English (default)
  voice-catalog --status --lang all     Catalog status, all languages
  voice-catalog --list ignored          List ignored entries
  voice-catalog --list pending          List untested candidates
  voice-catalog --list failed           List failed entries
  voice-catalog --list approved         List approved models
  voice-catalog --list pending --names-only | grep kokoro
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
    final direct = Directory(p.join(dir.path, 'voice_catalog', 'fixtures'));
    if (direct.existsSync()) return direct.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
