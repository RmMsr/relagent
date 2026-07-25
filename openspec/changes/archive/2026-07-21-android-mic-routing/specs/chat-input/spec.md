# chat-input Delta Specification

## ADDED Requirements

### Requirement: Recording Button Microphone Override

The recording button in the chat input SHALL open a microphone picker on long-press when the voice service reports input selection as available. Tap behavior (start/stop recording) SHALL be unchanged. The same behavior SHALL apply to the agentic chat input via a shared widget.

#### Scenario: Long-press opens the microphone picker

- **GIVEN** the voice service reports input selection as available
- **WHEN** the user long-presses the recording button
- **THEN** a picker SHALL open listing "Automatic" and the available input devices
- **AND** the currently effective selection SHALL be indicated
- **AND** choosing an entry SHALL update the microphone preference

#### Scenario: Long-press without input selection support

- **GIVEN** the voice service reports input selection as unavailable
- **WHEN** the user long-presses the recording button
- **THEN** nothing SHALL happen and no error SHALL be shown

### Requirement: Recording Button Device Symbol

The recording button SHALL display a symbol matching the active input device type (built-in, Bluetooth, wired/USB) and SHALL update when the active device changes.

#### Scenario: Symbol shows Bluetooth input

- **GIVEN** the active input device is a Bluetooth headset
- **WHEN** the recording button is rendered
- **THEN** it SHALL display the Bluetooth-badged microphone symbol

#### Scenario: Symbol updates on device change

- **GIVEN** the recording button shows the Bluetooth symbol
- **WHEN** the headset disconnects and input falls back to the built-in microphone
- **THEN** the symbol SHALL change to the plain microphone symbol without requiring a rebuild of the input widget by the user

#### Scenario: Symbol without input selection support

- **GIVEN** the voice service reports input selection as unavailable
- **WHEN** the recording button is rendered
- **THEN** it SHALL display the plain microphone symbol
