## ADDED Requirements

### Requirement: Imported Models Shown First in Catalog Browser
The catalog browser SHALL display imported models above catalog models within each type tab, sorted by most-recently-imported first. Within the catalog group, existing ordering (recommended first, then alphabetical) is unchanged.

#### Scenario: Imported models lead the list
- **WHEN** the catalog browser is open and imported models exist for the active type tab
- **THEN** imported model cards SHALL appear at the top of the list before any catalog entries

#### Scenario: Most recently imported appears first within imports group
- **WHEN** multiple imported models exist for the active type tab
- **THEN** they SHALL be ordered with the most recently imported model at the top

#### Scenario: No imported models leaves catalog ordering unchanged
- **WHEN** no imported models exist for the active type tab
- **THEN** catalog entries SHALL appear in their existing order (recommended first, then alphabetical)

### Requirement: Imported Model Visual Distinction
Imported model cards SHALL carry a visible "Imported" badge so the user can distinguish them from curated catalog entries.

#### Scenario: Badge visible on imported card
- **WHEN** an imported model card is displayed
- **THEN** it SHALL show an "Imported" label or chip
- **AND** fields absent from the import (e.g., download size, origin) SHALL be omitted rather than shown as empty

#### Scenario: Catalog cards show no imported badge
- **WHEN** a catalog model card is displayed
- **THEN** it SHALL NOT show an "Imported" badge

### Requirement: Import Action in Catalog Browser
The catalog browser SHALL provide an action to trigger the local model import flow.

#### Scenario: Import button visible in browser
- **WHEN** the catalog browser is open
- **THEN** an "Import from storage" button or action SHALL be accessible without leaving the screen

#### Scenario: Import action opens file picker
- **WHEN** the user activates the import action
- **THEN** the local model import flow SHALL begin (file picker opens)

### Requirement: Imported Model Deletion from Browser
The catalog browser SHALL allow the user to delete an imported model, consistent with how downloaded catalog models can be deleted.

#### Scenario: Delete action on imported card
- **WHEN** an imported model card is displayed
- **THEN** it SHALL show a delete action

#### Scenario: Deletion confirmed removes model from list
- **WHEN** the user confirms deletion of an imported model
- **THEN** the card SHALL disappear from the catalog browser
- **AND** a confirmation message SHALL be shown

## MODIFIED Requirements

### Requirement: Downloaded-Only Filter
The catalog browser SHALL provide a filter control to show only locally available models, making it easy to find models that are ready to use for selection or deletion. Locally available models include both downloaded catalog models and all imported models.

#### Scenario: Filter chip toggles locally-available view
- **WHEN** the user activates the "Downloaded" filter chip
- **THEN** the list SHALL show downloaded catalog models and all imported models
- **AND** the search query SHALL continue to apply within the filtered set

#### Scenario: Filter chip disabled shows all models
- **WHEN** the "Downloaded" filter chip is not active
- **THEN** all catalog entries and all imported entries (subject to any active search query) SHALL be shown
