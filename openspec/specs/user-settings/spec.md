## Purpose

Provide a settings UI for configuring backend connections, managing API key credentials, and selecting/managing ASR and TTS voice models.
## Requirements
### Requirement: URL Change Clears Session State

When a backend URL is changed, all session data associated with the previous URL becomes invalid and SHALL be cleared to prevent stale data or authentication errors.

#### Scenario: Engine URL change clears session data
- **GIVEN** the user has an active agentic session with messages
- **WHEN** the user changes the engine URL to a different value and saves
- **THEN** all session data SHALL be cleared
- **AND** the active session ID SHALL be reset to null
- **AND** all cached messages SHALL be cleared from memory

#### Scenario: Simple chat URL change clears chat history
- **GIVEN** the user has sent and received messages in simple chat
- **WHEN** the user changes the simple chat base URL and saves
- **THEN** all chat messages SHALL be cleared
- **AND** any pending requests SHALL be cancelled

#### Scenario: Engine URL change clears health check results
- **GIVEN** the engine health check has been performed and cached
- **WHEN** the user changes the engine URL to a different value and saves
- **THEN** cached health check results SHALL be cleared

### Requirement: API Key Indicator Fields in Settings

The system SHALL persist a boolean indicator for each backend's API key status in SharedPreferences. These indicators reflect whether an API key is stored in secure storage for the current URL, without exposing the key itself.

#### Scenario: engineHasApiKey defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `engineHasApiKey` SHALL be `false`

#### Scenario: simpleChatHasApiKey defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `simpleChatHasApiKey` SHALL be `false`

#### Scenario: engineHasApiKey persists across restarts
- **GIVEN** the user has saved an API key for the current engine URL
- **WHEN** the app is closed and reopened
- **THEN** `engineHasApiKey` SHALL still be `true`
- **AND** the settings page SHALL show the "API key saved" indicator

#### Scenario: Indicator reset when API key is cleared
- **GIVEN** `engineHasApiKey` is `true`
- **WHEN** the user clears the API key and saves
- **THEN** `engineHasApiKey` SHALL be set to `false`

### Requirement: API Key Credential Binding to URL

The system SHALL store API key credentials and basic auth credentials per URL in secure storage. When switching back to a previously-used URL, the stored auth configuration (auth type, username, API key indicator) SHALL be restored from the engine URL history.

#### Scenario: Engine URL change preserves auth config from history
- **GIVEN** the user has configured basic auth for URL A
- **AND** the user switches to URL B (which resets auth to none)
- **WHEN** the user switches back to URL A
- **THEN** the stored auth config for URL A SHALL be restored
- **AND** `engineAuthType` SHALL be `basic`
- **AND** `engineUsername` SHALL be restored
- **AND** `engineHasApiKey` SHALL reflect the stored indicator

#### Scenario: Engine URL change resets API key indicator for unknown URLs
- **GIVEN** `engineHasApiKey` is `true` for the current engine URL
- **WHEN** the user changes to a URL that has never been used before
- **THEN** `engineHasApiKey` SHALL be set to `false`
- **AND** `engineAuthType` SHALL be set to `none`

#### Scenario: Unknown URL resets auth to none
- **GIVEN** the user has no URL history
- **WHEN** the user enters a new engine URL and saves
- **THEN** `engineAuthType` SHALL be `none`
- **AND** `engineUsername` SHALL be null

#### Scenario: Simple chat URL change resets API key indicator
- **GIVEN** `simpleChatHasApiKey` is `true` for the current simple chat URL
- **WHEN** the user changes the simple chat base URL and saves
- **THEN** `simpleChatHasApiKey` SHALL be set to `false`
- **AND** the old API key SHALL be cleared from secure storage

#### Scenario: API key indicator not included in settings JSON serialization as a secret
- **GIVEN** settings are serialized for persistence
- **WHEN** the JSON representation is written to SharedPreferences
- **THEN** `engineHasApiKey` and `simpleChatHasApiKey` boolean values SHALL be included
- **AND** no actual API key string value SHALL appear in the serialized output

### Requirement: Engine URL History with Auth Configuration

The system SHALL persist a history of previously used engine URLs along with their associated auth configuration (auth type, username, API key indicator). The actual password and API key values remain in secure storage.

#### Scenario: History entry stores auth metadata
- **GIVEN** the user has configured engine URL A with basic auth and username "admin"
- **WHEN** the URL is saved
- **THEN** the history entry for URL A SHALL store `url`, `authType`, `username`, and `hasApiKey`

#### Scenario: History limited to 5 entries
- **GIVEN** the engine URL history contains 5 entries
- **WHEN** a new URL is saved
- **THEN** the oldest entry SHALL be removed
- **AND** the new entry SHALL be inserted at position 0

#### Scenario: Duplicate URL updates history position
- **GIVEN** the engine URL history contains URL A at position 2
- **WHEN** URL A is saved again
- **THEN** URL A SHALL be moved to position 0
- **AND** its auth config SHALL be updated to the current values

### Requirement: Model Management Settings Section
The settings page SHALL include a "Voice Models" section for managing ASR and TTS models.

#### Scenario: Section visible on voice-capable platforms
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the page is displayed
- **THEN** a "Voice Models" section SHALL be visible
- **AND** it SHALL show the currently active ASR and TTS models (or "None" if no model selected)

#### Scenario: Section hidden on web
- **GIVEN** the user opens the settings page on web
- **WHEN** the page is displayed
- **THEN** the "Voice Models" section SHALL NOT be displayed

#### Scenario: Browse available models
- **WHEN** the user taps a "Browse Models" action in the Voice Models section
- **THEN** the system SHALL display the model catalog filtered by type (ASR or TTS)
- **AND** each entry SHALL show: display name, supported languages, download size, and streaming indicator (for ASR)

#### Scenario: Download model from catalog
- **WHEN** the user taps download on a catalog entry
- **THEN** the system SHALL start downloading the model
- **AND** it SHALL show download progress in the catalog entry
- **AND** the user SHALL be able to cancel the download

#### Scenario: Select active model
- **WHEN** the user taps on a downloaded model
- **THEN** the system SHALL set it as the active ASR or TTS model
- **AND** the selection SHALL persist across app restarts via SharedPreferences

#### Scenario: Delete downloaded model
- **WHEN** the user requests deletion of a downloaded model
- **THEN** the system SHALL remove the model files from storage
- **AND** if the model was active, the system SHALL clear the selection

### Requirement: Startup Validation of Selected Models
On app startup, the system SHALL verify that selected ASR and TTS model IDs correspond to models that are actually available in download storage. Stale selections SHALL be cleared automatically.

#### Scenario: Selected ASR model still available
- **WHEN** the app starts
- **AND** the selected ASR model ID corresponds to a downloaded model
- **THEN** the selection SHALL be preserved unchanged

#### Scenario: Selected ASR model no longer available
- **WHEN** the app starts
- **AND** the selected ASR model ID does NOT correspond to a downloaded model
- **THEN** the ASR model selection SHALL be cleared to null
- **AND** the settings page SHALL show "None" for the active ASR model

#### Scenario: Selected TTS model no longer available
- **WHEN** the app starts
- **AND** the selected TTS model ID does NOT correspond to a downloaded model
- **THEN** the TTS model selection SHALL be cleared to null
- **AND** the settings page SHALL show "None" for the active TTS model

#### Scenario: No model selected at startup
- **WHEN** the app starts
- **AND** no ASR or TTS model is selected (both null)
- **THEN** no validation action SHALL be taken
- **AND** no errors SHALL be logged

#### Scenario: Validation runs after download scan completes
- **WHEN** the app starts
- **THEN** model validation SHALL occur after `ModelDownloadProvider` has completed its initial scan of download storage
- **AND** it SHALL NOT run while the scan is still in progress

### Requirement: Selected Model Persistence
The system SHALL persist the user's model selections in SharedPreferences.

#### Scenario: ASR model selection persists
- **GIVEN** the user has selected a downloaded ASR model
- **WHEN** the app is closed and reopened
- **THEN** the selected ASR model SHALL still be active

#### Scenario: TTS model selection persists
- **GIVEN** the user has selected a downloaded TTS model
- **WHEN** the app is closed and reopened
- **THEN** the selected TTS model SHALL still be active

#### Scenario: Selection cleared when model deleted
- **GIVEN** the user has selected a model that is subsequently deleted
- **WHEN** the app loads settings
- **THEN** the selection SHALL be cleared to null
- **AND** voice features SHALL be reported as unavailable until a new model is selected

### Requirement: Voice settings visible when available
The voice-related settings sections SHALL be conditionally visible based on platform voice capabilities and model availability. The settings page SHALL use a tabbed layout with voice settings on a dedicated "Voice" tab.

#### Scenario: Voice settings visible when available
- **GIVEN** the user opens the settings page on a platform with voice capabilities
- **WHEN** the user navigates to the Voice tab
- **THEN** voice model management (ASR and TTS) SHALL be displayed
- **AND** TTS-related settings (speaker, speed) SHALL be displayed

#### Scenario: Voice mode selector indicates model requirement
- **GIVEN** no ASR model is downloaded and selected
- **WHEN** the user views the Voice tab
- **THEN** it SHALL indicate that a model download is required to enable voice features
- **AND** it SHALL provide a shortcut to the model management section

### Requirement: Continuous voice enabled setting

The system SHALL persist a `continuousVoiceEnabled` boolean in the Settings model, defaulting to `false`.

#### Scenario: continuousVoiceEnabled defaults to false
- **GIVEN** the app is freshly installed or settings are reset
- **WHEN** settings are loaded
- **THEN** `continuousVoiceEnabled` SHALL be `false`

#### Scenario: continuousVoiceEnabled persists across restarts
- **GIVEN** the user has enabled continuous voice mode
- **WHEN** the app is closed and reopened
- **THEN** `continuousVoiceEnabled` SHALL still be `true`

#### Scenario: Migration from settings without continuousVoiceEnabled
- **GIVEN** persisted settings JSON does not contain `continuousVoiceEnabled`
- **WHEN** settings are deserialized
- **THEN** `continuousVoiceEnabled` SHALL default to `false`

### Requirement: Voice mode enforcement based on continuous voice toggle

The system SHALL prevent activation of continuous voice modes (`listening`, `conversation`) when `continuousVoiceEnabled` is `false`.

#### Scenario: Reject continuous mode when toggle is off
- **GIVEN** `continuousVoiceEnabled` is `false`
- **WHEN** `updateVoiceMode()` is called with `VoiceMode.listening` or `VoiceMode.conversation`
- **THEN** the voice mode SHALL NOT be changed
- **AND** it SHALL remain at the current mode

#### Scenario: Clamp voice mode when toggle is disabled
- **GIVEN** `continuousVoiceEnabled` is `true`
- **AND** the current voice mode is `listening` or `conversation`
- **WHEN** `continuousVoiceEnabled` is set to `false`
- **THEN** the voice mode SHALL be changed to `silent`

#### Scenario: Allow continuous modes when toggle is on
- **GIVEN** `continuousVoiceEnabled` is `true`
- **WHEN** `updateVoiceMode()` is called with `VoiceMode.listening` or `VoiceMode.conversation`
- **THEN** the voice mode SHALL be updated accordingly

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

