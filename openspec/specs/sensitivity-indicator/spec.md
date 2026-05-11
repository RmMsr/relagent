# sensitivity-indicator Specification

## Purpose

Defines how the current session sensitivity level is displayed and changed by the user in the agentic chat page.

## Requirements

### Requirement: Sensitivity Level Display

The chat page SHALL display the current session sensitivity level as a color-coded indicator in the app bar.

#### Scenario: Indicator visible on chat page

- **WHEN** the agentic chat page is displayed
- **AND** a session is active
- **THEN** a sensitivity indicator SHALL be visible in the app bar actions area
- **AND** the indicator SHALL show a shield icon and the current sensitivity level
- **AND** on narrow screens (< 400dp) the indicator SHALL show the shield and the level's single-character abbreviation (O/S/P/C/I)
- **AND** on wider screens the indicator SHALL show the shield and the full level name

#### Scenario: Indicator color mapping

- **WHEN** the sensitivity level is displayed
- **THEN** the color SHALL follow this mapping:
  - OpenInformation (1): Green
  - Specific (2): Teal
  - Personal (3): Orange
  - Confidential (4): Deep orange
  - Internal (5): Red
- **AND** the level name SHALL be displayed as text alongside the color (not color alone)

#### Scenario: Sensitivity updated from chat response

- **WHEN** the app receives a `ChatResponse` from the engine (via message send or session continue)
- **THEN** the indicator SHALL update to reflect the `sensitivity_level` returned in the response

#### Scenario: No session active

- **WHEN** no session is active (e.g., first launch before any message)
- **THEN** the sensitivity indicator SHALL NOT be displayed

### Requirement: Sensitivity Level Picker

The user SHALL be able to change the session sensitivity level via a picker opened from the indicator.

#### Scenario: Open sensitivity picker

- **WHEN** the user taps the sensitivity indicator
- **THEN** a bottom sheet SHALL open showing all five sensitivity levels with their names, colors, and a short descriptive sentence per level

#### Scenario: Select a new sensitivity level

- **GIVEN** the sensitivity picker is open
- **WHEN** the user selects a different level
- **THEN** the app SHALL call `PUT /session/{id}/sensitivity` with the new level
- **AND** the indicator SHALL update optimistically to show the new level
- **AND** the picker SHALL close

#### Scenario: Sensitivity change fails

- **GIVEN** the user selects a new sensitivity level
- **WHEN** the `PUT /session/{id}/sensitivity` call fails
- **THEN** the indicator SHALL revert to the previous level
- **AND** an error message SHALL be shown to the user

#### Scenario: Select current level (no-op)

- **GIVEN** the sensitivity picker is open
- **WHEN** the user selects the already-active level
- **THEN** no API call SHALL be made
- **AND** the picker SHALL close

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
