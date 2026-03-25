## Why

ASR model initialization (`sherpa_onnx.OnlineRecognizer(config)` / `sherpa_onnx.OfflineRecognizer(config)`) runs on the main isolate and blocks the UI for several seconds on first use. The `remove-asset-model-loading` change adds a blocking overlay as a workaround, but the proper fix is to move ASR initialization to a background isolate — the same pattern already used for TTS via `TtsIsolateWorker`.

Earlier attempts to do this failed. This change captures the approach so it can be attempted when time allows, without blocking other work.

## What Changes

- Move ASR recognizer creation and audio processing to a background isolate (similar to `TtsIsolateWorker`)
- Remove the initialization overlay workaround from `remove-asset-model-loading` once isolate init works
- ASR audio stream data is forwarded to the worker isolate for processing
- Recognized text results are sent back to the main isolate via `SendPort`

## Capabilities

### New Capabilities

_(none — this is a performance improvement within existing capabilities)_

### Modified Capabilities

- `speech-recognition`: ASR recognizer initialization and audio processing move to a background isolate, eliminating main-thread blocking
- `voice-init-feedback`: Overlay becomes unnecessary and can be removed once isolate init is stable

## Impact

- `apps/lib/speech_recognition/services.dart` — `ASR` class refactored to use isolate worker
- `apps/lib/speech_recognition/sherpa_vad_asr.dart` — `VadAsr` class refactored similarly
- New `apps/lib/speech_recognition/asr_isolate_worker.dart` — worker isolate (modeled after `tts_isolate_worker.dart`)
- `apps/lib/providers/recording_provider.dart` — remove overlay logic once isolate init works

## Known Risks

- **Earlier attempts failed** — the exact failure mode should be investigated before starting. Possible issues: `sherpa_onnx` native bindings not working in background isolates, audio stream forwarding overhead, `RootIsolateToken` requirements.
- **Audio stream latency** — forwarding raw audio chunks across isolate boundaries adds overhead. Must verify real-time performance is maintained.
- **TTS isolate works as a reference** — `TtsIsolateWorker` proves the pattern is viable for sherpa_onnx. ASR is more complex because of the continuous audio stream (TTS is request/response).
