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
The catalog browser SHALL provide a filter control to show only downloaded models, making it easy to find locally available models for selection or deletion.

#### Scenario: Filter chip toggles downloaded-only view
- **WHEN** the user activates the "Downloaded" filter chip
- **THEN** the list SHALL show only models that are currently downloaded
- **AND** the search query SHALL continue to apply within the filtered set

#### Scenario: Filter chip disabled shows all models
- **WHEN** the "Downloaded" filter chip is not active
- **THEN** all catalog entries (subject to any active search query) SHALL be shown

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
