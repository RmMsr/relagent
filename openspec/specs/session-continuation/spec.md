# session-continuation Specification

## Purpose

Defines the engine endpoint and app behavior for continuing a session after approval resolution or sensitivity change.
## Requirements
### Requirement: Session Continuation Endpoint

The engine SHALL provide a `POST /sessions/{session_id}/continue` endpoint that triggers an agent run with the current session state and returns a `ChatResponse`. The endpoint SHALL respect the engine-in-flight guard before processing (see `engine-in-flight-guard`). The endpoint SHALL NOT be triggered implicitly by per-approval grant or decline calls; the client orchestrates when to invoke it.

#### Scenario: Continue after per-approval decisions

- **GIVEN** the trailing in-flight `SystemAction` has all approvals decided (each `granted=true` or `granted=false`) via the per-approval grant/decline endpoints
- **WHEN** `POST /sessions/{id}/continue` is called
- **THEN** the engine SHALL run the agent with the current context, decisions, and sensitivity level
- **AND** the response SHALL be a `ChatResponse` containing either an `AssistantMessage` or a new `SystemAction`

#### Scenario: Continue with mixed grants and declines

- **GIVEN** the trailing in-flight `SystemAction` has a mix of granted and declined approvals
- **WHEN** `POST /sessions/{id}/continue` is called
- **THEN** the engine SHALL run the agent in a recovery path, working without the capabilities that were declined
- **AND** the response SHALL be a `ChatResponse`

#### Scenario: Continue after sensitivity change

- **GIVEN** the session sensitivity level was changed via `PUT /session/{id}/sensitivity`
- **WHEN** `POST /sessions/{id}/continue` is called
- **THEN** the engine SHALL re-evaluate the context at the new sensitivity level
- **AND** the response MAY include new approvals if the new level requires different permissions

#### Scenario: Continue for error recovery

- **GIVEN** a previous agent run resulted in an error
- **WHEN** `POST /sessions/{id}/continue` is called
- **THEN** the engine SHALL attempt to resume or re-run the agent
- **AND** the response SHALL be a `ChatResponse`

#### Scenario: Continue on non-existent session

- **GIVEN** the session_id does not exist
- **WHEN** `POST /sessions/{id}/continue` is called
- **THEN** the engine SHALL return HTTP 404

#### Scenario: Response includes sensitivity level

- **WHEN** `POST /sessions/{id}/continue` returns successfully
- **THEN** the `ChatResponse` SHALL include the current `sensitivity_level` of the context

### Requirement: App Session Continuation

The app SHALL call the session continuation endpoint and handle the response using the same flow as regular message responses. Continuation SHALL be invoked only after the client has collected all per-card decisions for the trailing in-flight `SystemAction`; the engine SHALL NOT auto-continue.

#### Scenario: App calls continue after collecting per-card decisions

- **GIVEN** every approval in the trailing in-flight `SystemAction` has been recorded via `POST /sessions/{id}/approvals/{approval_id}/grant` or `POST /sessions/{id}/approvals/{approval_id}/decline`
- **WHEN** the last per-card decision is recorded
- **THEN** the app SHALL call `POST /sessions/{id}/continue`
- **AND** the app SHALL show the "Thinking..." pending state
- **AND** the response SHALL be parsed and appended to the chat history

#### Scenario: App calls continue after sensitivity change

- **GIVEN** the user changed the session sensitivity via the sensitivity adjustment flow
- **WHEN** the user triggers re-evaluation
- **THEN** the app SHALL call `POST /sessions/{id}/continue`
- **AND** the response SHALL be parsed and appended to the chat history

#### Scenario: Continue endpoint returns error

- **GIVEN** the app calls `POST /sessions/{id}/continue`
- **WHEN** the endpoint returns an error (network, 4xx, 5xx)
- **THEN** an error message SHALL be displayed in the chat
- **AND** the trailing in-flight `SystemAction` SHALL remain in its current state (not advanced to settled)

#### Scenario: Continue endpoint does not block on in-flight cycle

- **GIVEN** the trailing message has `final=false` (the in-flight cycle that `/continue` is meant to advance)
- **WHEN** the app calls `POST /sessions/{id}/continue`
- **THEN** the engine SHALL proceed without waiting (see `engine-in-flight-guard`)
- **AND** the app SHALL receive a normal `ChatResponse`

#### Scenario: Continue endpoint not available (graceful degradation)

- **GIVEN** the engine does not yet support `POST /sessions/{id}/continue` (returns 404 or 405)
- **WHEN** the app attempts to call it
- **THEN** an error message SHALL inform the user that the engine does not support continuation
- **AND** the app SHALL NOT silently fail or hang

