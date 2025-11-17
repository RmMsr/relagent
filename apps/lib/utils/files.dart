// Containes code from sherpa-onnx. Copyright (c) 2024  Xiaomi Corporation
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

Future<String> copyAssetFileToCache(String src, [String? dst]) async {
  final Directory directory = await getApplicationCacheDirectory();
  dst ??= basename(src);
  final target = join(directory.path, dst);
  bool exists = await File(target).exists();

  final data = await rootBundle.load(src);

  if (!exists || File(target).lengthSync() != data.lengthInBytes) {
    final List<int> bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    await File(target).writeAsBytes(bytes);
  }

  return target;
}
