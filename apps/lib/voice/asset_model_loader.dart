import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import '/utils/logger.dart';
import '/voice/model_loader.dart';

/// Loads models from bundled Flutter assets by copying them to the cache directory.
class AssetModelLoader implements ModelLoader {
  @override
  Future<bool> isModelAvailable(String modelName) async {
    try {
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = assetManifest.listAssets().where(
        (key) => key.startsWith('assets/$modelName/'),
      );
      return assets.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> loadModel(String modelName) async {
    final Directory cacheDirectory = await getApplicationCacheDirectory();
    return join(cacheDirectory.path, modelName);
  }

  @override
  Future<String> loadModelFile(String modelName, String fileName) async {
    final src = '$modelName/$fileName';
    final Directory directory = await getApplicationCacheDirectory();
    final target = join(directory.path, src);
    final targetFile = File(target);
    bool exists = await targetFile.exists();

    if (exists) {
      final actualSize = await targetFile.length();
      Logger.debug('Cached file $src exists: $actualSize bytes at $target');

      if (actualSize > 0) {
        try {
          final data = await rootBundle.load('assets/$src');
          final expectedSize = data.lengthInBytes;

          if (actualSize == expectedSize) {
            Logger.debug('Cached file $src verified ($actualSize bytes)');
            return target;
          } else {
            Logger.debug(
              'Cached file $src is incomplete ($actualSize bytes vs $expectedSize expected), re-copying...',
            );
          }
        } catch (e) {
          Logger.debug(
            'Cached file $src (background isolate, size: $actualSize bytes)',
          );
          return target;
        }
      } else {
        Logger.debug('Cached file $src is empty (0 bytes), re-copying...');
      }
    }

    final data = await rootBundle.load('assets/$src');

    final parentDir = targetFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final List<int> bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    await targetFile.writeAsBytes(bytes);

    return target;
  }

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) async {
    final assetDir = '$modelName/$dirName';
    final Directory cacheDirectory = await getApplicationCacheDirectory();
    final targetDir = join(cacheDirectory.path, assetDir);

    final dir = Directory(targetDir);
    await dir.create(recursive: true);

    final markerFile = File(join(targetDir, '.copied'));
    if (await markerFile.exists()) {
      Logger.debug('Directory $targetDir already copied, skipping');
      return targetDir;
    }

    Logger.debug('Copying asset directory $assetDir to $targetDir');

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetPaths = assetManifest
        .listAssets()
        .where((String key) => key.startsWith('assets/$assetDir/'))
        .toList();

    Logger.debug('Found ${assetPaths.length} assets in $assetDir');

    int copiedCount = 0;
    for (final assetPath in assetPaths) {
      try {
        final data = await rootBundle.load(assetPath);
        final relativePath = assetPath.substring('assets/$assetDir/'.length);
        final targetPath = join(targetDir, relativePath);

        final targetFile = File(targetPath);
        final parentDir = targetFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }

        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        await targetFile.writeAsBytes(bytes);
        copiedCount++;
      } catch (e) {
        Logger.debug('Failed to copy $assetPath: $e');
        continue;
      }
    }

    Logger.debug('Copied $copiedCount files from $assetDir');

    await markerFile.writeAsString('copied');

    return targetDir;
  }
}
