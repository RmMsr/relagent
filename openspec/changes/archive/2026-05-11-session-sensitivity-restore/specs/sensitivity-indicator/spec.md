## ADDED Requirements

### Requirement: Sensitivity Level Restored on Session Load

When history is loaded for an existing session, the app SHALL restore the persisted sensitivity level from the engine response rather than defaulting to Personal.

#### Scenario: Sensitivity restored on full history load

- **WHEN** `loadHistory()` fetches the full message history for an existing session
- **AND** the `GET /messages/{id}` response includes a `sensitivity_level` field
- **THEN** the app state SHALL update `sensitivityLevel` to the value returned by the engine
- **AND** the sensitivity indicator SHALL reflect that restored level without requiring user interaction

#### Scenario: Sensitivity restored on incremental history load

- **WHEN** `loadHistory()` fetches messages incrementally (using `afterMessageId`)
- **AND** the response includes a `sensitivity_level` field
- **THEN** the app state SHALL update `sensitivityLevel` to the value returned by the engine

#### Scenario: Missing sensitivity field does not reset state

- **WHEN** the `GET /messages/{id}` response does not include a `sensitivity_level` field
- **THEN** the existing `sensitivityLevel` in app state SHALL remain unchanged

### Requirement: Sensitivity Level Applied on New Session Creation

When the user has adjusted the sensitivity level before sending the first message of a new session, the engine SHALL receive and apply that level before processing the first cycle.

#### Scenario: Sensitivity included in first message of new session

- **WHEN** the user sends the first message of a new session (no session ID exists)
- **AND** the current sensitivity level in app state is not the engine default
- **THEN** the `POST /messages` request SHALL include the `sensitivity_level` field
- **AND** the engine SHALL apply it to the new session context before processing
- **AND** any approvals generated in the first cycle SHALL reflect the user-chosen sensitivity level

#### Scenario: Sensitivity not re-sent for existing sessions

- **WHEN** the user sends a message to an existing session (session ID is present)
- **THEN** the `POST /messages` request SHALL NOT include a `sensitivity_level` field
- **AND** the engine SHALL use the already-persisted session sensitivity
