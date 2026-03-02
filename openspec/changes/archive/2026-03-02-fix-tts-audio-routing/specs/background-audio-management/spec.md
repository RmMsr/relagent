## MODIFIED Requirements

### Requirement: Android Audio Mode Reset on Mode Transitions
When transitioning to TTS playback or idle mode, the Android audio mode SHALL be reset to `MODE_NORMAL` to ensure audio routes through the loudspeaker. `IN_COMMUNICATION` mode SHALL only be active during active microphone recording.

#### Scenario: TTS playback routes to loudspeaker
- **WHEN** the audio background service receives a `MODE_PLAYING` signal
- **THEN** the Android audio mode SHALL be set to `MODE_NORMAL`
- **AND** TTS audio SHALL play through the device loudspeaker
- **AND** `IN_COMMUNICATION` mode SHALL NOT be active

#### Scenario: Audio mode cleared on idle
- **WHEN** the audio background service receives a `MODE_IDLE` signal
- **THEN** the Android audio mode SHALL be reset to `MODE_NORMAL`
- **AND** any `IN_COMMUNICATION` mode from a previous recording session SHALL be cleared

#### Scenario: Recording still uses communication mode
- **WHEN** the audio background service receives a `MODE_RECORDING` signal
- **THEN** the Android audio mode SHALL be set to `IN_COMMUNICATION`
- **AND** the microphone SHALL route through the communication path
