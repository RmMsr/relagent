## ADDED Requirements

### Requirement: Notification Permission Check on Service Start

The system SHALL check and request notification permission when the background audio service starts.

#### Scenario: Permission granted

- **WHEN** continuous audio mode is activated and background service starts
- **AND** notification permission is not granted
- **THEN** the system SHALL request notification permission using Android's newer interface
- **AND** if granted, service SHALL start normally

#### Scenario: Permission denied

- **WHEN** notification permission is requested
- **AND** user denies permission
- **THEN** the system SHALL show appropriate error message
- **AND** service SHALL not start or SHALL degrade gracefully