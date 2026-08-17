import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '/models/imported_model.dart';
import '/voice/imported_model_registry.dart';
import '/voice/model_architecture_detector.dart';

class ArchivePeekResult {
  final List<String> entries;
  final ModelArchitecture? detectedArchitecture;
  final bool isAmbiguousShape;

  const ArchivePeekResult({
    required this.entries,
    required this.detectedArchitecture,
    required this.isAmbiguousShape,
  });
}

class ImportedModelService {
  static final _rng = Random.secure();

  static String _generateId() {
    final chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return 'imported-${List.generate(8, (_) => chars[_rng.nextInt(chars.length)]).join()}';
  }

  /// Read the archive's entry names without extracting.
  /// Returns the file list and a best-effort architecture detection.
  Future<ArchivePeekResult> peekArchive(File archive) async {
    final bytes = await archive.readAsBytes();
    final entries = await compute(_listArchiveEntries, bytes);
    return ArchivePeekResult(
      entries: entries,
      detectedArchitecture: detectArchitecture(entries),
      isAmbiguousShape: isAmbiguousTransducerShape(entries),
    );
  }

  /// Extract [archive] to the support directory and register the model.
  Future<void> importModel(File archive, ImportedModelEntry template) async {
    final id = _generateId();
    final destDir = await _modelDir(template.type, id);

    try {
      await compute(
        _extractArchive,
        _ExtractArgs(archivePath: archive.path, destPath: destDir.path),
      );
    } catch (e) {
      if (await destDir.exists()) await destDir.delete(recursive: true);
      rethrow;
    }

    final entry = ImportedModelEntry(
      id: id,
      displayName: template.displayName,
      type: template.type,
      architecture: template.architecture,
      languages: template.languages,
      importedAt: DateTime.now(),
    );

    await ImportedModelRegistry.add(entry);
  }

  /// Re-run architecture detection against an already-imported model's files
  /// on disk. Used by the edit sheet so a bad original guess (or a manual
  /// mis-pick at import time) doesn't get shown back as "auto-detected".
  Future<ArchivePeekResult> detectArchitectureForModel(
    ModelType type,
    String id,
  ) async {
    final dir = await _modelDir(type, id);
    if (!await dir.exists()) {
      return const ArchivePeekResult(
        entries: [],
        detectedArchitecture: null,
        isAmbiguousShape: false,
      );
    }
    final entries = await dir
        .list(recursive: true)
        .where((e) => e is File)
        .map((e) => p.relative(e.path, from: dir.path))
        .toList();
    return ArchivePeekResult(
      entries: entries,
      detectedArchitecture: detectArchitecture(entries),
      isAmbiguousShape: isAmbiguousTransducerShape(entries),
    );
  }

  /// Delete an imported model's files and manifest entry.
  Future<void> deleteModel(String id) async {
    final entry = ImportedModelRegistry.findById(id);
    if (entry == null) return;

    final dir = await _modelDir(entry.type, id);
    if (await dir.exists()) await dir.delete(recursive: true);

    await ImportedModelRegistry.remove(id);
  }

  Future<Directory> _modelDir(ModelType type, String id) async {
    final support = await getApplicationSupportDirectory();
    final typeDir = type == ModelType.asr ? 'asr' : 'tts';
    final dir = Directory(
      p.join(support.path, 'imported_models', typeDir, id),
    );
    await dir.create(recursive: true);
    return dir;
  }
}

// Top-level helpers for compute() isolation

/// Decode any supported archive format using magic-byte detection.
/// Supports: .tar.bz2, .tar.gz / .tgz, .zip, plain .tar.
Archive _decodeArchive(List<int> bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x50 && bytes[1] == 0x4B &&
      bytes[2] == 0x03 && bytes[3] == 0x04) {
    return ZipDecoder().decodeBytes(bytes);
  }
  final List<int> decompressed;
  if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
    decompressed = GZipDecoder().decodeBytes(bytes);
  } else if (bytes.length >= 3 &&
      bytes[0] == 0x42 && bytes[1] == 0x5A && bytes[2] == 0x68) {
    decompressed = BZip2Decoder().decodeBytes(bytes);
  } else {
    decompressed = bytes; // plain tar
  }
  return TarDecoder().decodeBytes(decompressed);
}

List<String> _listArchiveEntries(Uint8List bytes) {
  try {
    return _decodeArchive(bytes).map((f) => f.name).toList();
  } catch (_) {
    return [];
  }
}

class _ExtractArgs {
  final String archivePath;
  final String destPath;
  const _ExtractArgs({required this.archivePath, required this.destPath});
}

Future<void> _extractArchive(_ExtractArgs args) async {
  final file = File(args.archivePath);
  final bytes = await file.readAsBytes();

  final archive = _decodeArchive(bytes);
  final prefix = _topLevelPrefix(archive);

  await Directory(args.destPath).create(recursive: true);

  for (final entry in archive) {
    if (!entry.isFile) continue;
    var path = entry.name;
    if (prefix != null && path.startsWith(prefix)) {
      path = path.substring(prefix.length);
    }
    if (path.isEmpty) continue;

    final outFile = File(p.join(args.destPath, path));
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(entry.content as List<int>);
  }

  await File(p.join(args.destPath, '.complete'))
      .writeAsString(DateTime.now().toIso8601String());
}

String? _topLevelPrefix(Archive archive) {
  if (archive.isEmpty) return null;
  final firstName = archive.first.name;
  final slashIndex = firstName.indexOf('/');
  if (slashIndex < 0) return null;
  final prefix = firstName.substring(0, slashIndex + 1);
  for (final f in archive) {
    if (!f.name.startsWith(prefix)) return null;
  }
  return prefix;
}
