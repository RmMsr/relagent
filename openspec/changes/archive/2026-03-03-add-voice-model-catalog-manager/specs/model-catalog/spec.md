## ADDED Requirements

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
