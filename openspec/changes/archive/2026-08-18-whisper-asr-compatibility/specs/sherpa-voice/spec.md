## MODIFIED Requirements

### Requirement: Architecture Taxonomy
`packages/sherpa_voice/` SHALL define the `ModelArchitecture` and `ModelType` enums as the single source of truth for the taxonomy of supported sherpa-onnx model types. Supported TTS architectures SHALL include `kokoro`, `vitsPiper`, and `pocket`. Supported ASR architectures SHALL include `transducer`, `ctc`, `onlineNemoCtc`, `offlineNemoTransducer`, and `whisper`.

#### Scenario: Both consumers import enums from the shared package
- **WHEN** `apps/` or `tools/voice_catalog/` references `ModelArchitecture`
- **THEN** the import SHALL resolve to `package:sherpa_voice/model_architecture.dart`
- **AND** no duplicate enum definitions SHALL exist elsewhere

## ADDED Requirements

### Requirement: Offline ASR Recognition Support
The system SHALL support running offline (non-streaming) ASR architectures — those with no incremental partial-result API — by chunking audio through `VoiceActivityDetector` and decoding each chunk with an `OfflineRecognizer`, the same mechanism already used for `offlineNemoTransducer`. `whisper` SHALL be recognized as an offline architecture.

#### Scenario: Whisper recognizer built with forced language
- **WHEN** an `OfflineRecognizer` is constructed for `ModelArchitecture.whisper`
- **THEN** it SHALL use `OfflineModelConfig.whisper` with encoder, decoder, and tokens paths
- **AND** `language` SHALL be set to a fixed, non-empty value associated with the model — never left empty for auto-detection
- **AND** `task` SHALL be set to `'transcribe'`

#### Scenario: Missing forced language rejected
- **WHEN** a whisper model's metadata does not specify a language to force
- **THEN** recognizer construction SHALL fail with an error identifying the missing language, rather than silently falling back to auto-detection

#### Scenario: Whisper excluded from streaming-capable classification
- **WHEN** any part of the system derives whether a model supports live/streaming recognition from its architecture
- **THEN** `whisper` SHALL be classified as not streaming-capable, consistent with its offline/chunked (30-second-window) decoding
