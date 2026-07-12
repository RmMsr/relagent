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
