## ADDED Requirements

### Requirement: Session Continuation Endpoint

The engine SHALL provide a `POST /session/{session_id}/continue` endpoint that triggers an agent run with the current session state and returns a `ChatResponse`.

#### Scenario: Continue after approval resolution

- **GIVEN** a session has pending approvals and the user has created grants for some or all of them
- **WHEN** `POST /session/{id}/continue` is called
- **THEN** the engine SHALL run the agent with the current context, grants, and sensitivity level
- **AND** the response SHALL be a `ChatResponse` containing either an `AssistantMessage` or a new `SystemAction`

#### Scenario: Continue with missing grants (recovery path)

- **GIVEN** a session has pending approvals and some have not been granted
- **WHEN** `POST /session/{id}/continue` is called
- **THEN** the engine SHALL run the agent in a recovery path, working without the capabilities that lack grants
- **AND** the response SHALL be a `ChatResponse`

#### Scenario: Continue after sensitivity change

- **GIVEN** the session sensitivity level was changed via `PUT /session/{id}/sensitivity`
- **WHEN** `POST /session/{id}/continue` is called
- **THEN** the engine SHALL re-evaluate the context at the new sensitivity level
- **AND** the response MAY include new approvals if the new level requires different permissions

#### Scenario: Continue for error recovery

- **GIVEN** a previous agent run resulted in an error
- **WHEN** `POST /session/{id}/continue` is called
- **THEN** the engine SHALL attempt to resume or re-run the agent
- **AND** the response SHALL be a `ChatResponse`

#### Scenario: Continue on non-existent session

- **GIVEN** the session_id does not exist
- **WHEN** `POST /session/{id}/continue` is called
- **THEN** the engine SHALL return HTTP 404

#### Scenario: Response includes sensitivity level

- **WHEN** `POST /session/{id}/continue` returns successfully
- **THEN** the `ChatResponse` SHALL include the current `sensitivity_level` of the context

### Requirement: App Session Continuation

The app SHALL call the session continuation endpoint and handle the response using the same flow as regular message responses.

#### Scenario: App calls continue endpoint

- **GIVEN** the user triggers continuation (from approval resolution or sensitivity change)
- **WHEN** the app calls `POST /session/{id}/continue`
- **THEN** the app SHALL show the "Thinking..." pending state
- **AND** the response SHALL be parsed and appended to the chat history

#### Scenario: Continue endpoint returns error

- **GIVEN** the app calls `POST /session/{id}/continue`
- **WHEN** the endpoint returns an error (network, 4xx, 5xx)
- **THEN** an error message SHALL be displayed in the chat
- **AND** the approval group SHALL remain in its current state (not marked as resolved)

#### Scenario: Continue endpoint not available (graceful degradation)

- **GIVEN** the engine does not yet support `POST /session/{id}/continue` (returns 404 or 405)
- **WHEN** the app attempts to call it
- **THEN** an error message SHALL inform the user that the engine does not support continuation
- **AND** the app SHALL NOT silently fail or hang
