# feature-toggles Specification

## Purpose

Provide a dedicated "Features" tab in settings for opt-in experimental or platform-specific feature toggles. The tab is conditionally shown based on whether any applicable features exist for the current platform.

## Requirements

### Requirement: Features tab in settings

The settings page SHALL include a "Features" tab when there are applicable features for the current platform. The tab uses a `TabBar` navigation structure alongside "Connection" and optionally "Voice".

#### Scenario: Features tab visible on supported platforms
- **GIVEN** `VoiceCapabilities.isBackgroundListeningAvailable` is `true` (e.g., Android, Linux)
- **WHEN** the user opens the settings page
- **THEN** a "Features" tab SHALL be visible in the tab bar

#### Scenario: Features tab hidden on unsupported platforms
- **GIVEN** `VoiceCapabilities.isBackgroundListeningAvailable` is `false` (e.g., web)
- **WHEN** the user opens the settings page
- **THEN** the "Features" tab SHALL NOT be displayed
- **AND** no empty tab SHALL be shown

#### Scenario: Features tab content
- **WHEN** the user navigates to the Features tab
- **THEN** the tab SHALL display a list of feature toggles
- **AND** the first entry SHALL be the continuous voice mode toggle

### Requirement: Continuous voice mode toggle

The Features tab SHALL include a toggle for continuous voice modes, defaulting to off. The toggle SHALL be clearly marked as experimental.

#### Scenario: Toggle visible on supported platforms
- **GIVEN** `VoiceCapabilities.isBackgroundListeningAvailable` is `true` (e.g., Android, Linux)
- **WHEN** the user opens the Features tab
- **THEN** the continuous voice toggle SHALL be displayed

#### Scenario: Toggle defaults to off
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** the user opens the Features tab
- **THEN** the continuous voice mode toggle SHALL be off

#### Scenario: Toggle marked as experimental
- **WHEN** the user views the continuous voice toggle
- **THEN** the toggle title SHALL be "Continuous Voice"
- **AND** a label "(Experimental)" SHALL be displayed alongside the title
- **AND** a description SHALL read "Enables continuous recording and auto-playback modes. This feature is experimental and may be unreliable."
- **AND** platform info SHALL read "Background service currently implemented on Android only."

#### Scenario: Enabling the toggle
- **GIVEN** the continuous voice toggle is off
- **WHEN** the user enables the toggle
- **THEN** `continuousVoiceEnabled` SHALL be set to `true` and persisted
- **AND** the `VoiceModeSelector` SHALL become visible in the chat app bar
- **AND** the background listening duration setting SHALL appear below the toggle

#### Scenario: Disabling the toggle while in continuous mode
- **GIVEN** the continuous voice toggle is on
- **AND** the current voice mode is `listening` or `conversation`
- **WHEN** the user disables the toggle
- **THEN** `continuousVoiceEnabled` SHALL be set to `false` and persisted
- **AND** the voice mode SHALL be changed to `silent`
- **AND** any active continuous recording SHALL stop
- **AND** any active background audio service SHALL stop

#### Scenario: Background listening duration visible when enabled
- **GIVEN** the continuous voice toggle is on
- **WHEN** the user views the Features tab
- **THEN** the background listening duration dropdown SHALL be visible below the toggle

#### Scenario: Background listening duration hidden when disabled
- **GIVEN** the continuous voice toggle is off
- **WHEN** the user views the Features tab
- **THEN** the background listening duration dropdown SHALL NOT be visible

### Requirement: Settings tab structure

The settings page SHALL use a `TabBar` to organize settings into logical groups. Tabs are shown conditionally based on platform capabilities. The tab bar itself is hidden when only one tab applies.

#### Scenario: Full tab set on Android/Linux
- **WHEN** the user opens the settings page on a platform with voice and background listening
- **THEN** the tab bar SHALL display tabs in order: "Connection", "Voice", "Features"

#### Scenario: Reduced tabs on web
- **GIVEN** the app is running on web
- **WHEN** the user opens the settings page
- **THEN** only the "Connection" tab SHALL be displayed
- **AND** the tab bar SHALL NOT be shown (single tab needs no navigation header)

#### Scenario: Connection tab content
- **WHEN** the user views the Connection tab
- **THEN** it SHALL contain backend selection, URL/model configuration, authentication settings, and connection test controls

#### Scenario: Voice tab content
- **WHEN** the user views the Voice tab on a platform with voice capabilities
- **THEN** it SHALL contain voice model management (ASR and TTS) and TTS settings (speaker, speed)

#### Scenario: Fixed action bar
- **WHEN** the user opens the settings page
- **THEN** a fixed bar at the bottom SHALL display a "Reset" button and a "Save" button
- **AND** these SHALL be visible regardless of which tab is active
- **AND** "Reset" SHALL ask for confirmation before resetting all settings to defaults
- **AND** "Save" SHALL validate, persist all settings, and close the page
