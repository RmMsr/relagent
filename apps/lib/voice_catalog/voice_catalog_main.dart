// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'catalog_index.dart';
import 'discovery.dart';
import 'evaluator.dart';
import 'filter.dart';

/// Voice Catalog tool — developer CLI for managing voice-models.json.
///
/// Run from the apps/ directory:
///   fvm flutter run -d linux -t lib/voice_catalog/voice_catalog_main.dart
///
/// Phases:
///   1. Discover — fetch new sherpa-onnx model assets from GitHub
///   2. Filter  — skip entries that fail hard project criteria
///   3. Evaluate — download + smoke-test untested entries that pass the filter
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve project root: the directory containing pubspec.yaml.
  // When running via `flutter run`, the CWD is the Flutter project root (apps/).
  final projectRoot = _findProjectRoot();
  if (projectRoot == null) {
    stderr.writeln('Error: Cannot find project root (pubspec.yaml not found)');
    exit(1);
  }

  final fixtureDir = p.join(
    projectRoot,
    'lib',
    'voice_catalog',
    'fixtures',
  );
  final catalogIndexFile = CatalogIndex.fromProjectRoot(projectRoot);

  print('=== Voice Catalog Tool ===');
  print('Project root: $projectRoot');
  print('Catalog: ${catalogIndexFile.filePath}');
  print('');

  // Load current catalog.
  var entries = await catalogIndexFile.load();
  print('Loaded ${entries.length} existing entries');
  print('');

  // Phase 1: Discover
  print('--- Phase 1: Discovery ---');
  final discovery = VoiceCatalogDiscovery(catalogIndexFile);
  entries = await discovery.discover(entries);
  await catalogIndexFile.save(entries);
  print('');

  // Phase 2: Filter
  print('--- Phase 2: Filter ---');
  final filter = VoiceCatalogFilter();
  entries = filter.filter(entries);
  await catalogIndexFile.save(entries);
  print('');

  // Phase 3: Evaluate
  print('--- Phase 3: Evaluate ---');
  final evaluator = VoiceCatalogEvaluator(
    index: catalogIndexFile,
    fixtureDir: fixtureDir,
  );
  entries = await evaluator.evaluate(entries);
  print('');

  // Summary
  final approved = entries.where((e) => e['status'] == 'approved').length;
  final untested = entries.where((e) => e['status'] == 'untested').length;
  final excluded = entries
      .where((e) => (e['notes'] as String? ?? '').startsWith('excluded:'))
      .length;

  print('=== Summary ===');
  print('Total entries: ${entries.length}');
  print('  Approved:  $approved');
  print('  Untested:  $untested (review notes, promote to approved if OK)');
  print('  Excluded:  $excluded (did not meet filter criteria)');
  print('');
  print('Catalog written to: ${catalogIndexFile.filePath}');
  print('Review the output, promote passing entries to approved, then commit.');

  exit(0);
}

/// Walk up from the current directory to find the Flutter project root.
String? _findProjectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}
