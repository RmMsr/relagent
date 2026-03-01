## ADDED Requirements

### Requirement: Flutter Linux CLI Entry Point
The `voice-catalog` tool SHALL be a Flutter Linux application with a dedicated entry point at `apps/lib/voice_catalog/voice_catalog_main.dart`. It SHALL be run with `fvm flutter run -d linux -t lib/voice_catalog/voice_catalog_main.dart` and exit with code 0 on success or non-zero on unrecoverable error.

#### Scenario: Tool runs to completion and exits
- **WHEN** the tool finishes all three phases (discover, filter, evaluate)
- **THEN** it SHALL write the updated `voice-models.json` and exit the process
- **AND** it SHALL print a summary to stdout listing counts of discovered, filtered, and evaluated entries

#### Scenario: Tool is excluded from the regular app build
- **WHEN** the app is built normally (`flutter build`)
- **THEN** `eval_main.dart` SHALL NOT be included in the app bundle
- **AND** the tool entry point SHALL only be activated via `-t lib/voice_catalog/voice_catalog_main.dart`

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

#### Scenario: GitHub API is unreachable
- **WHEN** the GitHub releases API request fails with a network error
- **THEN** the tool SHALL print a warning and proceed using only the existing `voice-models.json` entries
- **AND** it SHALL NOT overwrite the file with partial data

### Requirement: Filter Phase
The tool SHALL apply hard filter criteria to all `untested` entries and skip those that cannot be suitable for the project, recording a failure note without downloading.

#### Scenario: Non-permissive license is excluded
- **WHEN** a model entry has a license other than Apache-2.0 or MIT
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: license <value>"`

#### Scenario: Oversized model is excluded
- **WHEN** a model entry has `downloadSizeMb` greater than 1000
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: size <value>MB exceeds 1GB limit"`

#### Scenario: Non-project language is excluded
- **WHEN** a model entry's `languages` array has no overlap with the supported set (en, de, fr, es, it, nl, pl, ru, sv, pt, cs)
- **THEN** the entry SHALL be skipped in the evaluate phase
- **AND** `notes` SHALL record `"excluded: no supported language"`

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
- **AND** initialize it via `createOfflineTtsFromMetadata`
- **AND** synthesize a short reference sentence in the model's primary language
- **AND** verify the output audio buffer is non-empty
- **AND** record latency in milliseconds in `notes`

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
