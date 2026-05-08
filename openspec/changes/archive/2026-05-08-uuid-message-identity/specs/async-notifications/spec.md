## MODIFIED Requirements

### Requirement: Event Format

The engine SHALL use standard SSE format with thin event payloads that notify about resource changes without including the changed data.

#### Scenario: SSE field structure

- **WHEN** any event is sent
- **THEN** the event SHALL include `event:`, `id:`, and `data:` fields
- **AND** the `event:` field SHALL use dot-separated naming (e.g., `session.updated`)
- **AND** the `id:` field SHALL contain a monotonically increasing unique integer (used by the SSE protocol for stream replay; unrelated to message identity)
- **AND** the `data:` field SHALL contain JSON with resource identifiers only

#### Scenario: Session updated event

- **WHEN** a session property (e.g., title) is updated
- **THEN** the event type SHALL be `session.updated`
- **AND** the data SHALL contain `{"session_id": "<session_id>"}`

#### Scenario: Messages appended event

- **WHEN** a message is added to a session
- **THEN** the event type SHALL be `session.messages.appended`
- **AND** the data SHALL contain `{"session_id": "<session_id>"}` and SHALL NOT carry any per-message identifier
- **AND** the client SHALL determine what to fetch using its own cursor (the UUID of its last known final message)

### Requirement: Message Notification

The engine SHALL publish a `session.messages.appended` event when a message is added to a session or when an in-flight message's mutable state changes (e.g., approval grant updates, final flag flips).

#### Scenario: User message added

- **GIVEN** a session exists
- **WHEN** a user message is added to the session
- **THEN** a `session.messages.appended` event SHALL be published
- **AND** the data SHALL contain `session_id` only

#### Scenario: Assistant message added

- **GIVEN** a session exists
- **WHEN** an assistant message is added to the session
- **THEN** a `session.messages.appended` event SHALL be published
- **AND** the data SHALL contain `session_id` only

#### Scenario: SystemAction approval state changes

- **GIVEN** a session has an in-flight `SystemAction` with pending approvals
- **WHEN** an approval is granted or declined
- **THEN** a `session.messages.appended` event SHALL be published
- **AND** the data SHALL contain `session_id` only
- **AND** the client's subsequent fetch SHALL re-fetch all non-final messages, allowing the in-place replacement of the updated `SystemAction`
