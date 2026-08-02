## REMOVED Requirements

### Requirement: Staged Model Selection with Save/Reset
**Reason**: An explicit Save step for model selection added friction the original goal never asked for — the actual intent was a fast, one-tap way to close the Voice Models screen. Model selection is instant again; a shared Apply action (see the new "Instant Model Selection with Shared Apply" requirement) covers closing the whole Settings flow in one tap, including any staged text/credential fields committed elsewhere.
**Migration**: No user data migration. The screen-scoped `pendingModelSelectionProvider` this requirement introduced was removed; model taps write directly to `settingsProvider` via `updateSelectedAsrModelId`/`updateSelectedTtsModelId`, same as before this requirement was ever added.

## ADDED Requirements

### Requirement: Instant Model Selection with Shared Apply
The catalog browser SHALL apply model selection immediately, and SHALL expose a shared Apply action that commits any other staged changes in the Settings flow and closes to Chat.

#### Scenario: Selecting a model applies immediately
- **WHEN** the user taps "Select" (or taps a card directly) on a downloaded catalog model or an imported model
- **THEN** that model SHALL become the active ASR or TTS model immediately
- **AND** the selection checkmark SHALL move to that card
- **AND** the selection SHALL persist across app restarts via SharedPreferences

#### Scenario: Back navigation is always instant
- **WHEN** the user presses the back arrow or Escape on the catalog browser
- **THEN** the screen SHALL close immediately
- **AND** no confirmation prompt SHALL be shown, regardless of any staged (unsaved) text or credential changes elsewhere in the Settings flow

#### Scenario: Apply commits and closes when the connection is verified
- **WHEN** the user presses Apply
- **AND** the currently-active connection settings are verified (or nothing is staged that requires verification)
- **THEN** any staged Connection-tab text fields SHALL be committed to persisted settings
- **AND** the app SHALL navigate directly to Chat

#### Scenario: Apply defers to Settings when the connection is unverified
- **WHEN** the user presses Apply
- **AND** the currently-active connection settings have changed since they were last verified
- **THEN** a confirmation SHALL be shown offering to review the connection settings or close anyway
- **AND** choosing to review SHALL return to the Settings page's Connection tab without committing or navigating away
- **AND** choosing to close anyway SHALL commit any staged Connection-tab text fields and navigate to Chat

#### Scenario: Download and Delete remain immediate
- **WHEN** the user downloads or deletes a model on the catalog browser
- **THEN** that action SHALL take effect immediately
- **AND** it SHALL NOT be affected by any staged, uncommitted Connection-tab changes
