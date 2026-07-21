import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '/models/imported_model.dart';

class ImportedModelRegistry {
  static const _manifestFileName = 'imported_models.json';

  static List<ImportedModelEntry> _entries = [];

  static List<ImportedModelEntry> get entries => List.unmodifiable(_entries);

  /// Runs before runApp(), so it must never throw. Without local storage
  /// (web) the app just has no imported models.
  static Future<void> init() async {
    if (kIsWeb) {
      _entries = [];
      return;
    }
    try {
      final file = await _manifestFile();
      if (!await file.exists()) {
        _entries = [];
        return;
      }
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      _entries = raw
          .cast<Map<String, dynamic>>()
          .expand((e) {
            try {
              return [ImportedModelEntry.fromJson(e)];
            } catch (_) {
              return <ImportedModelEntry>[];
            }
          })
          .toList();
    } catch (_) {
      _entries = [];
    }
  }

  static List<ImportedModelEntry> byType(ModelType type) {
    return _entries.where((e) => e.type == type).toList()
      ..sort(_newestFirst);
  }

  static List<ImportedModelEntry> byTypeAndLanguage(
    ModelType type,
    String languageCode,
  ) {
    return _entries
        .where((e) => e.type == type && e.languages.contains(languageCode))
        .toList()
      ..sort(_newestFirst);
  }

  static ImportedModelEntry? findById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  static Future<void> add(ImportedModelEntry entry) async {
    _entries = [..._entries, entry];
    await _persist();
  }

  static Future<void> remove(String id) async {
    _entries = _entries.where((e) => e.id != id).toList();
    await _persist();
  }

  static Future<void> update(ImportedModelEntry entry) async {
    _entries = [
      for (final e in _entries) e.id == entry.id ? entry : e,
    ];
    await _persist();
  }

  static Future<File> _manifestFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, _manifestFileName));
  }

  static Future<void> _persist() async {
    final file = await _manifestFile();
    await file.writeAsString(
      jsonEncode(_entries.map((e) => e.toJson()).toList()),
    );
  }

  static int _newestFirst(ImportedModelEntry a, ImportedModelEntry b) =>
      b.importedAt.compareTo(a.importedAt);
}
