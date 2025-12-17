# user-settings Specification

## Purpose
TBD - created by archiving change add-reliable-background-listening. Update Purpose after archive.
## Requirements
### Requirement: Background Listening Duration Setting
The system SHALL provide a user setting to configure the maximum duration for background listening sessions.

#### Scenario: Default duration is one hour
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** the settings are loaded
- **THEN** the background listening duration SHALL default to 1 hour

#### Scenario: User selects short durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "5 minutes", "15 minutes", or "30 minutes" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects medium durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "1 hour", "2 hours", "3 hours", or "6 hours" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects long durations
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "12 hours" or "24 hours" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL timeout after the selected duration

#### Scenario: User selects unlimited duration
- **GIVEN** the user opens the settings page
- **WHEN** the user selects "Unlimited" from the background listening duration dropdown
- **THEN** the setting SHALL be saved
- **AND** future listening sessions SHALL NOT automatically timeout

#### Scenario: Duration setting persists across app restarts
- **GIVEN** the user has set background listening duration to 2 hours
- **WHEN** the app is closed
- **AND** the app is reopened
- **THEN** the background listening duration SHALL still be 2 hours

#### Scenario: Duration setting applies to new sessions only
- **GIVEN** a listening session is currently active
- **WHEN** the user changes the background listening duration setting
- **THEN** the current session SHALL continue with the previous duration
- **AND** new listening sessions SHALL use the updated duration

### Requirement: Background Listening Duration Options
The system SHALL provide exactly ten duration options for background listening.

#### Scenario: Available duration options
- **GIVEN** the user opens the background listening duration setting
- **WHEN** the dropdown is displayed
- **THEN** the following options SHALL be available:
  - 5 minutes
  - 15 minutes
  - 30 minutes
  - 1 hour
  - 2 hours
  - 3 hours
  - 6 hours
  - 12 hours
  - 24 hours
  - Unlimited

#### Scenario: Duration values are immutable
- **GIVEN** the user views the background listening duration setting
- **WHEN** the user attempts to enter a custom duration
- **THEN** custom input SHALL NOT be possible
- **AND** only the predefined options SHALL be selectable

