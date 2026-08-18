## MODIFIED Requirements

### Requirement: Input Device Enumeration

The system SHALL enumerate available audio input devices on Android, reporting for each device its type (built-in, Bluetooth, wired headset, USB), display name, and address where applicable. The enumeration SHALL refresh when devices connect or disconnect.

#### Scenario: Devices listed with identifying information

- **GIVEN** the app is running on Android API 23+ with a Bluetooth headset connected
- **WHEN** the input device list is requested
- **THEN** the list SHALL contain the built-in microphone and the Bluetooth headset
- **AND** each entry SHALL include a device type and a human-readable name (product name preferred, generic type label as fallback)

#### Scenario: List refreshes on device change

- **GIVEN** the input device list has been requested
- **WHEN** a Bluetooth headset connects or disconnects
- **THEN** a device-change event SHALL be emitted
- **AND** a subsequent enumeration SHALL reflect the new set of devices

#### Scenario: Unsupported platform

- **GIVEN** the app is running on a platform without an input-device surface (web, or Android below API 23)
- **WHEN** the input device list is requested
- **THEN** the system SHALL report the capability as unavailable
- **AND** no error SHALL be raised
