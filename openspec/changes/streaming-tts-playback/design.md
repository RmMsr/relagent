## Context

The current TTS pipeline is fully buffer-based: `TtsIsolateWorker.generateAudio()` waits for `OfflineTts.generate()` to return a complete `Uint8List`, which `PlaybackService` then passes to `InMemoryAudioSource`. On an 8-second message this adds 4–8 s of silence before the first word plays.

`OfflineTts.generateWithCallback` in sherpa-onnx calls a Dart callback with each `OfflineTtsGeneratedAudio` chunk as soon as it is synthesized. Chunks arrive roughly every 200–500 ms. Piping these to `just_audio` before synthesis finishes gives users perceivable playback within the first chunk.

Existing infrastructure that this change can build on:
- `TtsIsolateWorker` — already isolate-based; `SendPort` messaging can carry chunk messages
- `PlaybackItem` — just needs a second path alongside `content: Future<Uint8List>`
- `InMemoryAudioSource` — already in `audio_source.dart`; needs a stream sibling
- `StreamAudioSource` — abstract class from `just_audio`; ready to subclass
- RTF gate from `tts-model-preview` sets `streamingDisabled` on `TtsService`

## Goals / Non-Goals

**Goals:**
- Reduce time-to-first-audio for TTS generation by starting playback on the first synthesized chunk.
- Keep the full-buffer path intact as a fallback when streaming is disabled via the RTF gate.
- Keep the change confined to the TTS/playback pipeline — no UI changes.

**Non-Goals:**
- Streaming ASR output or any non-TTS pipeline.
- Pause/seek within a streaming playback session — the WAV header will use unknown-length encoding; seeking is not supported while streaming.
- Background or pre-warming of synthesis for future messages.

## Decisions

### D1 — Isolate sends PCM chunks, not WAV frames

`generateWithCallback` yields `OfflineTtsGeneratedAudio` objects containing `Float32List samples` and `int sampleRate`. The callback runs inside the isolate. Each chunk is sent to the main isolate as a new sealed message `AudioChunkMessage(Float32List samples, int sampleRate)`, followed by `AudioStreamDoneMessage` when the callback stops being called.

The main isolate converts `Float32List` to 16-bit LE PCM bytes (`Int16List`) just before handing them to the audio source. This keeps the isolate protocol transport-agnostic; if a future audio format is preferred the conversion stays in one place on the main side.

Alternative considered: encode to MP3/Ogg in the isolate to avoid the WAV length problem below. Rejected because it requires a native encoder dependency and increases isolate CPU load.

### D2 — Streaming WAV header with unknown-length sentinels

`StreamAudioSource` in `just_audio` requires a content type. Raw PCM is not universally decodable by platform media players. A WAV envelope is the safest choice with no extra dependencies.

WAV headers encode file size in the RIFF chunk and `data` sub-chunk. For a live stream the final size is not known upfront. Both Android's ExoPlayer (underlying just_audio on Android) and libsound on Linux accept streaming WAV when the RIFF chunk size field is set to `0xFFFFFFFF` — the RIFF64 streaming sentinel. The `data` sub-chunk size is similarly set to `0xFFFFFFFF`.

A new `StreamingWavAudioSource` subclass of `StreamAudioSource` will:
1. Build and emit the 44-byte WAV header with sentinel sizes using the sample rate from the first chunk.
2. Stream 16-bit LE PCM bytes from each incoming chunk.
3. Signal end-of-stream when `AudioStreamDoneMessage` is received, completing the `StreamController`.

### D3 — `PlaybackItem` gains an optional stream field

`PlaybackItem` is extended with `Stream<List<int>>? streamContent`. Exactly one of `content` (the existing `Future<Uint8List>`) or `streamContent` is non-null for any given item.

`PlaybackService._processNext` detects which field is set:
- `content` → existing full-buffer path via `InMemoryAudioSource`
- `streamContent` → new streaming path via `StreamingWavAudioSource`

This is the smallest change to `PlaybackItem` without introducing a sealed class or breaking callers that use the current constructor.

### D4 — `TtsService` exposes `generateStream`, not a union return type

`TtsService` gains a new method `generateStream(text, messageId)` → `Stream<List<int>>`. `TtsNotifier` calls either `generate` (existing, returns `Future<Uint8List?>`) or `generateStream` based on `streamingDisabled`. This keeps the `generate` method signature unchanged for callers that have no streaming concern (e.g., pre-cache logic).

The `VoiceService` abstract interface gains `Stream<List<int>> generateSpeechStream(...)` so the native implementation and web stub stay consistent. The web stub returns `const Stream.empty()`.

### D5 — Streaming path skips the audio cache

The LRU audio cache in `TtsService` stores `Uint8List`. Streaming audio is ephemeral — the bytes are consumed as they arrive and cannot be cheaply replayed. The streaming path bypasses `_audioCache` entirely. If the same message is replayed after streaming, `TtsService.generateStream` is called again (re-synthesis). This is acceptable because manual replay of a fully-played message is rare.

Alternative: materialise the full WAV in the background while streaming, then cache it. Rejected for added complexity with marginal benefit.

### D6 — The RTF gate from `tts-model-preview` is the only toggle

No user-facing "enable streaming" setting is added. Streaming is the default; the RTF benchmark disables it automatically when a model is too slow. This keeps settings simple and removes a user-facing concept (streaming mode) that is an implementation detail.

### D7 — 1 s pre-playback pause after ASR stop

Streaming synthesis starts delivering audio in ~200–500 ms. Without a deliberate pause, TTS can begin playing before the microphone hardware has fully stopped capturing, causing ASR to record the TTS output.

`AudioCoordinator.requestPlayback()` already stops recording (mode → idle) and resets the audio session (~200 ms) before granting the playback lock. The existing additional delay of 200 ms is extended to **900 ms**, giving ≈ 1 s total from the moment the mode change fires until the speaker starts. By that point the recording animation has visibly stopped (~50–100 ms in) and the microphone is idle.

The delay is confined to the `if (state.mode == AudioMode.recording)` branch — it only applies when transitioning from recording to playback. TTS queued while already idle is unaffected.

Alternative considered: wait for `RecordingProvider.state.isRecording == false` before starting the delay. Rejected for the streaming change — the async state propagation adds complexity and the ~1 s fixed delay is a reliable proxy. A follow-up change can introduce speech-activity-aware scheduling if needed.

## Risks / Trade-offs

- [Risk] `0xFFFFFFFF` WAV sentinel is not guaranteed to work on iOS's AVFoundation. → Mitigation: test on iOS; fall back to full-buffer on iOS if AVFoundation rejects the streaming WAV. Gate can be extended to platform check.
- [Risk] If the synthesis isolate crashes mid-stream, the `StreamController` never closes and `just_audio` hangs. → Mitigation: add an `isolate.errors` listener in `TtsIsolateWorker`; close the stream controller with an error on isolate exit.
- [Risk] Pause/resume while streaming may produce garbled audio if ExoPlayer flushes the buffer. → Accepted: pause/resume semantics remain unchanged for the streaming path; users can stop and replay (which re-synthesizes).
- [Risk] Memory usage if chunks arrive faster than the audio is consumed. → Mitigation: `generateWithCallback` is synchronous within the isolate loop — the isolate naturally blocks after sending each chunk if the `SendPort` buffer fills. In practice synthesis rate ≈ playback rate so buffer stays small.

## Open Questions

- iOS AVFoundation streaming WAV compatibility — needs manual testing before enabling streaming on iOS. If incompatible, the streaming gate can be extended to skip iOS.
