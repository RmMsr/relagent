## ADDED Requirements

### Requirement: API Status Version Field

The engine `/api/v1/status` response SHALL include a `version` field containing the deployed engine version string.

#### Scenario: Status response includes version

- **WHEN** an authenticated GET request is made to `/api/v1/status`
- **THEN** the response JSON includes a `version` field with a valid semver string (e.g., `"0.1.13"`)
- **AND** the value matches the version from the engine's deployed package metadata
