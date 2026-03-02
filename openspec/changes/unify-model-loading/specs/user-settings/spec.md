## ADDED Requirements

### Requirement: Unavailable Model Warning on Settings Page
The settings page SHALL warn the user when the selected ASR or TTS model is not currently loaded and therefore unusable.

#### Scenario: Selected ASR model not loaded at startup
- **GIVEN** the user has a previously selected ASR model in settings
- **WHEN** the app starts and the selected model is not available (not yet extracted or missing from storage)
- **THEN** the settings page SHALL display a warning that no usable ASR model is selected
- **AND** the warning SHALL be visible in the Voice Models section

#### Scenario: Selected TTS model not loaded at startup
- **GIVEN** the user has a previously selected TTS model in settings
- **WHEN** the app starts and the selected model is not available (not yet extracted or missing from storage)
- **THEN** the settings page SHALL display a warning that no usable TTS model is selected
- **AND** the warning SHALL be visible in the Voice Models section

#### Scenario: Warning clears when model becomes available
- **GIVEN** the settings page shows an unavailable model warning
- **WHEN** the model finishes loading or seeding and becomes available
- **THEN** the warning SHALL disappear
- **AND** the settings page SHALL show the model as active
