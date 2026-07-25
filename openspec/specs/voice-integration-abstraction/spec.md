## Purpose

Define a unified `VoiceService` interface that abstracts all voice-related dependencies (ASR, TTS, audio recording, background services), enabling platform-specific implementations with a web stub.

## Requirements

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
- **WHEN** a consumer calls audio session methods (configureAudioSession, configureAudioSessionForRecording, configureAudioSessionForPlayback, activateAudioSession, deactivateAudioSession)
- **THEN** the native implementation SHALL delegate to audio_session package
- **AND** `configureAudioSessionForRecording` SHALL set voiceCommunication usage (Android) and playAndRecord/voiceChat category with allowBluetooth (iOS)
- **AND** `configureAudioSessionForPlayback` SHALL set assistant usage (Android) and playback/spokenAudio category with allowBluetooth/allowBluetoothA2dp (iOS)
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

### Requirement: Input Device Surface

The `VoiceService` interface SHALL expose an input-device surface: list available input devices, set the input device preference (automatic or a pinned device), query the active input device, and a stream of input-device-change events. Implementations without native routing support SHALL report the surface as unavailable through `VoiceCapabilities`.

#### Scenario: Native Android implementation provides the surface

- **GIVEN** the app runs the native voice service on Android 12+
- **WHEN** the input-device surface is queried
- **THEN** `VoiceCapabilities` SHALL report input selection as available
- **AND** listing devices SHALL return the enumerated Android input devices
- **AND** setting a preference SHALL affect subsequent recording routing

#### Scenario: Stub and unsupported implementations degrade gracefully

- **GIVEN** the app runs the stub voice service (web) or a platform without routing support (iOS for now, Android below API 31)
- **WHEN** the input-device surface is queried
- **THEN** `VoiceCapabilities` SHALL report input selection as unavailable
- **AND** listing devices SHALL return an empty list without raising errors
- **AND** UI consumers SHALL use this to hide the microphone picker and show the plain microphone symbol

#### Scenario: Routing errors never block recording

- **GIVEN** the native voice service invokes the input-device surface
- **WHEN** the underlying platform channel fails (exception or missing implementation)
- **THEN** the failure SHALL be logged and the call SHALL degrade to default-device behavior
- **AND** recording SHALL start regardless, beyond at most the bounded readiness timeout
