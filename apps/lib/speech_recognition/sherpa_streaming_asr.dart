import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/asr_config.dart';

import 'asr_metadata.dart';

/// Create an OnlineRecognizer using explicit model metadata.
Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizerFromMetadata(
  AsrModelMetadata metadata,
) async {
  return buildAsrRecognizer(
    metadata.architecture,
    metadata.fileStructure,
    metadata.loader,
    metadata.modelId,
  );
}
