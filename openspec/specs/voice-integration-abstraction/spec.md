## ADDED Requirements

### Requirement: Voice Service Interface
The system SHALL define an abstract `VoiceService` interface that encapsulates all voice-related platform dependencies (ASR, TTS, audio recording, audio session management, background service).

#### Scenario: Native platform returns functional implementation
- **WHEN** the app starts on Android, iOS, or Linux
- **THEN** `createVoiceService()` SHALL return a native implementation that wraps sherpa_onnx, record, and audio_session
- **AND** all voice capabilities SHALL report as available

#### Scenario: Web platform returns stub implementation
- **WHEN** the app starts in a web browser
- **THEN** `createVoiceService()` SHALL return a no-op stub implementation
- **AND** all voice capabilities SHALL report as unavailable

#### Scenario: Service provides ASR operations
- **WHEN** a consumer calls ASR methods (initializeAsr, startRecording, stopRecording, pauseRecording, resumeRecording)
- **THEN** the native implementation SHALL delegate to the existing ASR engine
- **AND** the stub implementation SHALL return immediately without error

#### Scenario: Service provides TTS operations
- **WHEN** a consumer calls TTS methods (initializeTts, generateSpeech)
- **THEN** the native implementation SHALL delegate to the existing TTS isolate worker
- **AND** the stub implementation SHALL return null for generated audio

#### Scenario: Service provides audio session operations
- **WHEN** a consumer calls audio session methods (configureAudioSession, activateAudioSession, deactivateAudioSession)
- **THEN** the native implementation SHALL delegate to audio_session package
- **AND** the stub implementation SHALL return immediately without error

#### Scenario: Service provides background service operations
- **WHEN** a consumer calls background service methods (startBackgroundService, stopBackgroundService, updateNotification, showErrorNotification)
- **THEN** the native implementation SHALL delegate to the platform MethodChannel
- **AND** the stub implementation SHALL return immediately without error

### Requirement: Local Audio Recording Status Type
The system SHALL define an app-owned `AudioRecordingStatus` enum that replaces the `RecordState` type from the `record` package in all code outside the voice service implementation.

#### Scenario: Enum values match recording lifecycle
- **WHEN** the `AudioRecordingStatus` enum is defined
- **THEN** it SHALL include values: `stopped`, `recording`, `paused`
- **AND** these SHALL map to the equivalent `RecordState` values in the native implementation

#### Scenario: No record package types in providers
- **WHEN** `RecordingProvider` or `RecordingState` reference recording status
- **THEN** they SHALL use `AudioRecordingStatus` exclusively
- **AND** they SHALL NOT import `package:record/record.dart`

#### Scenario: No record package types in widgets
- **WHEN** widgets display or check recording status (RecordingStateIndicator, RecorderButton)
- **THEN** they SHALL use `AudioRecordingStatus` exclusively
- **AND** they SHALL NOT import `package:record/record.dart`

### Requirement: Voice Capabilities Query
The system SHALL provide a `VoiceCapabilities` interface for querying which voice features are available on the current platform.

#### Scenario: Capabilities reflect platform support
- **WHEN** code queries `isAsrAvailable`, `isTtsAvailable`, or `isBackgroundListeningAvailable`
- **THEN** native platforms SHALL return true
- **AND** web SHALL return false

#### Scenario: Capabilities available via Riverpod provider
- **WHEN** a widget needs to check voice availability
- **THEN** it SHALL access capabilities through a Riverpod provider
- **AND** the provider SHALL return the capabilities from the active `VoiceService` instance

### Requirement: Conditional Import Boundary
The system SHALL use Dart conditional imports to select between native and stub implementations at exactly one entry point.

#### Scenario: Conditional import uses dart.library.io
- **WHEN** the voice service factory is imported
- **THEN** the import SHALL use `if (dart.library.io)` to select between native and stub files
- **AND** no other file in the codebase SHALL use conditional imports for voice dependencies

#### Scenario: Native dependencies confined to implementation files
- **WHEN** `sherpa_onnx`, `record`, or `audio_session` packages are imported
- **THEN** the import SHALL only occur in files within `lib/voice/` native implementation
- **AND** no provider, widget, or model file SHALL import these packages directly

### Requirement: Audio Interruption Abstraction
The system SHALL define a local `AudioInterruptionEvent` type and expose interruption events through the `VoiceService` interface.

#### Scenario: Native implementation forwards interruptions
- **WHEN** the audio_session package detects an interruption (phone call, alarm)
- **THEN** the native `VoiceService` SHALL emit a local `AudioInterruptionEvent`
- **AND** consumers SHALL not need to import `audio_session`

#### Scenario: Stub implementation provides empty stream
- **WHEN** consumers listen to `interruptionEvents` on web
- **THEN** the stream SHALL be empty (never emit)
- **AND** consumers SHALL handle the empty stream gracefully without errors
