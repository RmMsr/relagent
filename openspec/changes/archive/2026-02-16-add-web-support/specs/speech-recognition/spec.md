## MODIFIED Requirements

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
