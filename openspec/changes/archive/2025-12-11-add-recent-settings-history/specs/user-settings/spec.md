# User Settings Specification

## ADDED Requirements

### Requirement: Recent Settings History

The system SHALL maintain a history of recently used server URL and model combinations to enable quick switching between different AI servers.

#### Scenario: Track new settings

- **WHEN** user saves settings with a new URL/model combination
- **THEN** the combination is added to the top of the recent history
- **AND** the history is persisted to SharedPreferences

#### Scenario: Deduplicate existing entry

- **WHEN** user saves settings with a URL/model combination that already exists in history
- **THEN** the existing entry is moved to the top of the history
- **AND** no duplicate entry is created

#### Scenario: Enforce history limit

- **WHEN** history contains 5 entries and a new unique combination is saved
- **THEN** the oldest entry is removed from history
- **AND** the new entry is added to the top
- **AND** history contains exactly 5 entries

#### Scenario: Load history on startup

- **WHEN** the app starts
- **THEN** the recent settings history is loaded from SharedPreferences
- **AND** history entries are available for autocomplete suggestions

### Requirement: Settings Autocomplete UI

The settings page SHALL provide autocomplete suggestions for server URL and model fields based on recent history.

#### Scenario: Display URL suggestions

- **WHEN** user focuses on the base URL field
- **THEN** a dropdown shows recently used URLs
- **AND** suggestions are ordered with most recent first

#### Scenario: Display model suggestions

- **WHEN** user focuses on the model field
- **THEN** a dropdown shows recently used model names
- **AND** suggestions are ordered with most recent first

#### Scenario: Select from suggestions

- **WHEN** user selects a recent entry from autocomplete
- **THEN** the corresponding URL or model value is populated in the field
- **AND** user can continue editing or save immediately

### Requirement: History Persistence

Recent settings history SHALL persist across app sessions using SharedPreferences.

#### Scenario: Persist on change

- **WHEN** history is updated (addition, deduplication, or limit enforcement)
- **THEN** the updated history is immediately saved to SharedPreferences

#### Scenario: Survive app restart

- **WHEN** user closes and reopens the app
- **THEN** the recent settings history is restored
- **AND** autocomplete suggestions reflect the saved history
