// ignore_for_file: avoid_print
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sherpa_voice/model_archive.dart';

/// Downloads and extracts voice model archives to a local directory.
///
/// Models are stored at `<modelsBaseDir>/<type>/<id>/`.
/// A `.complete` marker is written after successful extraction.
class ModelDownloadService {
  final String modelsBaseDir;

  ModelDownloadService(this.modelsBaseDir);

  String modelDir(String type, String id) =>
      p.join(modelsBaseDir, type, id);

  bool isDownloaded(String type, String id) {
    final marker = File(p.join(modelDir(type, id), '.complete'));
    return marker.existsSync();
  }

  /// Download and extract a model. Returns the extracted directory path.
  Future<String> downloadModel(
    String type,
    String id,
    String downloadUrl, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = modelDir(type, id);

    if (isDownloaded(type, id)) {
      print('[Download] Already in cache, skipping download');
      return dir;
    }

    // Clean up any incomplete previous attempt.
    final dirObj = Directory(dir);
    if (await dirObj.exists()) await dirObj.delete(recursive: true);

    print('[Download] Downloading...');
    final tempFile = await _download(id, downloadUrl, onProgress: onProgress);

    try {
      await _extract(tempFile, dir);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }

    return dir;
  }

  /// Delete a downloaded model directory.
  Future<void> deleteModel(String type, String id) async {
    final dir = Directory(modelDir(type, id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      print('[Download] Deleted from cache');
    }
  }

  Future<File> _download(
    String id,
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }

      final total = response.contentLength ?? 0;
      final tempFile = File(p.join(
        Directory.systemTemp.path,
        '$id-${DateTime.now().millisecondsSinceEpoch}.tar.bz2',
      ));
      final sink = tempFile.openWrite();
      var received = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        if (await tempFile.exists()) await tempFile.delete();
        rethrow;
      }

      return tempFile;
    } finally {
      client.close();
    }
  }

  Future<void> _extract(File archiveFile, String destDir) async {
    await extractModelArchive(archiveFile, destDir);
    print('[Download] Extracted to $destDir');
  }
}
