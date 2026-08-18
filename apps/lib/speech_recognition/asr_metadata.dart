import '/models/model_catalog.dart';
import 'package:sherpa_voice/model_loader.dart';

class AsrModelMetadata {
  final ModelArchitecture architecture;
  final Map<String, String> fileStructure;
  final ModelLoader loader;
  final String modelId;

  /// Forced recognition language (e.g. 'no'), sourced from the model's
  /// first declared language. Only meaningful for architectures that need
  /// an explicit language rather than auto-detecting one (currently:
  /// [ModelArchitecture.whisper] — see sherpa_vad_asr.dart). Null when the
  /// model declares no languages at all.
  final String? language;

  const AsrModelMetadata({
    required this.architecture,
    required this.fileStructure,
    required this.loader,
    required this.modelId,
    this.language,
  });
}
