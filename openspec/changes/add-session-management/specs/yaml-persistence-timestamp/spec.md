## ADDED Requirements

### Requirement: Folder Timestamp Update on Session Access

The system SHALL update the folder modification timestamp when a session is accessed or modified to enable accurate chronological sorting.

#### Scenario: Timestamp updated on message addition

- **WHEN** a new message is added to a session
- **THEN** the system SHALL update the session folder's modification timestamp
- **AND** the timestamp SHALL reflect the current system time
- **AND** the update SHALL be persisted to the filesystem

#### Scenario: Timestamp updated on session read

- **WHEN** a session is accessed (opened/viewed)
- **THEN** the system SHALL update the session folder's modification timestamp
- **AND** the timestamp SHALL reflect the current access time
- **AND** this update SHALL enable "recently viewed" sorting

#### Scenario: Timestamp preserved during listing

- **WHEN** the system lists sessions for display
- **THEN** the folder modification timestamp SHALL be used as the "last modified" time
- **AND** sessions SHALL be sorted by this timestamp in descending order
- **AND** the relative time display SHALL be calculated from this timestamp

### Requirement: YAML Persistence Layer Integration

The system SHALL integrate timestamp updates into the existing YAML persistence layer without breaking existing functionality.

#### Scenario: Backward compatibility maintained

- **WHEN** the persistence layer updates folder timestamps
- **THEN** existing session data SHALL remain accessible
- **AND** existing session formats SHALL be readable
- **AND** no data loss SHALL occur during the transition

#### Scenario: Cross-platform timestamp handling

- **WHEN** the system runs on different platforms (Windows, Linux, macOS)
- **THEN** folder timestamps SHALL be updated using platform-appropriate methods
- **AND** timestamp resolution SHALL be sufficient for sorting (seconds or better)
- **AND** behavior SHALL be consistent across platforms

#### Scenario: Timestamp update efficiency

- **WHEN** timestamp updates occur
- **THEN** the operation SHALL complete quickly (sub-second)
- **AND** the operation SHALL NOT block user interactions
- **AND** the operation SHALL be performed asynchronously where possible
