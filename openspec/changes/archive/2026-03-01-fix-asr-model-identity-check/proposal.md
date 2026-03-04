## Why

`AsrModelMetadata` is a plain Dart class with no `==` override. Every call to `resolveAsrMetadata()` returns a new object instance, so the identity check in `VoiceServiceNative._startRecording()` always evaluates to "different model" — triggering full model disposal and recreation (InitEncoder/InitDecoder/InitJoiner, several seconds) on every recording start after the first.

## What Changes

- `voice_service_native.dart`: Change model identity comparison from object reference (`!=`) to `modelId` string comparison (`?.modelId != ?.modelId`), so the sherpa-onnx recognizer is only recreated when the model actually changes.

## Capabilities

### New Capabilities

None — this is a bug fix within existing capabilities.

### Modified Capabilities

- `speech-recognition`: Requirement clarified — ASR model identity must be compared by model ID, not by object reference. The recognizer must be reused across recordings when the selected model has not changed.

## Impact

- `apps/lib/voice/voice_service_native.dart` — single-line change to the model metadata comparison
- No API changes, no new dependencies
- Effect: second and subsequent recordings start immediately instead of after several seconds of model reload
