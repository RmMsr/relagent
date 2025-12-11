// Contains code from sherpa-onnx. Copyright (c) 2024  Xiaomi Corporation
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

Future<String> copyAssetFileToCache(String src, [String? dst]) async {
  final Directory directory = await getApplicationCacheDirectory();
  final target = join(directory.path, src);
  final targetFile = File(target);
  bool exists = await targetFile.exists();

  // If file already exists in cache, return path without accessing assets
  // This allows background isolates to use cached files
  if (exists) {
    return target;
  }

  // File doesn't exist, need to copy from assets (requires main isolate)
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

Future<String> copyAssetDirectoryToCache(String assetDir) async {
  final Directory cacheDirectory = await getApplicationCacheDirectory();
  final targetDir = join(cacheDirectory.path, assetDir);

  // Create target directory
  final dir = Directory(targetDir);
  await dir.create(recursive: true);

  // Check if we need to copy files (directory is empty or marker file doesn't exist)
  final markerFile = File(join(targetDir, '.copied'));
  if (await markerFile.exists()) {
    debugPrint('Directory $targetDir already copied, skipping');
    return targetDir;
  }

  debugPrint('Copying asset directory $assetDir to $targetDir');

  // Load asset manifest to get all files in the directory
  final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assetPaths = assetManifest
      .listAssets()
      .where((String key) => key.startsWith('assets/$assetDir/'))
      .toList();

  debugPrint('Found ${assetPaths.length} assets in $assetDir');

  // Copy each file preserving directory structure
  int copiedCount = 0;
  for (final assetPath in assetPaths) {
    try {
      final data = await rootBundle.load(assetPath);
      final relativePath = assetPath.substring('assets/$assetDir/'.length);
      final targetPath = join(targetDir, relativePath);

      // Create parent directories if needed
      final targetFile = File(targetPath);
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Write file
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await targetFile.writeAsBytes(bytes);
      copiedCount++;
    } catch (e) {
      debugPrint('Failed to copy $assetPath: $e');
      // Skip files that can't be loaded (might be directories in manifest)
      continue;
    }
  }

  debugPrint('Copied $copiedCount files from $assetDir');

  // Create marker file to indicate successful copy
  await markerFile.writeAsString('copied');

  return targetDir;
}
