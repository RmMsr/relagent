## Purpose

Define the schema and lifecycle of `apps/assets/voice-models.json` — the single source of truth for the curated catalog of sherpa-onnx models used by both the app runtime and the voice-catalog CLI tool.

## Requirements

### Requirement: Single JSON Catalog File
The system SHALL maintain a single JSON file at `apps/assets/voice-models.json` that serves as both the evaluation registry and the app's runtime model catalog. The file SHALL be pretty-printed with 2-space indentation so that it is readable by humans, produces clean git diffs, and allows manual edits without tooling.

#### Scenario: File is a valid Flutter asset
- **WHEN** the app starts
- **THEN** `voice-models.json` SHALL be loadable via `rootBundle.loadString`
- **AND** the file SHALL parse without error using `dart:convert`

#### Scenario: File is human-readable
- **WHEN** a developer opens `voice-models.json` in a text editor
- **THEN** each entry SHALL be clearly delimited with 2-space indentation
- **AND** field names SHALL be self-explanatory without comments

### Requirement: Entry Schema
Each entry in the JSON array SHALL conform to a fixed schema with metadata fields and curation fields.

Metadata fields (set by the discovery tool, not manually edited):
- `id` — unique kebab-case identifier
- `type` — `"asr"` or `"tts"`
- `architecture` — maps to a `ModelArchitecture` enum value
- `languages` — array of ISO 639-1 language codes
- `downloadUrl` — direct URL to the `.tar.bz2` archive
- `downloadSizeMb` — compressed size in megabytes (integer)
- `fileStructure` — object mapping logical keys to relative file paths within the extracted archive
- `origin` — source project or organisation
- `sourceUrl` — URL to the upstream source repository
- `license` — SPDX identifier (e.g. `"Apache-2.0"`)
- `speakerCount` — number of speaker voices; 0 for ASR models
- `releaseDate` — `"YYYY-MM"` format

Curation fields (set by the developer after evaluation):
- `status` — `"untested"` | `"fail"` | `"approved"`
- `recommended` — boolean; `true` for the best pick per language+type combination
- `notes` — free-text string explaining a failure reason or curation decision; empty string when not needed

#### Scenario: Discovery tool writes a new entry
- **WHEN** the discovery phase finds a model not yet in `voice-models.json`
- **THEN** a new entry SHALL be appended with all metadata fields populated
- **AND** `status` SHALL be `"untested"`, `recommended` SHALL be `false`, `notes` SHALL be `""`

#### Scenario: Evaluation tool records a failure
- **WHEN** the evaluation phase fails to load or run inference on a model
- **THEN** the entry's `status` field SHALL remain unchanged (left for developer to set)
- **AND** `notes` SHALL be updated with a concise error description

#### Scenario: Developer approves a model
- **WHEN** a developer edits `voice-models.json` and sets `status` to `"approved"`
- **THEN** the app SHALL include that model in the downloadable model list on next launch
- **AND** if `recommended` is `true`, the app SHALL highlight it as the default pick for its language

#### Scenario: Schema validation on malformed entry
- **WHEN** an entry is missing a required metadata field
- **THEN** `ModelCatalog.fromJson` SHALL throw a descriptive parse error
- **AND** the app SHALL NOT crash silently with null field access

#### Scenario: Empty fileStructure is valid
- **WHEN** an entry has `fileStructure: {}`
- **THEN** `CatalogEntry.fromJson` SHALL parse it without error
- **AND** it SHALL NOT be treated as a missing required field

#### Scenario: Pocket TTS entry includes referenceWav
- **WHEN** a catalog entry has `architecture: "pocket"`
- **THEN** its `fileStructure` SHALL contain a `referenceWav` key pointing to a bundled sample voice relative path (e.g. `"test_wavs/bria.wav"`)
- **AND** the app SHALL use this path as the default voice reference when no user selection is active

### Requirement: App Reads Only Approved Entries
The app SHALL filter `voice-models.json` at load time and expose only entries with `status == "approved"` through the `ModelCatalog` API.

#### Scenario: Untested entries are invisible to the app
- **WHEN** `voice-models.json` contains entries with `status: "untested"`
- **THEN** `ModelCatalog.entries` SHALL NOT include those entries
- **AND** `ModelCatalog.findById` SHALL return `null` for their ids

#### Scenario: Failed entries are invisible to the app
- **WHEN** `voice-models.json` contains entries with `status: "fail"`
- **THEN** `ModelCatalog.entries` SHALL NOT include those entries

### Requirement: ASR Streaming Mode Display
The app SHALL display a streaming mode label for each ASR model in the model selection UI. The label SHALL reflect whether the model processes audio in real-time ("Live") or in discrete chunks after speech ends ("Chunked"). The label is derived from `ModelArchitecture` and is NOT stored in `voice-models.json`.

Live architectures (online/streaming recognizers): `transducer`, `ctc`, `onlineNemoCtc`
Chunked architectures (offline recognizers): `offlineNemoTransducer`

#### Scenario: Online ASR model shows Live label
- **WHEN** an ASR model's `architecture` is `transducer`, `ctc`, or `onlineNemoCtc`
- **THEN** the model selection UI SHALL display a "Live" label for that model

#### Scenario: Offline NeMo transducer shows Chunked label
- **WHEN** an ASR model's `architecture` is `offlineNemoTransducer`
- **THEN** the model selection UI SHALL display a "Chunked" label for that model
- **AND** it SHALL NOT display "Live" for that model

### Requirement: Recommended Flag Per Language and Type
Exactly one entry per language+type combination SHOULD be marked `recommended: true`. The app SHALL surface recommended entries prominently in the model selection UI.

#### Scenario: Recommended entry appears first in filtered list
- **WHEN** the model selection UI lists models for a given language and type
- **THEN** entries with `recommended: true` SHALL appear before entries with `recommended: false`

#### Scenario: Multiple recommended entries for same language are permitted at tool level
- **WHEN** `voice-models.json` contains two entries with the same type and language both marked `recommended: true`
- **THEN** the app SHALL display both without error
- **AND** both SHALL appear at the top of the filtered list
