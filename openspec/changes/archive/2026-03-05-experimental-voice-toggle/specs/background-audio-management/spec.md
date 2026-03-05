## ADDED Requirements

### Requirement: Continuous voice toggle gate

Background audio management features (health monitoring, recovery, wake locks, foreground service) SHALL only activate when `continuousVoiceEnabled` is `true` in settings.

#### Scenario: Background service blocked when toggle is off
- **GIVEN** `continuousVoiceEnabled` is `false`
- **WHEN** a voice mode change to `listening` or `conversation` is attempted
- **THEN** the background audio service SHALL NOT start
- **AND** health monitoring SHALL NOT start
- **AND** no wake lock SHALL be acquired

#### Scenario: Background service stops when toggle is disabled
- **GIVEN** `continuousVoiceEnabled` is `true`
- **AND** the background audio service is running
- **WHEN** `continuousVoiceEnabled` is set to `false`
- **THEN** the background audio service SHALL stop
- **AND** health monitoring SHALL stop
- **AND** the wake lock SHALL be released
- **AND** the foreground notification SHALL be dismissed
