## Purpose

Enable voice input through a unified VoiceService abstraction with target-based routing, model selection support (CTC/transducer architectures), and resilient lazy initialization.

## Requirements

### Requirement: Target-Based Speech Recognition
The system SHALL bind speech recognition to specific input targets, ensuring only one target receives speech input at a time. Speech recognition SHALL operate through the `VoiceService` abstraction rather than directly using the `ASR` class or native dependencies.

#### Scenario: Single active target enforcement
- **GIVEN** a recording target is registered
- **WHEN** another target attempts to register
- **THEN** the previous target SHALL be unregistered first
- **AND** only the new target SHALL receive speech recognition events

#### Scenario: Target receives recognized text
- **GIVEN** a target is registered and recording is active
- **WHEN** speech recognition produces partial or final text
- **THEN** the registered target SHALL receive the text via `onTextRecognized()` callback
- **AND** no other components SHALL receive the recognized text

#### Scenario: Target receives completion signal
- **GIVEN** a target is registered and continuous listening is active
- **WHEN** speech endpoint is detected
- **THEN** the registered target SHALL receive completion signal via `onTextFinished()` callback
- **AND** the target SHALL handle text submission

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

### Requirement: Simplified Recording Button
The RecordingButton widget SHALL focus solely on displaying recording state and triggering recording actions, using only app-defined types.

#### Scenario: Button uses local types for state checks
- **WHEN** the button checks whether recording is active
- **THEN** it SHALL compare against `AudioRecordingStatus.recording`
- **AND** it SHALL NOT reference `RecordState` from the `record` package

#### Scenario: Button displays recording state
- **GIVEN** RecordingButton is displayed
- **WHEN** recording state changes in RecordingProvider
- **THEN** the button SHALL update its visual state (icon, visualizer)
- **AND** the button SHALL NOT forward text or completion events

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
The ASR system SHALL use the model selected by the user rather than a hardcoded or bundled model name.

#### Scenario: Use user-selected downloaded model
- **WHEN** the user has selected a downloaded ASR model in settings
- **AND** the model is available in download storage
- **THEN** the recognizer factory SHALL load model files from the download storage directory
- **AND** it SHALL use the architecture specified in the model catalog entry

#### Scenario: No ASR model available
- **WHEN** no ASR model is selected in settings
- **THEN** the voice service SHALL report that speech recognition is unavailable
- **AND** the recording provider SHALL NOT attempt to start recording
- **AND** the UI SHALL indicate that a model download is required

#### Scenario: Selected ASR model not in downloads
- **WHEN** an ASR model ID is selected in settings but not present in download storage
- **THEN** the voice service SHALL treat this as "no model available"
- **AND** the recording provider SHALL NOT attempt to start recording

### Requirement: ASR Model Identity Comparison
The system SHALL compare ASR model identity by model ID string, not by object reference. The sherpa-onnx recognizer SHALL be reused across recordings when the selected model has not changed, and recreated only when the model ID actually differs.

#### Scenario: Recognizer reused on second recording start
- **GIVEN** a recording session has completed with model "model-a"
- **WHEN** a new recording starts with the same model "model-a"
- **THEN** the existing sherpa-onnx recognizer SHALL be reused
- **AND** recording SHALL start immediately without model reload

#### Scenario: Recognizer recreated when model changes
- **GIVEN** a recording session has completed with model "model-a"
- **WHEN** a new recording starts with model "model-b"
- **THEN** the previous recognizer SHALL be disposed
- **AND** a new recognizer SHALL be initialized with model "model-b"
- **AND** recording SHALL start after model initialization completes

### Requirement: Lazy Initialization Resilience for ASR
The `RecordingProvider` SHALL handle the case where the selected ASR model is not yet available at initialization time. When the selected model becomes available after initial startup, the provider SHALL reinitialize ASR with the correct model without requiring user action.

#### Scenario: ASR waits for model when scan is in progress
- **WHEN** `RecordingProvider.checkAutoStart()` is called
- **AND** `ModelDownloadState.downloadedModels` is still empty (scan in progress)
- **THEN** ASR SHALL NOT start recording
- **AND** the system SHALL wait for the scan to complete before evaluating model availability

#### Scenario: ASR restarts when selected model becomes available during recording
- **WHEN** the selected ASR model's download status transitions to downloaded
- **AND** continuous recording is currently active
- **THEN** ASR recording SHALL stop and restart using the newly available model
- **AND** listening SHALL resume without user action

#### Scenario: No ASR restart when not recording
- **WHEN** the selected ASR model becomes available in the download state
- **AND** continuous recording is NOT currently active
- **THEN** the system SHALL NOT start recording
- **AND** the correct model SHALL be used when recording next starts
