# microphone-selection Specification

## Purpose
Selection of the audio input device for speech recognition: enumeration of
available microphones, automatic Bluetooth-first selection, manual override
via long-press on the recording button, and persistence of that choice.

## Requirements
### Requirement: Input Device Enumeration

The system SHALL enumerate available audio input devices on Android, reporting for each device its type (built-in, Bluetooth, wired headset, USB), display name, and address where applicable. The enumeration SHALL refresh when devices connect or disconnect.

#### Scenario: Devices listed with identifying information

- **GIVEN** the app is running on Android 12+ with a Bluetooth headset connected
- **WHEN** the input device list is requested
- **THEN** the list SHALL contain the built-in microphone and the Bluetooth headset
- **AND** each entry SHALL include a device type and a human-readable name (product name preferred, generic type label as fallback)

#### Scenario: List refreshes on device change

- **GIVEN** the input device list has been requested
- **WHEN** a Bluetooth headset connects or disconnects
- **THEN** a device-change event SHALL be emitted
- **AND** a subsequent enumeration SHALL reflect the new set of devices

#### Scenario: Unsupported platform

- **GIVEN** the app is running on a platform without an input-device surface (web, or Android below API 31)
- **WHEN** the input device list is requested
- **THEN** the system SHALL report the capability as unavailable
- **AND** no error SHALL be raised

### Requirement: Automatic Microphone Selection

The system SHALL select the recording microphone automatically in the order: user-pinned device (if present) → Bluetooth headset (SCO or BLE) → built-in microphone.

#### Scenario: Bluetooth preferred automatically

- **GIVEN** the preference is "automatic" and a Bluetooth headset is connected
- **WHEN** a recording starts
- **THEN** the Bluetooth headset microphone SHALL be selected

#### Scenario: No Bluetooth device present

- **GIVEN** the preference is "automatic" and no Bluetooth headset is connected
- **WHEN** a recording starts
- **THEN** the built-in microphone SHALL be used
- **AND** no routing state SHALL be modified and no readiness wait SHALL occur

### Requirement: Manual Microphone Override

The user SHALL be able to override automatic selection by long-pressing the recording button, which opens a picker listing "Automatic" and the enumerated input devices.

#### Scenario: Long-press opens picker

- **GIVEN** the platform reports the input-device surface as available
- **WHEN** the user long-presses the recording button
- **THEN** a picker SHALL open listing "Automatic" and each available input device by name
- **AND** the currently effective choice SHALL be indicated

#### Scenario: Selecting a device pins it

- **GIVEN** the picker is open
- **WHEN** the user selects a specific device
- **THEN** that device SHALL be used for subsequent recordings while present
- **AND** the selection SHALL persist across app restarts

#### Scenario: Long-press on unsupported platform

- **GIVEN** the platform reports the input-device surface as unavailable
- **WHEN** the user long-presses the recording button
- **THEN** no picker SHALL open and no error SHALL occur

### Requirement: Active Input Device Indicator

The recording button SHALL display a symbol matching the active input device type: plain microphone for built-in, Bluetooth-badged for Bluetooth devices, wired/USB-badged for wired or USB devices. This applies to the recording button in both the chat input and the agentic chat input.

#### Scenario: Indicator reflects Bluetooth input

- **GIVEN** a recording is active on the Bluetooth headset microphone
- **WHEN** the recording button is rendered
- **THEN** it SHALL show the Bluetooth input symbol

#### Scenario: Indicator updates on device change

- **GIVEN** the Bluetooth headset disconnects and input falls back to the built-in microphone
- **WHEN** the device-change event is received
- **THEN** the recording button symbol SHALL update to the built-in microphone symbol

#### Scenario: Indicator on unsupported platform

- **GIVEN** the platform reports the input-device surface as unavailable
- **WHEN** the recording button is rendered
- **THEN** it SHALL show the plain microphone symbol

### Requirement: Preference Persistence and Fallback

A pinned device SHALL be persisted by stable identity (device type plus address where applicable, plus display name) — not by Android device ID, which is not stable across reboots. If the pinned device is absent when a recording starts, the system SHALL fall back to automatic selection for that recording and report the fallback.

#### Scenario: Pinned device absent

- **GIVEN** the user pinned a Bluetooth headset that is currently disconnected
- **WHEN** a recording starts
- **THEN** automatic selection SHALL apply for that recording
- **AND** the fallback SHALL be reported in the selection result and log
- **AND** the pin SHALL remain stored and apply again when the device returns

#### Scenario: Preference survives restart

- **GIVEN** the user pinned a specific device
- **WHEN** the app is restarted
- **THEN** the pinned preference SHALL be restored from persistent storage
