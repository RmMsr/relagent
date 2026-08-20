import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Extract a sherpa-onnx `.tar.bz2` archive to [destDir].
///
/// Sherpa-onnx archives conventionally contain a single top-level directory
/// named after the model. That prefix is stripped so files land directly
/// under [destDir]. Writes a `.complete` marker after successful extraction.
Future<void> extractModelArchive(File archiveFile, String destDir) async {
  await Directory(destDir).create(recursive: true);

  final bytes = await archiveFile.readAsBytes();
  final decompressed = BZip2Decoder().decodeBytes(bytes);
  final archive = TarDecoder().decodeBytes(decompressed);

  final prefix = _topLevelPrefix(archive);

  for (final file in archive) {
    if (!file.isFile) continue;
    var path = file.name;
    if (prefix != null && path.startsWith(prefix)) {
      path = path.substring(prefix.length);
    }
    if (path.isEmpty) continue;

    final outFile = File(p.join(destDir, path));
    await outFile.parent.create(recursive: true);
    await outFile.writeAsBytes(file.content as List<int>);
  }

  await File(
    p.join(destDir, '.complete'),
  ).writeAsString(DateTime.now().toIso8601String());
}

/// Find the common top-level directory prefix shared by all archive entries,
/// or null if entries don't share a single prefix.
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
