# Version Management

Unified version management across all Relagent artifacts.

## ADDED Requirements

### Requirement: Single Source of Truth

The system SHALL maintain a single `VERSION` file at the repository root containing the semantic version.

#### Scenario: VERSION file format

- **GIVEN** a VERSION file exists at the repository root
- **WHEN** the file is read
- **THEN** it contains a valid semver string (e.g., `0.1.0`, `1.2.3-beta.1`)

### Requirement: Version Synchronization Script

The system SHALL provide a script to synchronize the version across all artifacts.

#### Scenario: Sync to pyproject.toml

- **GIVEN** VERSION contains `0.2.0`
- **WHEN** `bin/update-version.py` is executed
- **THEN** `pyproject.toml` `version` field is updated to `0.2.0`

#### Scenario: Sync to pubspec.yaml preserving build number

- **GIVEN** VERSION contains `0.2.0`
- **AND** `apps/pubspec.yaml` has `version: 0.1.0+5`
- **WHEN** `bin/update-version.py` is executed
- **THEN** `apps/pubspec.yaml` has `version: 0.2.0+5`

#### Scenario: Version bump

- **GIVEN** VERSION contains `0.1.0`
- **WHEN** `bin/update-version.py --bump minor` is executed
- **THEN** VERSION contains `0.2.0`
- **AND** all artifacts are updated to `0.2.0`

### Requirement: Engine Status Endpoint

The engine SHALL expose a `/health` endpoint returning version information.

#### Scenario: Status endpoint response

- **WHEN** a GET request is made to `/health`
- **THEN** the response includes `name`, `version`, and `status` fields
- **AND** the `version` matches the deployed package version

### Requirement: Container Version Tags

Container images SHALL be tagged with the version number.

#### Scenario: Build creates version tag

- **GIVEN** VERSION contains `0.2.0`
- **WHEN** `bin/server_build.py` is executed
- **THEN** the image is tagged as `registry.gitlab.com/rmmsr/relagent:0.2.0`
- **AND** the image is also tagged as `registry.gitlab.com/rmmsr/relagent:latest`

### Requirement: Flutter Splash Screen

The Flutter app SHALL display a splash screen showing version information during startup.

#### Scenario: Splash screen content

- **WHEN** the app launches
- **THEN** a splash screen is displayed with the app icon, name, and version

#### Scenario: Splash screen navigation

- **GIVEN** the splash screen is displayed
- **WHEN** initialization completes or minimum display time elapses
- **THEN** the app navigates to the main chat interface
