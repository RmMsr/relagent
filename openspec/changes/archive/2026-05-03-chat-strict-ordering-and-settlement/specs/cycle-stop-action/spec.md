## ADDED Requirements

### Requirement: Stop Endpoint

The engine SHALL provide a `POST /sessions/{session_id}/stop` endpoint that settles the session's currently in-flight cycle by mutating its trailing in-flight messages. The endpoint SHALL NOT trigger the agent and SHALL NOT append a new record.

#### Scenario: Stop on cycle with undecided approvals

- **GIVEN** a session whose trailing in-flight chain ends in a `SystemAction(final=false)` with one or more approvals where `granted` is `null`
- **WHEN** `POST /sessions/{id}/stop` is called
- **THEN** every undecided approval SHALL be set to `granted=false`
- **AND** the trailing `SystemAction(s)` SHALL be set to `final=true`
- **AND** the cycle's `UserMessage` SHALL be set to `final=true`
- **AND** no new message record SHALL be appended to the session
- **AND** the agent SHALL NOT be invoked

#### Scenario: Stop on cycle with all approvals already decided

- **GIVEN** a session whose trailing in-flight chain ends in a `SystemAction(final=false)` with every approval already set to `granted=true` or `granted=false`
- **WHEN** `POST /sessions/{id}/stop` is called
- **THEN** the trailing `SystemAction` SHALL be set to `final=true`
- **AND** the cycle's `UserMessage` SHALL be set to `final=true`
- **AND** no new message record SHALL be appended
- **AND** the agent SHALL NOT be invoked

#### Scenario: Stop on session with no in-flight cycle

- **GIVEN** a session whose trailing message has `final=true`
- **WHEN** `POST /sessions/{id}/stop` is called
- **THEN** the engine SHALL return `409 Conflict`
- **AND** the response body SHALL describe the absence of an in-flight cycle

#### Scenario: Stop on non-existent session

- **GIVEN** the session_id does not exist
- **WHEN** `POST /sessions/{id}/stop` is called
- **THEN** the engine SHALL return `404 Not Found`

#### Scenario: Stop response payload

- **WHEN** `POST /sessions/{id}/stop` succeeds
- **THEN** the response body SHALL include the settled state of the mutated `UserMessage` and `SystemAction(s)` so the client can update its view without an extra fetch

### Requirement: Stop UI Affordance

The chat client SHALL provide a cycle-level Stop control as part of the in-flight approval group, distinct from the per-card grant/decline actions.

#### Scenario: Stop bar visible when approval group is in-flight

- **GIVEN** the trailing message in the chat list is a `SystemAction` with `final=false`
- **WHEN** the chat page is rendered
- **THEN** a Stop bar SHALL be visible at the bottom of the approval group
- **AND** the Stop control SHALL be visually distinct from the per-card buttons

#### Scenario: Stop bar hidden when cycle is settled

- **GIVEN** the trailing message has `final=true`
- **WHEN** the chat page is rendered
- **THEN** no Stop bar SHALL be displayed for that cycle

#### Scenario: Stop click sends single request

- **GIVEN** the user clicks the Stop control
- **WHEN** the client handles the click
- **THEN** the client SHALL send exactly one request to `POST /sessions/{id}/stop`
- **AND** the client SHALL NOT call `/continue` after Stop

#### Scenario: Stop click during awaiting + queued discards queued message

- **GIVEN** the state is `awaiting + queued`
- **WHEN** the user clicks Stop
- **THEN** the client SHALL prompt the user to confirm before discarding the queued message, OR keep the queued message and re-evaluate after the stop completes (decision per implementation, but the behavior SHALL be deterministic)

### Requirement: Stopped Cycle Self-Describing in History

A stopped cycle SHALL be self-describing in persisted history without an additional marker record. The settled state — declined approvals on a final `SystemAction`, no following `AssistantMessage`, all messages `final` — SHALL be sufficient for downstream readers.

#### Scenario: History reconstruction handles stopped cycle

- **GIVEN** a session whose history contains a stopped cycle
- **WHEN** the history is reconstructed for a subsequent agent run
- **THEN** the stopped cycle SHALL be treated as immutable history
- **AND** the absence of an `AssistantMessage` SHALL NOT trigger an error
- **AND** no synthetic "stopped" record SHALL be inferred or expected
