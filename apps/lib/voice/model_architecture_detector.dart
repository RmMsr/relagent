import '/models/model_catalog.dart';

/// Infer a sherpa-onnx [ModelArchitecture] from the list of file paths inside
/// a model archive. Returns null when no pattern matches confidently.
ModelArchitecture? detectArchitecture(List<String> entryNames) {
  final names = entryNames.map((e) => e.split('/').last.toLowerCase()).toSet();

  // Kokoro: voices.bin is unique to this architecture
  if (names.contains('voices.bin')) return ModelArchitecture.kokoro;

  final hasEncoder = names.any(
    (n) => n.startsWith('encoder') && n.endsWith('.onnx'),
  );
  final hasDecoder = names.any(
    (n) => n.startsWith('decoder') && n.endsWith('.onnx'),
  );
  final hasJoiner = names.any(
    (n) => n.startsWith('joiner') && n.endsWith('.onnx'),
  );
  // Any .onnx that isn't encoder/decoder/joiner (catches model.int8.onnx etc.)
  final hasModel = names.any(
    (n) =>
        n.endsWith('.onnx') &&
        !n.startsWith('encoder') &&
        !n.startsWith('decoder') &&
        !n.startsWith('joiner'),
  );
  final hasTokens = names.contains('tokens.txt');
  final hasEspeak = entryNames.any((e) => e.contains('espeak-ng-data'));
  final hasNemo = entryNames.any((e) => e.toLowerCase().contains('nemo'));

  // Transducer: encoder + decoder + joiner (covers Zipformer and NeMo transducer)
  if (hasEncoder && hasDecoder && hasJoiner) return ModelArchitecture.transducer;

  // Piper VITS: single model file + espeak data (TTS)
  if (hasModel && hasEspeak) return ModelArchitecture.vitsPiper;

  // NeMo CTC streaming: 'nemo' anywhere in the archive paths distinguishes it
  // from offline Zipformer/Paraformer CTC models which have the same file layout.
  if (hasModel && hasTokens && hasNemo) return ModelArchitecture.onlineNemoCtc;

  // CTC: single model file + tokens (offline, e.g. Zipformer2 / Paraformer)
  if (hasModel && hasTokens) return ModelArchitecture.ctc;

  return null;
}
