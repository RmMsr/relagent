## ADDED Requirements

### Requirement: Voice Cloning Capability Indicator on Model Cards
The catalog browser SHALL display a non-interactive indicator on TTS model cards that support voice cloning, so users can identify which models offer voice customization before downloading.

#### Scenario: Indicator shown on Pocket TTS model card
- **WHEN** a Pocket TTS model card is displayed in the catalog browser
- **THEN** it SHALL show a "Voice cloning" label or badge
- **AND** this indicator SHALL be non-interactive (no tap target, no controls)

#### Scenario: Indicator absent on non-cloning TTS models
- **WHEN** a TTS model card is displayed for a model that does not support voice cloning
- **THEN** no voice cloning indicator SHALL be shown

#### Scenario: Indicator visible regardless of download status
- **WHEN** a Pocket TTS model card is displayed, whether the model is downloaded or not
- **THEN** the voice cloning indicator SHALL be visible
