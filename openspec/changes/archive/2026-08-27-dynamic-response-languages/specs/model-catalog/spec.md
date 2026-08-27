## ADDED Requirements

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
