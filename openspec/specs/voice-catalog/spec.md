## Purpose

Define the `voice-catalog` CLI tool that automates discovery, filtering, and evaluation of sherpa-onnx models, keeping `apps/assets/voice-models.json` up to date as new releases appear upstream.

## Requirements

### Requirement: Pure Dart CLI Entry Point
The `voice-catalog` tool SHALL be a standalone pure Dart package at `tools/voice_catalog/` invoked via the shell script `bin/voice-catalog`. Phases are enabled by explicit flags (`--discover`, `--eval`); running without flags SHALL print help and exit. The tool SHALL exit with code 0 on success and non-zero on unrecoverable error.

#### Scenario: No arguments prints help
- **WHEN** the tool is invoked with no arguments
- **THEN** it SHALL print the usage text including all flags and filter criteria
- **AND** it SHALL exit without modifying `voice-models.json`

#### Scenario: Tool runs to completion and exits
- **WHEN** the enabled phases complete
- **THEN** it SHALL write the updated `voice-models.json` and print a summary
- **AND** it SHALL list counts of discovered, filtered, and evaluated entries

#### Scenario: Language filter is configurable
- **WHEN** the tool is invoked with `--lang <code>` (repeatable, or comma-separated)
- **THEN** only entries matching at least one specified language SHALL be candidates for evaluation
- **AND** the default language when no `--lang` is given SHALL be `en`

#### Scenario: Downloads cleaned up after each evaluation
- **WHEN** an entry completes evaluation (pass or fail)
- **THEN** the downloaded model directory SHALL be deleted from the cache
- **UNLESS** `--keep` was passed, in which case downloads SHALL be retained

### Requirement: Discovery Phase
The tool SHALL fetch the GitHub releases API for the `asr-models` and `tts-models` tags on `k2-fsa/sherpa-onnx` and parse the asset list to extract model metadata from filenames.

#### Scenario: New model assets are added to the registry
- **WHEN** the GitHub releases API returns assets not present in `voice-models.json`
- **THEN** each new asset SHALL be added as an entry with `status: "untested"` and metadata inferred from the filename
- **AND** `voice-models.json` SHALL be updated before the filter phase begins

#### Scenario: Existing entries are not overwritten by discovery
- **WHEN** the GitHub releases API returns an asset whose `id` already exists in `voice-models.json`
- **THEN** the existing entry SHALL be left unchanged
- **AND** the tool SHALL NOT reset `status`, `recommended`, or `notes` on existing entries

#### Scenario: Kokoro multilingual models are correctly classified
- **WHEN** the discovery phase parses a Kokoro model filename containing `multi-lang`
- **THEN** the entry's `languages` SHALL be set to all languages supported by Kokoro multilingual (de, en, es, fr, hi, it, ja, ko, pt, zh)
- **AND** `architecture` SHALL be `kokoro`

#### Scenario: GitHub API is unreachable
- **WHEN** the GitHub releases API request fails with a network error
- **THEN** the tool SHALL print a warning and proceed using only the existing `voice-models.json` entries
- **AND** it SHALL NOT overwrite the file with partial data

### Requirement: Filter Phase
The tool SHALL apply hard filter criteria to all `untested` entries and skip those that cannot be suitable for the project, recording a failure note without downloading.

#### Scenario: License is shown but not filtered
- **WHEN** the filter phase runs
- **THEN** the license distribution of passing candidates SHALL be printed to the log
- **AND** license SHALL NOT be used as an exclusion criterion

#### Scenario: Oversized model is excluded
- **WHEN** a model entry has `downloadSizeMb` greater than 1000
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: size <value>MB exceeds 1GB limit"`

#### Scenario: Non-matching language is excluded
- **WHEN** a model entry's `languages` array has no overlap with the `--lang` codes in effect
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: no matching language"`

#### Scenario: Low-quality Piper model is excluded
- **WHEN** a Piper TTS model's filename contains `_low` or `x_low` quality suffix
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: quality below medium"`

#### Scenario: Unsupported architecture is excluded
- **WHEN** a model's inferred architecture does not map to any `ModelArchitecture` enum value
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: unsupported architecture"`

### Requirement: Evaluate Phase
The tool SHALL download and smoke-test each `untested` entry that passes the filter phase, using the same code paths as the app.

#### Scenario: ASR model loads and produces output
- **WHEN** an untested ASR model passes all filters
- **THEN** the tool SHALL download it via `ModelDownloadService`
- **AND** initialize it via `createOnlineRecognizerFromMetadata` or `createOfflineRecognizerFromMetadata` depending on architecture
- **AND** run inference on a short reference WAV clip for the model's primary language
- **AND** verify the output is a non-empty string
- **AND** record latency in milliseconds in `notes`

#### Scenario: TTS model loads and produces output
- **WHEN** an untested TTS model passes all filters
- **THEN** the tool SHALL download it via `ModelDownloadService`
- **AND** initialize it via `buildTtsConfig` from the shared `sherpa_voice` package
- **AND** synthesize a short reference sentence in the model's primary language
- **AND** verify the output audio buffer is non-empty
- **AND** record latency in milliseconds in `notes`

#### Scenario: Pocket TTS model uses reference audio for evaluation
- **WHEN** an untested Pocket TTS model (`architecture == pocket`) is evaluated
- **THEN** the evaluator SHALL scan the extracted model's `test_wavs/` directory for `.wav` files
- **AND** load the shortest-named WAV file as the reference audio for `generateWithConfig`
- **AND** the resolved path SHALL be recorded as `fileStructure.referenceWav` in the catalog entry

#### Scenario: Directory inspection records fileStructure
- **WHEN** the evaluator inspects a downloaded model's directory
- **THEN** it SHALL populate the entry's `fileStructure` map with all required model file paths
- **AND** for Pocket TTS models, it SHALL additionally include `referenceWav` pointing to a bundled sample voice

#### Scenario: Model fails to load
- **WHEN** initialization throws an exception
- **THEN** the entry's `notes` SHALL be updated with the exception message
- **AND** the tool SHALL continue to the next entry without crashing
- **AND** `status` SHALL remain `"untested"` so the developer can review and decide

#### Scenario: Each evaluated entry is written immediately
- **WHEN** an entry completes evaluation (pass or fail)
- **THEN** `voice-models.json` SHALL be written to disk before the next entry begins
- **AND** a tool crash mid-run SHALL not lose results from already-evaluated entries

### Requirement: Reference Fixtures
The tool SHALL include short reference WAV files for each supported language used in ASR smoke tests.

#### Scenario: ASR fixture is a short mono WAV
- **WHEN** the ASR evaluation phase loads a fixture for a language
- **THEN** the fixture SHALL be a mono 16 kHz WAV file of 2–5 seconds duration
- **AND** it SHALL contain clearly spoken words in the target language

#### Scenario: Missing language fixture falls back to English
- **WHEN** a model's primary language has no dedicated fixture
- **THEN** the English fixture SHALL be used as a fallback
- **AND** the evaluation SHALL still verify that the output is non-empty
