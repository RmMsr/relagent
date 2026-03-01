## ADDED Requirements

### Requirement: CTC Model Architecture Support
The streaming ASR recognizer factory SHALL support CTC model architecture in addition to transducer.

#### Scenario: CTC model configuration
- **WHEN** the selected ASR model has architecture `ctc`
- **THEN** the recognizer factory SHALL create an `OnlineRecognizer` with CTC model config
- **AND** it SHALL use only `encoder.onnx` and `tokens.txt` (no decoder/joiner)

#### Scenario: Transducer model configuration preserved
- **WHEN** the selected ASR model has architecture `transducer`
- **THEN** the recognizer factory SHALL create an `OnlineRecognizer` with transducer model config
- **AND** it SHALL use `encoder.onnx`, `decoder.onnx`, `joiner.onnx`, and `tokens.txt`

#### Scenario: Streaming behavior identical for both architectures
- **WHEN** an `OnlineRecognizer` is created with either CTC or transducer config
- **THEN** the audio processing flow SHALL remain identical (acceptWaveform, decode, getResult, isEndpoint)
- **AND** the recording provider SHALL NOT need to change behavior based on architecture

### Requirement: Dynamic ASR Model Selection
The ASR system SHALL use the model selected by the user (or bundled fallback) rather than a hardcoded model name.

#### Scenario: Use user-selected downloaded model
- **WHEN** the user has selected a downloaded ASR model in settings
- **THEN** the recognizer factory SHALL load model files from the download storage directory
- **AND** it SHALL use the architecture specified in the model catalog entry

#### Scenario: Fall back to bundled model
- **WHEN** no ASR model is selected and bundled assets are available
- **THEN** the recognizer factory SHALL use the bundled model via `AssetModelLoader`
- **AND** it SHALL use the architecture from `AppConfig`

#### Scenario: No ASR model available
- **WHEN** no ASR model is selected and no bundled assets are available
- **THEN** the voice service SHALL report that speech recognition is unavailable
- **AND** the recording provider SHALL NOT attempt to start recording

## MODIFIED Requirements

### Requirement: RecordingProvider Uses Voice Service Abstraction
The `RecordingProvider` SHALL use the `VoiceService` interface for all recording operations instead of directly instantiating the `ASR` class or importing native packages.

#### Scenario: Provider depends on VoiceService
- **WHEN** `RecordingProvider` initializes recording
- **THEN** it SHALL call `VoiceService.startRecording()` with callback parameters
- **AND** it SHALL NOT create `ASR` instances directly
- **AND** it SHALL NOT import `package:record/record.dart` or `package:sherpa_onnx`

#### Scenario: Provider uses local AudioRecordingStatus
- **WHEN** recording state changes are reported
- **THEN** `RecordingProvider` SHALL receive `AudioRecordingStatus` values
- **AND** `RecordingState.recordState` SHALL be of type `AudioRecordingStatus`
- **AND** health monitoring SHALL compare against `AudioRecordingStatus.recording`

#### Scenario: Provider routes error notifications through VoiceService
- **WHEN** graceful degradation triggers an error notification
- **THEN** `RecordingProvider` SHALL call `VoiceService.showErrorNotification()`
- **AND** it SHALL NOT use `MethodChannel` directly

#### Scenario: Provider handles unavailable speech recognition
- **WHEN** the voice service reports that speech recognition is unavailable (no model)
- **THEN** the recording provider SHALL NOT attempt to start recording
- **AND** it SHALL report the unavailable state to the UI
