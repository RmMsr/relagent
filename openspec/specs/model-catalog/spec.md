## Purpose

Provide users with a curated catalog of recommended ASR and TTS models with filtering by language and download status tracking.
## Requirements
### Requirement: Curated Model Registry
The system SHALL provide a hardcoded catalog of recommended sherpa-onnx models for ASR and TTS.

#### Scenario: Catalog entry metadata
- **WHEN** a catalog entry is accessed
- **THEN** it SHALL contain: id, display name, type (asr/tts), languages (list of language codes), architecture, download URL, download size in MB, and file structure description

#### Scenario: ASR catalog entries include streaming indicator
- **WHEN** an ASR catalog entry is accessed
- **THEN** it SHALL indicate whether the model supports streaming (live recognition)
- **AND** this information SHALL be visible to the user when browsing models

#### Scenario: Catalog covers target languages
- **WHEN** the catalog is loaded
- **THEN** it SHALL include at least one ASR model supporting English, German, Norwegian, Swedish, French, and Russian
- **AND** it SHALL include at least one TTS model for each of those languages

### Requirement: Language-Based Model Filtering
The system SHALL allow filtering the model catalog by language.

#### Scenario: Filter by single language
- **WHEN** the user selects a language filter
- **THEN** the catalog SHALL show only models that support that language

#### Scenario: Show all models
- **WHEN** no language filter is active
- **THEN** the catalog SHALL show all available models grouped by type (ASR, TTS)

### Requirement: Model Download Status in Catalog
The catalog SHALL indicate the download status of each model.

#### Scenario: Model not downloaded
- **WHEN** a catalog entry is displayed and the model is not on device
- **THEN** it SHALL show a download action with the download size

#### Scenario: Model downloaded
- **WHEN** a catalog entry is displayed and the model is on device
- **THEN** it SHALL indicate the model is available
- **AND** it SHALL show a delete action

#### Scenario: Model currently downloading
- **WHEN** a catalog entry is displayed and the model is being downloaded
- **THEN** it SHALL show the download progress percentage

### Requirement: Scroll to Selected Model on Open
When the model catalog browser is opened, the list SHALL scroll to the currently selected model so the user immediately sees their active choice without manual scrolling.

#### Scenario: Selected model visible on open
- **GIVEN** a model is selected (ASR or TTS)
- **WHEN** the catalog browser is opened on the corresponding tab
- **THEN** the list SHALL be initially positioned so the selected model card is visible near the top of the viewport

#### Scenario: No selection leaves list at top
- **GIVEN** no model is selected for the active tab
- **WHEN** the catalog browser is opened
- **THEN** the list SHALL start at the top

### Requirement: Downloaded-Only Filter
The catalog browser SHALL provide a filter control to show only locally available models, making it easy to find models that are ready to use for selection or deletion. Locally available models include both downloaded catalog models and all imported models.

#### Scenario: Filter chip toggles locally-available view
- **WHEN** the user activates the "Downloaded" filter chip
- **THEN** the list SHALL show downloaded catalog models and all imported models
- **AND** the search query SHALL continue to apply within the filtered set

#### Scenario: Filter chip disabled shows all models
- **WHEN** the "Downloaded" filter chip is not active
- **THEN** all catalog entries and all imported entries (subject to any active search query) SHALL be shown

### Requirement: Imported Models Shown First in Catalog Browser
The catalog browser SHALL display imported models above catalog models within each type tab, sorted by most-recently-imported first. Within the catalog group, existing ordering (recommended first, then alphabetical) is unchanged.

#### Scenario: Imported models lead the list
- **WHEN** the catalog browser is open and imported models exist for the active type tab
- **THEN** imported model cards SHALL appear at the top of the list before any catalog entries

#### Scenario: Most recently imported appears first within imports group
- **WHEN** multiple imported models exist for the active type tab
- **THEN** they SHALL be ordered with the most recently imported model at the top

#### Scenario: No imported models leaves catalog ordering unchanged
- **WHEN** no imported models exist for the active type tab
- **THEN** catalog entries SHALL appear in their existing order (recommended first, then alphabetical)

### Requirement: Imported Model Visual Distinction
Imported model cards SHALL carry a visible "Imported" badge so the user can distinguish them from curated catalog entries.

#### Scenario: Badge visible on imported card
- **WHEN** an imported model card is displayed
- **THEN** it SHALL show an "Imported" label or chip
- **AND** fields absent from the import (e.g., download size, origin) SHALL be omitted rather than shown as empty

#### Scenario: Catalog cards show no imported badge
- **WHEN** a catalog model card is displayed
- **THEN** it SHALL NOT show an "Imported" badge

### Requirement: Import Action in Catalog Browser
The catalog browser SHALL provide an action to trigger the local model import flow.

#### Scenario: Import button visible in browser
- **WHEN** the catalog browser is open
- **THEN** an "Import from storage" button or action SHALL be accessible without leaving the screen

#### Scenario: Import action opens file picker
- **WHEN** the user activates the import action
- **THEN** the local model import flow SHALL begin (file picker opens)

### Requirement: Imported Model Deletion from Browser
The catalog browser SHALL allow the user to delete an imported model, consistent with how downloaded catalog models can be deleted.

#### Scenario: Delete action on imported card
- **WHEN** an imported model card is displayed
- **THEN** it SHALL show a delete action

#### Scenario: Deletion confirmed removes model from list
- **WHEN** the user confirms deletion of an imported model
- **THEN** the card SHALL disappear from the catalog browser
- **AND** a confirmation message SHALL be shown

### Requirement: Download Completion Notification
The catalog browser SHALL notify the user when a model download completes successfully.

#### Scenario: Snackbar shown on completion
- **WHEN** a model download finishes successfully while the catalog browser is open
- **THEN** a snackbar SHALL appear showing the model's display name and a "downloaded" confirmation
- **AND** it SHALL dismiss automatically after a short duration

### Requirement: Model ID Visible in Settings
The settings page Voice section SHALL display both the display name and the model ID of the currently active ASR and TTS models.

#### Scenario: Selected model shows id and display name
- **GIVEN** a downloaded model is active
- **WHEN** the user views the Voice section of the settings page
- **THEN** the model tile subtitle SHALL show the display name and size on the first line
- **AND** the model id SHALL appear below in a smaller muted style

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

### Requirement: Model Toggle Checkbox, One Shared Widget for Both Types
Each downloaded/available model card — ASR or TTS — SHALL provide a single checkbox, the same widget for both types, whose meaning differs by type: for TTS, assigning the model to its (first declared) playback language; for ASR, adding the model to the mic long-press quick-pick set (see the `asr-language-selection` capability). The checkbox behaves identically regardless of how many languages the model declares — there is no per-language toggle row for either type. Neither type shows a "Select" button, single-active-model checkmark, or whole-card tap-to-select action — the checkbox and the default control (below) replace that concept entirely.

#### Scenario: One checkbox regardless of declared language count
- **GIVEN** a downloaded model (either type) declares one language, several languages, or the unenumerable "multi" sentinel
- **WHEN** its card is displayed
- **THEN** it SHALL show at most one checkbox, with the same control and the same behavior regardless of how many languages it declares

#### Scenario: Checking a TTS model's checkbox assigns its language
- **WHEN** the user checks a downloaded TTS model's checkbox
- **THEN** the model SHALL be assigned to its first declared language
- **AND** unchecking it SHALL remove that assignment

#### Scenario: TTS model with only the unenumerable "multi" sentinel shows no checkbox
- **GIVEN** a downloaded TTS model's only listed language is the "multi" sentinel
- **WHEN** its card is displayed
- **THEN** no checkbox SHALL be shown for it, since there is no concrete language to assign

#### Scenario: Checking an ASR model's checkbox adds it to the quick-pick set
- **WHEN** the user checks a downloaded ASR model's checkbox
- **THEN** the model SHALL be added to the mic long-press quick-pick set
- **AND** unchecking it SHALL remove it from that set

#### Scenario: Checkbox only shown for downloaded/available models
- **WHEN** a model card is displayed for a model that is not downloaded (or, for imported models, not available)
- **THEN** the checkbox SHALL NOT be shown

#### Scenario: No Select control or whole-card tap on either type
- **WHEN** a model card is displayed, ASR or TTS
- **THEN** it SHALL NOT show a "Select" button, a single-active-model checkmark, or respond to a tap on the card body as a selection action

### Requirement: Default Control, Same Widget for Both Model Types
Each downloaded/available model card — ASR or TTS — SHALL provide a wildcard (star) control marking it the persisted device default for its type, using the same widget and interaction for both. The meaning differs by type: for TTS, the model used when no language-specific assignment matches a response; for ASR, the model used when no session-only quick-pick override is active (see `asr-language-selection`'s resolution chain — the quick-pick override does not persist across app restarts, but the default does).

#### Scenario: Marking a model as default
- **WHEN** the user activates the default control on a downloaded model card (either type)
- **THEN** that model SHALL become the device default for its type
- **AND** any previously marked default card of the same type SHALL reflect it is no longer the default

#### Scenario: Default control shares its widget across types
- **GIVEN** an ASR card and a TTS card are both displayed
- **WHEN** each has its default control shown
- **THEN** both SHALL use the same control widget and icon

### Requirement: Consistent Selected-State Visuals Across ASR and TTS
The catalog browser SHALL use the same visual treatment (card background and elevation) to indicate a card is "selected" on both the ASR and TTS tabs. "Selected" means: for TTS, assigned to a language or marked default; for ASR, in the quick-pick set or marked default. Both are the same shape of condition — "referenced by an active preference, of either kind" — so the same highlight rule applies uniformly.

#### Scenario: Card highlighted when assigned/enabled or default
- **GIVEN** a model (either type) is assigned to a language / in the quick-pick set, marked default, or both
- **WHEN** its card is displayed
- **THEN** it SHALL use the highlighted background/elevation style

#### Scenario: Card not highlighted otherwise
- **GIVEN** a model has no language assignment / is not in the quick-pick set, and is not the default
- **WHEN** its card is displayed
- **THEN** it SHALL NOT use the highlighted style

### Requirement: Secondary Actions Positioned Bottom-Left
On both ASR and TTS model cards, secondary row actions (Delete, and Edit for imported models) SHALL be positioned at the bottom-left of the card, below the model's metadata.

#### Scenario: Delete and Edit bottom-left on an imported card
- **WHEN** an imported model card is displayed
- **THEN** its Edit and Delete actions SHALL appear at the bottom-left of the card

#### Scenario: Delete bottom-left on a catalog card
- **WHEN** a downloaded catalog model card is displayed
- **THEN** its Delete action SHALL appear at the bottom-left of the card

### Requirement: Single Filter Control
The catalog browser SHALL provide one filter control offering "All", "Downloaded", and "Selected" as mutually exclusive options, replacing separate independent filter toggles. "Selected" uses the same per-type definition as the card-highlight requirement above: for TTS, assigned to a language or marked default; for ASR, in the quick-pick set or marked default.

#### Scenario: All shows every model
- **WHEN** the filter is set to "All"
- **THEN** every catalog and imported entry (subject to any active search query) SHALL be shown

#### Scenario: Downloaded shows only locally available models
- **WHEN** the filter is set to "Downloaded"
- **THEN** the list SHALL show downloaded catalog models and all imported models
- **AND** the search query SHALL continue to apply within the filtered set

#### Scenario: Selected shows only assigned/enabled/default models
- **WHEN** the filter is set to "Selected"
- **THEN** the list SHALL show only models (of the currently displayed type) that are assigned to a language / in the quick-pick set, or marked as the default
- **AND** the search query SHALL continue to apply within the filtered set

#### Scenario: Selected filter with nothing set shows an empty list
- **WHEN** the filter is set to "Selected"
- **AND** no model of the currently displayed type is assigned/enabled or marked default
- **THEN** the list SHALL be empty

### Requirement: Language Mapping Summary in Settings (TTS)
The settings page's Text-to-Speech entry SHALL show a list with one row per language-to-model assignment, rather than a single active-model summary. The device default SHALL be indicated. Rows SHALL NOT show an "Imported" tag regardless of whether the assigned model is a catalog or imported model.

#### Scenario: One row per language assignment
- **WHEN** the settings page's Voice tab is displayed
- **AND** one or more languages have an assigned TTS model
- **THEN** the Text-to-Speech entry SHALL show one row per assigned language, naming the language and the assigned model

#### Scenario: Default indicated
- **GIVEN** a TTS model is marked as the device default
- **WHEN** the settings page's Voice tab is displayed
- **THEN** the row for that model (or a dedicated row, if the default is not otherwise assigned to any language) SHALL indicate it is the default

#### Scenario: No imported tag in the summary
- **GIVEN** a language is assigned to an imported TTS model
- **WHEN** the settings page's Voice tab is displayed
- **THEN** that row SHALL show the model's plain name only, with no "Imported" tag

#### Scenario: Nothing assigned shows None
- **GIVEN** no language is assigned and no default is set
- **WHEN** the settings page's Voice tab is displayed
- **THEN** the Text-to-Speech entry SHALL show "None"

### Requirement: Quick-Pick Model Summary in Settings (ASR)
The settings page's Speech Recognition entry SHALL show a list with one row per quick-pick-enabled ASR model, naming the model and its declared language coverage — mirroring the structure of the TTS mapping summary, but keyed by model rather than by language. The persisted device default SHALL be indicated. The current session's active quick-pick override (if any) SHALL be indicated. Rows SHALL NOT show an "Imported" tag.

#### Scenario: One row per quick-pick model
- **WHEN** the settings page's Voice tab is displayed
- **AND** one or more ASR models are in the quick-pick set
- **THEN** the Speech Recognition entry SHALL show one row per quick-pick model, naming the model and its language coverage

#### Scenario: Default indicated
- **GIVEN** an ASR model is marked as the device default
- **WHEN** the settings page's Voice tab is displayed
- **THEN** the row for that model (or a dedicated row, if the default is not otherwise in the quick-pick set) SHALL indicate it is the default

#### Scenario: Active quick-pick model indicated
- **GIVEN** an ASR model is this session's active quick-pick override
- **WHEN** the settings page's Voice tab is displayed
- **THEN** that row SHALL indicate it is currently active

#### Scenario: No imported tag in the ASR summary
- **GIVEN** an imported ASR model is in the quick-pick set
- **WHEN** the settings page's Voice tab is displayed
- **THEN** that row SHALL show the model's plain name only, with no "Imported" tag

#### Scenario: Nothing enabled shows None
- **GIVEN** no ASR model is in the quick-pick set and no default is set
- **WHEN** the settings page's Voice tab is displayed
- **THEN** the Speech Recognition entry SHALL show "None"

