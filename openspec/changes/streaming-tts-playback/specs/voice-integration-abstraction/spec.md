## MODIFIED Requirements

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
- **WHEN** a consumer calls TTS methods (initializeTts, generateSpeech, generateSpeechStream)
- **THEN** the native implementation SHALL delegate to the existing TTS isolate worker
- **AND** the stub implementation SHALL return null for generateSpeech and an empty stream for generateSpeechStream

#### Scenario: generateSpeechStream emits PCM byte chunks
- **WHEN** the native implementation's `generateSpeechStream` is called
- **THEN** it SHALL return a `Stream<List<int>>` that emits 16-bit LE PCM bytes in chunks
- **AND** the stream SHALL close when synthesis is complete

#### Scenario: Service provides audio session operations
- **WHEN** a consumer calls audio session methods (configureAudioSession, activateAudioSession, deactivateAudioSession)
- **THEN** the native implementation SHALL delegate to audio_session package
- **AND** the stub implementation SHALL return immediately without error

#### Scenario: Service provides background service operations
- **WHEN** a consumer calls background service methods (startBackgroundService, stopBackgroundService, updateNotification, showErrorNotification)
- **THEN** the native implementation SHALL delegate to the platform MethodChannel
- **AND** the stub implementation SHALL return immediately without error
