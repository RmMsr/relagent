/// Abstraction for loading AI models (ASR, TTS).
///
/// Decouples model access from the loading strategy. The current
/// asset-bundling approach is one implementation; future implementations
/// may download models at runtime.
abstract class ModelLoader {
  /// Load a model directory and return its file system path.
  Future<String> loadModel(String modelName);

  /// Load a specific file within a model and return its file system path.
  Future<String> loadModelFile(String modelName, String fileName);

  /// Load a directory within a model (e.g., espeak-ng-data) and return its path.
  Future<String> loadModelDirectory(String modelName, String dirName);
}
