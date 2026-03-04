## Why

The current TTS pipeline waits for the full synthesis to complete before starting audio playback, adding noticeable silence on longer messages. `OfflineTts.generateWithCallback` in sherpa-onnx yields audio chunks progressively as they are synthesized — piping these directly to `just_audio` via `StreamAudioSource` lets playback begin within the first chunk, cutting perceived latency significantly on capable hardware.

## What Changes

- Add a streaming synthesis path to `TtsIsolateWorker` using `generateWithCallback`; the isolate emits `Float32List` chunks through a `SendPort` as they arrive and signals completion with a sentinel.
- `TtsService` selects between streaming and full-buffer synthesis based on a `streamingDisabled` flag set by `TtsNotifier` from the RTF benchmark (established by the `tts-model-preview` change).
- `PlaybackProvider` feeds streaming audio to `just_audio` via `StreamAudioSource` so playback begins on the first chunk.
- The full-buffer path is retained as a fallback for models whose RTF benchmark exceeds 1.10 or where no benchmark exists and the user disables streaming.

## Capabilities

### New Capabilities

- `streaming-tts-synthesis`: Progressive audio delivery from the TTS isolate to the playback layer, with RTF-based mode selection and transparent fallback to full-buffer synthesis.

### Modified Capabilities

- `voice-integration-abstraction`: The TTS pipeline now produces audio as a stream of chunks in streaming mode; the `generateSpeech` contract in `VoiceService` needs to express this optional streaming output.

## Impact

- **apps/lib/tts/tts_isolate_worker.dart** — New `StreamGenerateAudioMessage` message type and chunk-emit loop using `generateWithCallback`; isolate sends `AudioChunkResponse` packets followed by `AudioStreamDoneResponse`.
- **apps/lib/tts/services.dart** — `TtsService.generate` switches path based on `streamingDisabled`; streaming path returns a `Stream<Uint8List>` instead of `Future<Uint8List>`.
- **apps/lib/providers/tts_provider.dart** — Reads `streamingDisabled` from benchmark, passes it to `TtsService`; wraps streaming result in `PlaybackItem.stream` instead of `PlaybackItem.content`.
- **apps/lib/providers/playback_provider.dart** — `PlaybackItem` gains an optional `Stream<Uint8List>` field; `PlaybackService` feeds it to `just_audio`'s `StreamAudioSource`.
- No new pub dependencies — `just_audio`'s `StreamAudioSource` is already available.
