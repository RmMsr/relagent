## MODIFIED Requirements

### Requirement: Voice Input and Output

The system SHALL support the same voice input and output capabilities as the simple chat.

#### Scenario: Voice mode selection

- **WHEN** the Agentic Chat page is displayed
- **THEN** the voice mode selector SHALL be available
- **AND** all voice modes (Silent, Listening, Conversation, Reading) SHALL function

#### Scenario: Speech recognition

- **GIVEN** a continuous listening voice mode is active
- **WHEN** the user speaks
- **THEN** speech SHALL be recognized and displayed in the input field
- **AND** recognized text can be submitted to the engine

#### Scenario: Text-to-speech playback

- **GIVEN** an auto-playback voice mode is active
- **WHEN** an assistant response is received
- **THEN** the response SHALL be spoken aloud via TTS
- **AND** the TTS model used SHALL be selected based on the response's language code

#### Scenario: Text-to-speech playback falls back gracefully

- **GIVEN** an auto-playback voice mode is active
- **WHEN** an assistant response is received in a language with no assigned TTS model
- **THEN** the response SHALL still be spoken aloud using the fallback model
- **AND** if no TTS model is available at all, playback SHALL be skipped without blocking the text response
