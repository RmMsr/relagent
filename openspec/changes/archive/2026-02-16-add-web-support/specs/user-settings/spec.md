## MODIFIED Requirements

### Requirement: Settings Page Layout

The system SHALL organize settings into sections, with voice-related sections conditionally visible based on platform voice capabilities.

#### Scenario: Engine settings section
- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** an "Engine" section SHALL be visible
- **AND** it SHALL contain Engine URL and authentication settings

#### Scenario: Simple chat settings section
- **GIVEN** the user opens the settings page
- **WHEN** the page is displayed
- **THEN** the existing "API" section for simple chat SHALL remain available
- **AND** both sections SHALL be clearly labeled

#### Scenario: Voice settings hidden when unavailable
- **GIVEN** the user opens the settings page on a platform without voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL NOT be displayed
- **AND** the background listening duration setting SHALL NOT be displayed
- **AND** TTS-related settings (speaker, speed) SHALL NOT be displayed

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** the voice mode selector SHALL be displayed
- **AND** the background listening duration setting SHALL be displayed
- **AND** TTS-related settings SHALL be displayed

### Requirement: Background Listening Duration Setting
The system SHALL provide a user setting to configure the maximum duration for background listening sessions. This setting SHALL only be visible on platforms with voice capabilities.

#### Scenario: Default duration is one hour
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** the settings are loaded
- **THEN** the background listening duration SHALL default to 1 hour

#### Scenario: Setting hidden on web
- **GIVEN** the user opens the settings page on web
- **WHEN** the page is displayed
- **THEN** the background listening duration dropdown SHALL NOT be visible

#### Scenario: Duration setting persists across app restarts
- **GIVEN** the user has set background listening duration to 2 hours
- **WHEN** the app is closed
- **AND** the app is reopened
- **THEN** the background listening duration SHALL still be 2 hours
