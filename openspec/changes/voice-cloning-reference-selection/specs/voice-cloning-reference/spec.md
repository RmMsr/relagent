## Purpose

Allow users to select the reference audio that shapes the voice of a voice-cloning TTS model. The feature is surfaced in the Voice section of the settings page and is hidden when the active TTS model does not support voice cloning.

## Requirements

### Requirement: Reference Voice Picker in Voice Settings
The settings page SHALL show a reference voice picker in the Voice section when the active TTS model is a voice-cloning model (architecture `pocket`). The picker SHALL be hidden when any other TTS model is active.

#### Scenario: Picker visible with voice-cloning model active
- **GIVEN** the user has selected a downloaded Pocket TTS model
- **WHEN** the user opens the Voice section of the settings page
- **THEN** a "Reference voice" row SHALL be visible
- **AND** it SHALL display the name of the currently active reference voice

#### Scenario: Picker hidden with non-cloning model active
- **GIVEN** the user has selected a TTS model that is not a voice-cloning model
- **WHEN** the user opens the Voice section of the settings page
- **THEN** no reference voice row SHALL be displayed

#### Scenario: Picker hidden with no TTS model active
- **GIVEN** no TTS model is selected
- **WHEN** the user opens the Voice section of the settings page
- **THEN** no reference voice row SHALL be displayed

### Requirement: Bundled Model Voices
The picker SHALL list the reference audio samples bundled with the active Pocket TTS model (files in the model's `test_wavs/` directory), labelled under a "Model voices" section.

#### Scenario: Model voices listed
- **GIVEN** the user opens the reference voice picker
- **THEN** a "Model voices" section SHALL appear containing one entry per `.wav` file found in `test_wavs/` of the active model
- **AND** each entry SHALL be labelled by the filename stem (e.g., `bria.wav` → "Bria")

#### Scenario: No model voices available
- **GIVEN** the active model has no `test_wavs/` directory or it contains no `.wav` files
- **WHEN** the user opens the reference voice picker
- **THEN** the "Model voices" section SHALL be empty or absent
- **AND** the picker SHALL still show the "My voices" section

#### Scenario: Active model voice indicated
- **GIVEN** the current reference voice is a bundled model voice
- **WHEN** the user opens the picker
- **THEN** that entry SHALL show a check mark

### Requirement: User Custom Voice Library
The picker SHALL allow the user to maintain a personal library of imported audio files under a "My voices" section.

#### Scenario: Import custom voice
- **WHEN** the user taps "Add voice…" in the picker
- **THEN** the system SHALL open the native file-open dialog
- **AND** on selection the file SHALL be copied to app-managed storage
- **AND** the imported file SHALL appear in "My voices" with its filename as label
- **AND** it SHALL become the active reference voice

#### Scenario: Multiple custom voices
- **GIVEN** the user has previously imported one or more voices
- **WHEN** the user imports another voice
- **THEN** all previously imported voices SHALL remain in the library

#### Scenario: Delete custom voice
- **WHEN** the user deletes a custom voice from "My voices"
- **THEN** the underlying file SHALL be removed from app storage
- **AND** the entry SHALL be removed from the library
- **AND** if that voice was active, the system SHALL reset the reference to the model default

#### Scenario: Active custom voice indicated
- **GIVEN** the current reference voice is a user-imported file
- **WHEN** the user opens the picker
- **THEN** that entry SHALL show a check mark

### Requirement: Reference Voice Selection
Tapping an entry in the picker sets it as the active reference voice and triggers TTS worker reinitialization.

#### Scenario: Select model voice
- **WHEN** the user taps a model voice entry
- **THEN** `ttsReferenceVoicePath` SHALL be set to the absolute path of that file
- **AND** the TTS worker SHALL reinitialize with the new reference
- **AND** the picker SHALL close

#### Scenario: Select custom voice
- **WHEN** the user taps a custom voice entry
- **THEN** `ttsReferenceVoicePath` SHALL be set to the path of the copied file in app storage
- **AND** the TTS worker SHALL reinitialize with the new reference
- **AND** the picker SHALL close

### Requirement: Reference Voice Reset on Model Change
When the active TTS model changes, the saved reference voice SHALL be validated against the new model and reset if no longer applicable.

#### Scenario: Bundled reference invalidated by model switch
- **GIVEN** `ttsReferenceVoicePath` points to a bundled model voice
- **WHEN** the user switches to a different TTS model
- **THEN** `ttsReferenceVoicePath` SHALL be set to `null`
- **AND** the new model's first bundled reference SHALL be used as the effective default

#### Scenario: Custom reference survives model switch
- **GIVEN** `ttsReferenceVoicePath` points to a user-imported file in app storage
- **WHEN** the user switches to a different Pocket TTS model
- **THEN** `ttsReferenceVoicePath` SHALL remain unchanged
- **AND** the custom file SHALL continue to be used as the reference

#### Scenario: Reference unchanged when switching to non-cloning model
- **GIVEN** `ttsReferenceVoicePath` is set
- **WHEN** the user switches to a non-voice-cloning TTS model
- **THEN** `ttsReferenceVoicePath` SHALL remain stored but SHALL be ignored by the TTS pipeline

### Requirement: Effective Reference Display
The "Reference voice" row in settings SHALL always show the name of the voice that will actually be used, not the stored path.

#### Scenario: Stored path valid
- **GIVEN** `ttsReferenceVoicePath` points to an existing file
- **WHEN** the settings page displays the reference voice row
- **THEN** it SHALL show the filename stem of that file

#### Scenario: No reference set (model default)
- **GIVEN** `ttsReferenceVoicePath` is `null`
- **WHEN** the settings page displays the reference voice row
- **THEN** it SHALL show the name of the model's first bundled reference voice
