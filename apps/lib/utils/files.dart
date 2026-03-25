// Contains code from sherpa-onnx. Copyright (c) 2024  Xiaomi Corporation
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';

Future<String> copyAssetFileToCache(String src, [String? dst]) async {
  final Directory directory = await getApplicationCacheDirectory();
  final target = join(directory.path, src);
  final targetFile = File(target);
  bool exists = await targetFile.exists();

  // If file already exists in cache, verify it's complete
  if (exists) {
    final actualSize = await targetFile.length();
    Logger.debug('Cached file $src exists: $actualSize bytes at $target');

    // File must be non-zero size to be valid
    if (actualSize > 0) {
      // Try to verify size matches asset (only works in main isolate)
      try {
        final data = await rootBundle.load('assets/$src');
        final expectedSize = data.lengthInBytes;

        if (actualSize == expectedSize) {
          // File is complete and valid
          Logger.debug('✓ Cached file $src verified ($actualSize bytes)');
          return target;
        } else {
          Logger.debug(
            '✗ Cached file $src is incomplete ($actualSize bytes vs $expectedSize expected), re-copying...',
          );
          // File is corrupted or incomplete, will re-copy below
        }
      } catch (e) {
        // Can't access rootBundle (likely background isolate)
        // Assume file is OK if it's non-zero size
        Logger.debug(
          '✓ Cached file $src (background isolate, size: $actualSize bytes)',
        );
        return target;
      }
    } else {
      Logger.debug('✗ Cached file $src is empty (0 bytes), re-copying...');
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

