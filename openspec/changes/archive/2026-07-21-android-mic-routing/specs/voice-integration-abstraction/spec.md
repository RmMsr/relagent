# voice-integration-abstraction Delta Specification

## ADDED Requirements

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
