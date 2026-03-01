import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '/models/model_catalog.dart';
import '/utils/logger.dart';

/// Progress information for an active download.
class DownloadProgress {
  final String modelId;
  final int bytesReceived;
  final int totalBytes;

  const DownloadProgress({
    required this.modelId,
    required this.bytesReceived,
    required this.totalBytes,
  });

  double get fraction => totalBytes > 0 ? bytesReceived / totalBytes : 0;

  int get percent => (fraction * 100).round();
}

/// Service for downloading, extracting, and managing voice model archives.
class ModelDownloadService {
  static const _modelsSubdir = 'models';
  static const _completeMarker = '.complete';

  http.Client? _activeClient;
  String? _activeModelId;

  /// Get the base directory for all downloaded models.
  Future<Directory> _modelsBaseDir() async {
    final cacheDir = await getApplicationCacheDirectory();
    return Directory(p.join(cacheDir.path, _modelsSubdir));
  }

  /// Get the storage directory for a specific model.
  Future<Directory> _modelDir(CatalogEntry entry) async {
    final base = await _modelsBaseDir();
    final typeDir = entry.type == ModelType.asr ? 'asr' : 'tts';
    return Directory(p.join(base.path, typeDir, entry.id));
  }

  /// Download and extract a model archive.
  ///
  /// Reports progress via [onProgress]. Can be cancelled via [cancelDownload].
  Future<void> downloadModel(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final dir = await _modelDir(entry);

    // Clean up incomplete previous attempt
    if (await dir.exists()) {
      final marker = File(p.join(dir.path, _completeMarker));
      if (!await marker.exists()) {
        Logger.info('Cleaning up incomplete download for ${entry.id}');
        await dir.delete(recursive: true);
      } else {
        Logger.info('Model ${entry.id} already downloaded');
        return;
      }
    }

    // Download to temp file
    final tempFile = await _download(entry, onProgress: onProgress);
    if (tempFile == null) return; // Cancelled

    try {
      // Extract archive
      await _extract(tempFile, entry);
    } finally {
      // Clean up temp file
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  /// Download the archive to a temporary file, returning null if cancelled.
  Future<File?> _download(
    CatalogEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    final client = http.Client();
    _activeClient = client;
    _activeModelId = entry.id;

    try {
      final request = http.Request('GET', Uri.parse(entry.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode}',
          uri: Uri.parse(entry.downloadUrl),
        );
      }

      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, '${entry.id}.tar.bz2'));

      final sink = tempFile.openWrite();
      var bytesReceived = 0;

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          onProgress?.call(
            DownloadProgress(
              modelId: entry.id,
              bytesReceived: bytesReceived,
              totalBytes: totalBytes,
            ),
          );
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        if (await tempFile.exists()) await tempFile.delete();
        rethrow;
      }

      Logger.info('Downloaded ${entry.id}: $bytesReceived bytes');
      return tempFile;
    } on http.ClientException {
      // Client was closed (cancellation)
      Logger.info('Download cancelled for ${entry.id}');
      return null;
    } finally {
      _activeClient = null;
      _activeModelId = null;
    }
  }

  /// Extract a .tar.bz2 archive to the model directory.
  Future<void> _extract(File archiveFile, CatalogEntry entry) async {
    Logger.info('Extracting ${entry.id}...');

    final dir = await _modelDir(entry);
    await dir.create(recursive: true);

    final bytes = await archiveFile.readAsBytes();
    final decompressed = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decompressed);

    // Sherpa-onnx archives typically have a top-level directory.
    // We strip it so files go directly into our model directory.
    final topLevelPrefix = _findTopLevelPrefix(archive);
    Logger.debug('Archive prefix to strip: $topLevelPrefix');

    for (final file in archive) {
      if (file.isFile) {
        var filePath = file.name;
        if (topLevelPrefix != null && filePath.startsWith(topLevelPrefix)) {
          filePath = filePath.substring(topLevelPrefix.length);
        }
        if (filePath.isEmpty) continue;

        Logger.debug('Extracting: $filePath');
        final outFile = File(p.join(dir.path, filePath));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
      }
    }

    // Write completion marker
    final marker = File(p.join(dir.path, _completeMarker));
    await marker.writeAsString(DateTime.now().toIso8601String());

    Logger.info('Extracted ${entry.id} to ${dir.path}');
  }

  /// Find the common top-level directory prefix in a tar archive.
  String? _findTopLevelPrefix(Archive archive) {
    if (archive.isEmpty) return null;

    // Log first few entries for debugging
    final sampleEntries = archive.take(5).map((f) => f.name).toList();
    Logger.debug('Archive entries (first 5): $sampleEntries');

    final firstName = archive.first.name;
    final slashIndex = firstName.indexOf('/');
    if (slashIndex < 0) return null;

    final prefix = firstName.substring(0, slashIndex + 1);

    // Check if all entries share this prefix
    for (final file in archive) {
      if (!file.name.startsWith(prefix)) return null;
    }

    return prefix;
  }

  /// Cancel an active download.
  void cancelDownload(String modelId) {
    if (_activeModelId == modelId && _activeClient != null) {
      Logger.info('Cancelling download for $modelId');
      _activeClient!.close();
      _activeClient = null;
      _activeModelId = null;
    }
  }

  /// List all fully downloaded model IDs.
  Future<Set<String>> listDownloadedModels() async {
    final base = await _modelsBaseDir();
    if (!await base.exists()) return {};

    final downloaded = <String>{};

    for (final typeDir in ['asr', 'tts']) {
      final dir = Directory(p.join(base.path, typeDir));
      if (!await dir.exists()) continue;

      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final marker = File(p.join(entity.path, _completeMarker));
          if (await marker.exists()) {
            downloaded.add(p.basename(entity.path));
          }
        }
      }
    }

    return downloaded;
  }

  /// Check if a specific model is downloaded and complete.
  Future<bool> isModelDownloaded(String modelId) async {
    final entry = ModelCatalog.findById(modelId);
    if (entry == null) return false;

    final dir = await _modelDir(entry);
    final marker = File(p.join(dir.path, _completeMarker));
    return marker.exists();
  }

  /// Get the file system path for a downloaded model directory.
  Future<String> getModelPath(CatalogEntry entry) async {
    final dir = await _modelDir(entry);
    return dir.path;
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String modelId) async {
    final entry = ModelCatalog.findById(modelId);
    if (entry == null) return;

    final dir = await _modelDir(entry);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      Logger.info('Deleted model $modelId');
    }
  }

  /// Calculate total disk space used by all downloaded models in bytes.
  Future<int> totalStorageUsed() async {
    final base = await _modelsBaseDir();
    if (!await base.exists()) return 0;

    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
