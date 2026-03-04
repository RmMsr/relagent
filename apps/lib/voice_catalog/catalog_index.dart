import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads and writes the voice-models.json file on disk.
///
/// The file is located at `assets/voice-models.json` relative to the
/// Flutter project root (the directory containing pubspec.yaml).
class CatalogIndex {
  final String filePath;

  CatalogIndex(this.filePath);

  /// Create using the standard asset path relative to [projectRoot].
  factory CatalogIndex.fromProjectRoot(String projectRoot) {
    return CatalogIndex(p.join(projectRoot, 'assets', 'voice-models.json'));
  }

  /// Load all entries from the JSON file.
  Future<List<Map<String, dynamic>>> load() async {
    final file = File(filePath);
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    final raw = jsonDecode(content) as List<dynamic>;
    return raw.cast<Map<String, dynamic>>();
  }

  /// Write all entries to the JSON file, pretty-printed with 2-space indent.
  Future<void> save(List<Map<String, dynamic>> entries) async {
    final file = File(filePath);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(entries)}\n');
  }
}
