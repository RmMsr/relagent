import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_voice/model_loader.dart';

import '/models/imported_model.dart';

/// Loads imported models from the application support directory.
///
/// Models are stored at `<support_dir>/imported_models/<type>/<id>/`.
class ImportedModelLoader implements ModelLoader {
  final ImportedModelEntry _entry;

  ImportedModelLoader(this._entry);

  Future<String> _modelBasePath() async {
    final supportDir = await getApplicationSupportDirectory();
    final typeDir = _entry.type == ModelType.asr ? 'asr' : 'tts';
    return p.join(supportDir.path, 'imported_models', typeDir, _entry.id);
  }

  @override
  Future<String> loadModel(String modelName) async {
    return _modelBasePath();
  }

  @override
  Future<String> loadModelFile(String modelName, String fileName) async {
    final basePath = await _modelBasePath();
    return p.join(basePath, fileName);
  }

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) async {
    final basePath = await _modelBasePath();
    return p.join(basePath, dirName);
  }

  @override
  Future<bool> isModelAvailable(String modelName) async {
    final basePath = await _modelBasePath();
    final marker = File(p.join(basePath, '.complete'));
    return marker.exists();
  }
}
