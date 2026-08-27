## Purpose

Make text-to-speech playback pick the TTS model that matches an assistant message's response language, falling back gracefully when no matching model is available.

## ADDED Requirements

### Requirement: Language-Based TTS Model Selection
When TTS playback is triggered for an assistant message, the app SHALL select the TTS model to use based on the message's language code and the device's local language-to-model assignments.

#### Scenario: Assigned model available for the language
- **GIVEN** the device has a TTS model assigned to the message's language code
- **WHEN** TTS playback is triggered
- **THEN** playback SHALL use the assigned model

#### Scenario: No language code on the message
- **GIVEN** the message has no language code (English or undetermined)
- **WHEN** TTS playback is triggered
- **THEN** playback SHALL use the device default TTS model

### Requirement: Graceful Fallback Chain
When no TTS model is assigned to a message's language, the app SHALL fall back in a defined order rather than failing playback.

#### Scenario: Fall back to default model
- **GIVEN** no model is assigned to the message's language
- **AND** a device default TTS model is set
- **WHEN** TTS playback is triggered
- **THEN** playback SHALL use the device default model

#### Scenario: Fall back to first available model
- **GIVEN** no model is assigned to the message's language
- **AND** no device default TTS model is set
- **AND** at least one TTS model is downloaded
- **WHEN** TTS playback is triggered
- **THEN** playback SHALL use one of the downloaded TTS models

#### Scenario: No TTS model available
- **GIVEN** no model is assigned to the message's language
- **AND** no device default is set
- **AND** no TTS model is downloaded
- **WHEN** TTS playback is triggered
- **THEN** playback SHALL be skipped
- **AND** the message text SHALL remain visible to the user
