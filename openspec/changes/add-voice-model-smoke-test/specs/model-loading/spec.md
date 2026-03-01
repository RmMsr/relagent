## ADDED Requirements

### Requirement: JSON-Driven Model Catalog
The `ModelCatalog` class SHALL load its entries from `assets/voice-models.json` at app startup rather than declaring them as compile-time constants. The public query API (`entries`, `byType`, `byLanguage`, `byTypeAndLanguage`, `findById`, `availableLanguages`) SHALL remain unchanged so that no other code requires modification.

#### Scenario: Catalog initialised from asset on first access
- **WHEN** any `ModelCatalog` query method is called for the first time
- **THEN** `ModelCatalog` SHALL have already parsed `voice-models.json` via `rootBundle`
- **AND** the returned entries SHALL match only those with `status == "approved"` in the JSON

#### Scenario: Catalog is initialised once at app startup
- **WHEN** the app launches
- **THEN** `voice-models.json` SHALL be parsed exactly once and cached in memory
- **AND** subsequent calls to `ModelCatalog` query methods SHALL use the in-memory cache

#### Scenario: Catalog query API is unchanged
- **WHEN** existing code calls `ModelCatalog.byType(ModelType.asr)`
- **THEN** it SHALL receive a `List<CatalogEntry>` with the same shape as before
- **AND** no call sites outside `model_catalog.dart` SHALL require changes

### Requirement: CatalogEntry JSON Deserialisation
`CatalogEntry` SHALL gain a `fromJson` factory constructor that parses a JSON object into a typed `CatalogEntry` instance, mapping the JSON field names defined in the `voice-model-index` spec to the existing Dart fields.

#### Scenario: Valid entry deserialises without error
- **WHEN** `CatalogEntry.fromJson` is called with a complete, valid JSON object
- **THEN** it SHALL return a `CatalogEntry` with all fields populated correctly
- **AND** enum fields (`type`, `architecture`) SHALL be parsed from their string representations

#### Scenario: Missing required field throws descriptive error
- **WHEN** `CatalogEntry.fromJson` is called with a JSON object that omits a required field
- **THEN** it SHALL throw a `FormatException` naming the missing field
- **AND** the app SHALL surface this as a startup error rather than a null-safety crash

#### Scenario: Unknown architecture string is handled
- **WHEN** `CatalogEntry.fromJson` encounters an `architecture` value not in `ModelArchitecture`
- **THEN** it SHALL throw a `FormatException` with the unrecognised value
- **AND** the catalog SHALL not load partially (all-or-nothing parse)

### Requirement: Recommended Entries Exposed
`ModelCatalog` SHALL expose the `recommended` flag from each entry so that the model selection UI can sort and highlight entries appropriately.

#### Scenario: Recommended flag available on CatalogEntry
- **WHEN** code reads `entry.recommended`
- **THEN** it SHALL return `true` for entries marked `recommended: true` in the JSON
- **AND** `false` for all other approved entries

#### Scenario: Recommended entries sort before non-recommended
- **WHEN** `ModelCatalog.byType` or `ModelCatalog.byTypeAndLanguage` returns a list
- **THEN** entries with `recommended == true` SHALL appear first in the list
