# import-standardization Specification

## Purpose
TBD - created by archiving change standardize-imports-to-relative. Update Purpose after archive.
## Requirements
### Requirement: Import statements use relative paths

All internal project imports SHALL use the `/` prefix relative path format instead of `package:` format for files within the same package.

#### Scenario: Standard internal import
- **WHEN** importing a file from within the same package
- **THEN** the import SHALL use `/path/to/file.dart` format
- **AND** NOT use `package:relagent/path/to/file.dart` format

#### Scenario: External package import
- **WHEN** importing from external packages (http, flutter, etc.)
- **THEN** the import SHALL continue using `package:name/path.dart` format

