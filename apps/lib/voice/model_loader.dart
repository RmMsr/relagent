/// Abstraction for loading AI models (ASR, TTS).
///
/// Decouples model access from the loading strategy. Implementations
/// include asset-bundling and runtime download from remote sources.
abstract class ModelLoader {
  /// Load a model directory and return its file system path.
  Future<String> loadModel(String modelName);

  /// Load a specific file within a model and return its file system path.
  Future<String> loadModelFile(String modelName, String fileName);

  /// Load a directory within a model (e.g., espeak-ng-data) and return its path.
  Future<String> loadModelDirectory(String modelName, String dirName);

  /// Check if the model files are available and ready to use.
  Future<bool> isModelAvailable(String modelName);
}
