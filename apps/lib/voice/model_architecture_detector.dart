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

  // encoder + decoder + joiner covers both live Transducer (Zipformer) and
  // chunked NeMo Transducer exports — the layout alone can't tell them apart
  // (see isAmbiguousTransducerShape). "nemo" in the path is a weak hint
  // toward the chunked NeMo export, but not proof: some NeMo *streaming*
  // exports (e.g. "nemotron") also use this layout and are actually live.
  if (hasEncoder && hasDecoder && hasJoiner) {
    return hasNemo
        ? ModelArchitecture.offlineNemoTransducer
        : ModelArchitecture.transducer;
  }

  // Whisper: sherpa-onnx's own export-onnx.py names encoder/decoder/tokens
  // with a shared "{model-name}-" filename prefix instead of the bare names
  // every other architecture here uses, so this can't reuse hasEncoder/
  // hasDecoder/hasTokens above (those require startsWith/exact-match on the
  // bare form). Deliberately narrow — exactly one *encoder*.onnx, exactly one
  // *decoder*.onnx sharing a prefix, no joiner, and a "<prefix>tokens.txt" —
  // rather than loosening the general checks globally, so an unrelated
  // archive with a stray "*decoder*.onnx" can't accidentally match. This
  // still correctly matches the bare "encoder.onnx"/"decoder.onnx"/
  // "tokens.txt" case too (empty shared prefix).
  final onnxEncoderFiles =
      names.where((n) => n.contains('encoder') && n.endsWith('.onnx')).toList();
  final onnxDecoderFiles =
      names.where((n) => n.contains('decoder') && n.endsWith('.onnx')).toList();
  final onnxJoinerFiles =
      names.where((n) => n.contains('joiner') && n.endsWith('.onnx'));
  if (onnxEncoderFiles.length == 1 &&
      onnxDecoderFiles.length == 1 &&
      onnxJoinerFiles.isEmpty) {
    final encoderName = onnxEncoderFiles.single;
    final prefix = encoderName.substring(0, encoderName.indexOf('encoder'));
    if (onnxDecoderFiles.single.startsWith(prefix) &&
        names.contains('${prefix}tokens.txt')) {
      return ModelArchitecture.whisper;
    }
  }

  // Piper VITS: single model file + espeak data (TTS)
  if (hasModel && hasEspeak) return ModelArchitecture.vitsPiper;

  // NeMo CTC streaming: 'nemo' anywhere in the archive paths distinguishes it
  // from offline Zipformer/Paraformer CTC models which have the same file layout.
  if (hasModel && hasTokens && hasNemo) return ModelArchitecture.onlineNemoCtc;

  // CTC: single model file + tokens (offline, e.g. Zipformer2 / Paraformer)
  if (hasModel && hasTokens) return ModelArchitecture.ctc;

  return null;
}

/// Whether [entryNames] match the encoder+decoder+joiner layout shared by
/// both live Transducer and chunked NeMo Transducer. [detectArchitecture]
/// always has to guess one of the two for this shape, but the guess (even
/// the "nemo"-in-path hint) is never reliable enough to trust outright.
bool isAmbiguousTransducerShape(List<String> entryNames) {
  final names = entryNames.map((e) => e.split('/').last.toLowerCase()).toSet();
  final hasEncoder = names.any(
    (n) => n.startsWith('encoder') && n.endsWith('.onnx'),
  );
  final hasDecoder = names.any(
    (n) => n.startsWith('decoder') && n.endsWith('.onnx'),
  );
  final hasJoiner = names.any(
    (n) => n.startsWith('joiner') && n.endsWith('.onnx'),
  );
  return hasEncoder && hasDecoder && hasJoiner;
}
