## ADDED Requirements

### Requirement: On-Demand TTS Preview
The system SHALL synthesize a fixed preview phrase using any downloaded TTS model on user request without affecting the assistant's active TTS service.

#### Scenario: Preview plays audio for downloaded model
- **WHEN** the user taps the Preview action on a downloaded TTS model card
- **THEN** the system SHALL spawn a one-shot TTS worker for that model
- **AND** synthesize a short fixed English phrase
- **AND** play the resulting audio immediately via a dedicated player
- **AND** dispose the preview worker after playback begins

#### Scenario: Preview does not interrupt assistant TTS
- **WHEN** a preview is triggered while the assistant is generating or playing speech
- **THEN** the assistant's TTS isolate SHALL remain unaffected
- **AND** preview audio SHALL play through a separate audio player instance

#### Scenario: Preview unavailable for non-downloaded model
- **WHEN** a model is not yet downloaded
- **THEN** the Preview action SHALL NOT be shown for that model card

#### Scenario: Preview error is shown inline
- **WHEN** the preview worker fails to initialize or generate audio
- **THEN** an error indicator SHALL appear on the model card
- **AND** the assistant's TTS SHALL remain unaffected

### Requirement: RTF Benchmark Measurement
The system SHALL measure the real-time factor (RTF) of each TTS model preview and persist the result.

#### Scenario: RTF captured from preview synthesis
- **WHEN** a preview completes successfully
- **THEN** the system SHALL record RTF = synthesis_time / audio_duration for the synthesized audio
- **AND** persist the result keyed by model id

#### Scenario: Benchmark persists across app restarts
- **GIVEN** a preview has been run for a model
- **WHEN** the app is closed and reopened
- **THEN** the RTF value for that model SHALL still be available without re-running the preview

#### Scenario: Re-running preview updates benchmark
- **WHEN** the user taps Preview on a model that already has a stored benchmark
- **THEN** the new RTF value SHALL overwrite the previous one
