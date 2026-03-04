import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '/models/model_catalog.dart';
import '/utils/logger.dart';
import 'package:sherpa_voice/model_loader.dart';

/// Loads models from the cache storage directory (re-downloadable).
///
/// Models are stored at `<cache_dir>/models/<type>/<model-id>/`.
class DownloadModelLoader implements ModelLoader {
  final CatalogEntry _entry;

  DownloadModelLoader(this._entry);

  Future<String> _modelBasePath() async {
    final cacheDir = await getApplicationCacheDirectory();
    final typeDir = _entry.type == ModelType.asr ? 'asr' : 'tts';
    return p.join(cacheDir.path, 'models', typeDir, _entry.id);
  }

  @override
  Future<String> loadModel(String modelName) async {
    final basePath = await _modelBasePath();
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      throw StateError(
        'Model ${_entry.id} not downloaded. Please download it first.',
      );
    }
    return basePath;
  }

  @override
  Future<String> loadModelFile(String modelName, String fileName) async {
    final basePath = await _modelBasePath();
    final filePath = p.join(basePath, fileName);
    final file = File(filePath);
    if (!await file.exists()) {
      // List directory contents to aid debugging
      final dir = Directory(basePath);
      if (await dir.exists()) {
        final contents = await dir.list(recursive: true).map((e) {
          final rel = p.relative(e.path, from: basePath);
          return '${e is Directory ? "d" : "f"} $rel';
        }).toList();
        Logger.debug('Model dir contents for ${_entry.id}: $contents');
      } else {
        Logger.debug('Model dir does not exist: $basePath');
      }
      throw StateError(
        'Model file $fileName not found for ${_entry.id}. '
        'The model may need to be re-downloaded.',
      );
    }
    return filePath;
  }

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) async {
    final basePath = await _modelBasePath();
    final dirPath = p.join(basePath, dirName);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      // List top-level contents to aid debugging
      final baseDir = Directory(basePath);
      if (await baseDir.exists()) {
        final contents = await baseDir.list().map((e) {
          final rel = p.relative(e.path, from: basePath);
          return '${e is Directory ? "d" : "f"} $rel';
        }).toList();
        Logger.debug('Model dir contents for ${_entry.id}: $contents');
      }
      throw StateError(
        'Model directory $dirName not found for ${_entry.id}. '
        'The model may need to be re-downloaded.',
      );
    }
    return dirPath;
  }

  @override
  Future<bool> isModelAvailable(String modelName) async {
    final basePath = await _modelBasePath();
    final marker = File(p.join(basePath, '.complete'));
    return marker.exists();
  }
}
