import '/models/model_catalog.dart';
import '/voice/model_loader.dart';

class AsrModelMetadata {
  final ModelArchitecture architecture;
  final Map<String, String> fileStructure;
  final ModelLoader loader;
  final String modelId;

  const AsrModelMetadata({
    required this.architecture,
    required this.fileStructure,
    required this.loader,
    required this.modelId,
  });
}
