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
