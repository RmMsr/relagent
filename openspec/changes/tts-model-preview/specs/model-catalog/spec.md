## ADDED Requirements

### Requirement: TTS Model Preview Action
Downloaded TTS model cards in the catalog browser SHALL show a Preview action that triggers on-demand synthesis and playback.

#### Scenario: Preview button visible on downloaded TTS card
- **WHEN** a TTS model is downloaded and its card is displayed
- **THEN** a Preview button SHALL be visible on the card
- **AND** the button SHALL be absent for models that are not yet downloaded

#### Scenario: Preview button shows loading state
- **WHEN** the user taps Preview and the preview worker is initializing or generating
- **THEN** the Preview button SHALL show a loading indicator
- **AND** it SHALL NOT be tappable a second time while loading

### Requirement: RTF Speed Gauge on Model Cards
TTS model cards SHALL display a compact color-coded speed gauge when a benchmark result is available for that model.

#### Scenario: Gauge shown when benchmark exists
- **WHEN** a TTS model card is displayed and a benchmark RTF value is stored for that model
- **THEN** a color-coded speed gauge SHALL appear on the card

#### Scenario: Green gauge for fast models
- **WHEN** a model's stored RTF is less than or equal to 0.90
- **THEN** the gauge SHALL be rendered in green

#### Scenario: Amber gauge for marginal models
- **WHEN** a model's stored RTF is greater than 0.90 and less than or equal to 1.10
- **THEN** the gauge SHALL be rendered in amber

#### Scenario: Red gauge for slow models
- **WHEN** a model's stored RTF is greater than 1.10
- **THEN** the gauge SHALL be rendered in red

#### Scenario: No gauge when benchmark absent
- **WHEN** a TTS model card is displayed and no benchmark has been recorded
- **THEN** no speed gauge SHALL be shown on the card
