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

  // If file already exists in cache, verify it's complete
  if (exists) {
    final actualSize = await targetFile.length();
    debugPrint('Cached file $src exists: $actualSize bytes at $target');

    // File must be non-zero size to be valid
    if (actualSize > 0) {
      // Try to verify size matches asset (only works in main isolate)
      try {
        final data = await rootBundle.load('assets/$src');
        final expectedSize = data.lengthInBytes;

        if (actualSize == expectedSize) {
          // File is complete and valid
          debugPrint('✓ Cached file $src verified ($actualSize bytes)');
          return target;
        } else {
          debugPrint('✗ Cached file $src is incomplete ($actualSize bytes vs $expectedSize expected), re-copying...');
          // File is corrupted or incomplete, will re-copy below
        }
      } catch (e) {
        // Can't access rootBundle (likely background isolate)
        // Assume file is OK if it's non-zero size
        debugPrint('✓ Cached file $src (background isolate, size: $actualSize bytes)');
        return target;
      }
    } else {
      debugPrint('✗ Cached file $src is empty (0 bytes), re-copying...');
      // File is empty, will re-copy below
    }
  }

  // File doesn't exist or is corrupted, need to copy from assets (requires main isolate)
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
