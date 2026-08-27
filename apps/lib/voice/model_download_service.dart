import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_voice/model_archive.dart';

import '/models/model_catalog.dart';
import '/utils/logger.dart';

/// Progress information for an active download.
class DownloadProgress {
  final String modelId;
  final int bytesReceived;
  final int totalBytes;

  /// True while the archive is being extracted after the HTTP download
  /// completes. During this phase there is no byte progress to show.
  final bool isExtracting;

  const DownloadProgress({
    required this.modelId,
    required this.bytesReceived,
    required this.totalBytes,
    this.isExtracting = false,
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
  ///
  /// Application support storage, not cache: the OS purges the cache dir
  /// under storage pressure, which would silently delete downloaded models.
  Future<Directory> _modelsBaseDir() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory(p.join(supportDir.path, _modelsSubdir));
  }

  /// Same as [_modelsBaseDir], but null when local storage is unavailable
  /// (web). Scans run at startup and must not throw.
  Future<Directory?> _scannableBaseDir() async {
    if (kIsWeb) return null;
    try {
      return await _modelsBaseDir();
    } catch (_) {
      return null;
    }
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
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, '${entry.id}.tar.bz2'));
      var existingBytes = await tempFile.exists() ? await tempFile.length() : 0;

      var response = await client.send(_buildRequest(entry, existingBytes));

      if (existingBytes > 0 && response.statusCode != 206) {
        // The server ignored our Range request (or the partial file no
        // longer matches what it would serve) — drop it and start over
        // instead of appending onto or corrupting the archive.
        Logger.info('Resume not honored for ${entry.id}; restarting download');
        if (await tempFile.exists()) await tempFile.delete();
        existingBytes = 0;
        response = await client.send(_buildRequest(entry, existingBytes));
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw HttpException(
          'Download failed: HTTP ${response.statusCode}',
          uri: Uri.parse(entry.downloadUrl),
        );
      }

      final isResuming = existingBytes > 0 && response.statusCode == 206;
      // existingBytes is 0 whenever isResuming is false, so this covers both
      // a fresh download and a resumed one.
      final totalBytes = existingBytes + (response.contentLength ?? 0);
      final sink = tempFile.openWrite(
        mode: isResuming ? FileMode.append : FileMode.write,
      );
      var bytesReceived = existingBytes;

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
        // Keep the partial file on disk so the next attempt can resume
        // instead of redownloading a possibly multi-minute transfer from
        // scratch — this can't distinguish a cancellation from a genuine
        // failure, but resuming is safe either way.
        rethrow;
      }

      Logger.info('Downloaded ${entry.id}: $bytesReceived bytes');
      return tempFile;
    } on http.ClientException {
      // cancelDownload() nulls _activeClient before calling client.close(),
      // so by the time that close() surfaces here as a ClientException,
      // _activeClient is already null only for a deliberate cancellation.
      // A dropped connection (e.g. a flaky mobile network mid-download)
      // throws this same exception type but leaves _activeClient set, so it
      // must be treated as a real failure, not swallowed as a no-op.
      if (_activeClient == null) {
        Logger.info('Download cancelled for ${entry.id}');
        return null;
      }
      rethrow;
    } finally {
      _activeClient = null;
      _activeModelId = null;
    }
  }

  /// Builds the GET request for a download, adding a Range header to
  /// continue from [existingBytes] when resuming a partial download.
  http.Request _buildRequest(CatalogEntry entry, int existingBytes) {
    final request = http.Request('GET', Uri.parse(entry.downloadUrl));
    if (existingBytes > 0) {
      request.headers['Range'] = 'bytes=$existingBytes-';
    }
    return request;
  }

  /// Extract a .tar.bz2 archive to the model directory.
  Future<void> _extract(File archiveFile, CatalogEntry entry) async {
    Logger.info('Extracting ${entry.id}...');
    final dir = await _modelDir(entry);
    await extractModelArchive(archiveFile, dir.path);
    Logger.info('Extracted ${entry.id} to ${dir.path}');
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
    final base = await _scannableBaseDir();
    if (base == null || !await base.exists()) return {};

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
    final base = await _scannableBaseDir();
    if (base == null || !await base.exists()) return 0;

    var total = 0;
    await for (final entity in base.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }
}
