import '/voice/model_loader.dart';

/// Model loader for platforms that cannot load local models (web).
/// All methods throw UnsupportedError.
class UnavailableModelLoader implements ModelLoader {
  @override
  Future<String> loadModel(String modelName) {
    throw UnsupportedError('Model loading is not available on this platform');
  }

  @override
  Future<String> loadModelFile(String modelName, String fileName) {
    throw UnsupportedError('Model loading is not available on this platform');
  }

  @override
  Future<String> loadModelDirectory(String modelName, String dirName) {
    throw UnsupportedError('Model loading is not available on this platform');
  }
}
