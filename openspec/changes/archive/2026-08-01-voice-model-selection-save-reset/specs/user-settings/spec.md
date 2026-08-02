## ADDED Requirements

### Requirement: Instant-Apply Selection and Toggle Fields
Chat backend selection, continuous-voice enablement, background-listening duration, and TTS speed/speaker on the Settings page SHALL apply immediately on change, without requiring the Apply action.

#### Scenario: Backend switch applies immediately
- **WHEN** the user selects a different chat backend in the segmented control
- **THEN** `selectedBackend` SHALL be updated and persisted immediately
- **AND** the Connection tab SHALL switch to showing that backend's fields without requiring Apply

#### Scenario: Continuous voice toggle applies immediately
- **WHEN** the user toggles Continuous Voice on or off
- **THEN** `continuousVoiceEnabled` SHALL be updated and persisted immediately

#### Scenario: Background listening duration applies immediately
- **WHEN** the user selects a different Background Listening Duration
- **THEN** `backgroundListeningDuration` SHALL be updated and persisted immediately

#### Scenario: TTS speed and speaker apply immediately
- **WHEN** the user drags the TTS Speed or TTS Speaker ID slider
- **THEN** `ttsSpeed` or `ttsSpeakerId` SHALL be updated and persisted immediately

### Requirement: Apply Action Commits and Closes Settings

The Settings page SHALL expose a single Apply action that commits any staged Connection-tab text fields and credentials, then navigates to Chat.

#### Scenario: Apply commits staged text fields and credentials
- **WHEN** the user has edited the chat base URL, chat model name, prime message, and/or engine base URL, and/or entered new credentials
- **AND** the user presses Apply
- **THEN** the staged text fields SHALL be written to persisted settings
- **AND** any newly-entered credentials SHALL be written to secure storage
- **AND** the app SHALL navigate to Chat once the connection-verification gate (see "Connection Verification Gate on Apply") allows it

#### Scenario: Engine base URL is committed before engine credentials
- **GIVEN** the user has entered both a new engine base URL and new engine credentials (password and/or API key) in the same Apply
- **WHEN** Apply commits the changes
- **THEN** the engine base URL SHALL be committed before the engine credential writes
- **AND** the new credentials SHALL be stored keyed to the new URL, not the URL that was active when the screen was opened

#### Scenario: Apply is a no-op commit when nothing is staged
- **WHEN** the user presses Apply with no staged text/credential changes
- **THEN** no write to persisted settings or secure storage SHALL occur
- **AND** the app SHALL navigate to Chat

### Requirement: Connection Verification Gate on Apply

Apply SHALL be gated by whether the currently-active connection settings have been verified since they last changed, so an untested credential or URL change is never shipped silently.

#### Scenario: Verified connection skips the live check
- **GIVEN** the currently-active connection settings have already passed a health check since they last changed (or nothing credential/URL-relevant has changed at all)
- **WHEN** the user presses Apply
- **THEN** no live health check SHALL be run
- **AND** the app SHALL navigate to Chat immediately after committing any staged changes

#### Scenario: Unverified connection triggers a live check on Settings
- **GIVEN** a credential, URL, or backend-relevant field has changed since the connection was last verified
- **WHEN** the user presses Apply on the Settings page
- **THEN** a live health check SHALL be run for the active backend before navigating away
- **AND** if the check fails, a prompt SHALL offer to review settings or close anyway instead of navigating immediately

#### Scenario: A credential/URL edit invalidates prior verification
- **GIVEN** the connection was previously verified
- **WHEN** the user edits the active backend's base URL, username, password, or API key, or switches backends
- **THEN** the connection SHALL be considered unverified again until the next successful check

### Requirement: Unsaved Changes Guard on Back Navigation

The Settings page's back navigation SHALL warn before discarding staged Connection-tab text or credential changes; no other screen in the Settings flow SHALL show this warning.

#### Scenario: Back navigation warns when something is staged
- **WHEN** the user presses the Settings page's back arrow (or Escape) with staged text or credential changes present
- **THEN** a confirmation SHALL be shown offering to cancel or leave anyway
- **AND** choosing to leave anyway SHALL discard the staged changes and navigate back
- **AND** choosing to cancel SHALL leave the staged changes intact and stay on the page

#### Scenario: Back navigation is instant when nothing is staged
- **WHEN** the user presses the Settings page's back arrow (or Escape) with no staged changes
- **THEN** the page SHALL close immediately with no confirmation

#### Scenario: Nested screens never show the discard warning
- **WHEN** the user presses back on a screen pushed from Settings (e.g. Voice Models)
- **THEN** it SHALL close immediately regardless of any staged Connection-tab changes
- **AND** those staged changes SHALL remain intact on the Settings page underneath, not discarded
