## ADDED Requirements

### Requirement: Progressive Chunk Delivery from TTS Isolate
The TTS isolate SHALL emit synthesized audio as a sequence of PCM chunks as they are produced, rather than waiting for full synthesis to complete.

#### Scenario: Isolate emits chunks progressively
- **WHEN** a streaming TTS generation request is received by the isolate
- **THEN** the isolate SHALL call `generateWithCallback` on the sherpa-onnx `OfflineTts` instance
- **AND** each callback invocation SHALL send a chunk message to the main isolate immediately
- **AND** a completion sentinel SHALL be sent after the final chunk

#### Scenario: First chunk triggers playback start
- **WHEN** the first audio chunk arrives in the main isolate
- **THEN** playback SHALL begin without waiting for subsequent chunks
- **AND** later chunks SHALL be appended to the audio stream as they arrive

#### Scenario: Streaming synthesis does not block the isolate message loop
- **WHEN** a streaming generation is in progress
- **THEN** the isolate message loop SHALL remain responsive
- **AND** a dispose message received during streaming SHALL terminate the generation cleanly

### Requirement: Streaming WAV Delivery to Playback Layer
The streaming synthesis output SHALL be presented to `just_audio` as a WAV byte stream using unknown-length sentinel values in the RIFF header.

#### Scenario: WAV header uses unknown-length sentinels
- **WHEN** a streaming WAV source is created
- **THEN** the RIFF chunk size field SHALL be set to `0xFFFFFFFF`
- **AND** the data sub-chunk size field SHALL be set to `0xFFFFFFFF`
- **AND** the sample rate SHALL be taken from the first received chunk

#### Scenario: PCM chunks are emitted as 16-bit LE samples
- **WHEN** a `Float32List` chunk is received from the isolate
- **THEN** each sample SHALL be converted to a signed 16-bit little-endian integer
- **AND** the resulting bytes SHALL be appended to the stream immediately

#### Scenario: Stream closes on synthesis completion
- **WHEN** the completion sentinel is received from the isolate
- **THEN** the byte stream SHALL be closed
- **AND** `just_audio` SHALL treat the stream as complete and advance to the next queued item

### Requirement: RTF-Based Mode Selection
The TTS pipeline SHALL select between streaming and full-buffer synthesis based on the benchmark stored by the `tts-model-preview` capability.

#### Scenario: Streaming used when model benchmark is within threshold
- **WHEN** the active TTS model has a stored RTF benchmark of 1.10 or below
- **THEN** `TtsService` SHALL use the streaming synthesis path for new requests

#### Scenario: Full-buffer used when model benchmark exceeds threshold
- **WHEN** the active TTS model has a stored RTF benchmark greater than 1.10
- **THEN** `TtsService` SHALL use the full-buffer synthesis path
- **AND** playback SHALL not begin until the complete audio is returned

#### Scenario: Full-buffer used when no benchmark is available
- **WHEN** the active TTS model has no stored RTF benchmark
- **THEN** `TtsService` SHALL default to the streaming synthesis path
- **AND** the absence of a benchmark SHALL NOT suppress streaming

### Requirement: Transparent Fallback to Full-Buffer
Switching between streaming and full-buffer synthesis SHALL be invisible to callers above `TtsService`.

#### Scenario: PlaybackItem carries either buffer or stream
- **WHEN** `TtsNotifier` enqueues a playback item
- **THEN** the item SHALL carry either a `Future<Uint8List>` (full-buffer) or a `Stream<List<int>>` (streaming) — not both
- **AND** `PlaybackService` SHALL handle both item types without caller awareness of which path was used

#### Scenario: Audio cache bypassed for streaming path
- **WHEN** a message is synthesized via the streaming path
- **THEN** the resulting audio SHALL NOT be stored in the LRU audio cache
- **AND** a subsequent replay request for the same message SHALL trigger a new synthesis
