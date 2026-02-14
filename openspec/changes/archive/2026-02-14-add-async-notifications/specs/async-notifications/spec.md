## ADDED Requirements

### Requirement: SSE Event Endpoint

The engine SHALL expose an SSE endpoint for real-time event streaming.

#### Scenario: Client connects to event stream

- **GIVEN** the engine is running
- **WHEN** a client connects to `GET /api/v1/events`
- **THEN** the connection SHALL be held open as an SSE stream
- **AND** the response content-type SHALL be `text/event-stream`

#### Scenario: Client receives events

- **GIVEN** a client is connected to the event stream
- **WHEN** a notification event is published
- **THEN** the event SHALL be delivered to all connected clients
- **AND** each event SHALL include `event`, `data`, and `id` fields

#### Scenario: Ping keeps connection alive

- **GIVEN** a client is connected to the event stream
- **WHEN** no events occur for 15 seconds
- **THEN** the server SHALL send a ping (handled by sse-starlette)
- **AND** the connection SHALL remain open

### Requirement: Event Format

The engine SHALL use standard SSE format with thin event payloads that notify about resource changes without including the changed data.

#### Scenario: SSE field structure

- **WHEN** any event is sent
- **THEN** the event SHALL include `event:`, `id:`, and `data:` fields
- **AND** the `event:` field SHALL use dot-separated naming (e.g., `session.updated`)
- **AND** the `id:` field SHALL contain a monotonically increasing unique integer
- **AND** the `data:` field SHALL contain JSON with resource identifiers only

#### Scenario: Session updated event

- **WHEN** a session property (e.g., title) is updated
- **THEN** the event type SHALL be `session.updated`
- **AND** the data SHALL contain `{"session_id": "<session_id>"}`

#### Scenario: Messages appended event

- **WHEN** a message is added to a session
- **THEN** the event type SHALL be `session.messages.appended`
- **AND** the data SHALL contain `{"session_id": "<session_id>", "latest_sequence_id": <int>}`
- **AND** `latest_sequence_id` SHALL be the sequence ID of the most recently added message

### Requirement: Session Title Notification

The engine SHALL publish a `session.updated` event when a session title is generated or updated.

#### Scenario: Title generated

- **GIVEN** a session exists
- **WHEN** the session title is generated or updated
- **THEN** a `session.updated` event SHALL be published
- **AND** the data SHALL contain the session_id

### Requirement: Message Notification

The engine SHALL publish a `session.messages.appended` event when a message is added to a session.

#### Scenario: User message added

- **GIVEN** a session exists
- **WHEN** a user message is added to the session
- **THEN** a `session.messages.appended` event SHALL be published
- **AND** the data SHALL contain `session_id` and `latest_sequence_id`

#### Scenario: Assistant message added

- **GIVEN** a session exists
- **WHEN** an assistant message is added to the session
- **THEN** a `session.messages.appended` event SHALL be published
- **AND** the data SHALL contain `session_id` and `latest_sequence_id`

### Requirement: Event Persistence

The engine SHALL persist events to enable replay after client reconnection.

#### Scenario: Events stored in SQLite

- **WHEN** an event is published
- **THEN** the event SHALL be stored in an SQLite database
- **AND** the event SHALL be assigned a unique incrementing ID

#### Scenario: Event TTL pruning

- **GIVEN** events exist in the database
- **WHEN** an event is older than 72 hours
- **THEN** the event MAY be pruned from the database

#### Scenario: Cross-process event publishing

- **GIVEN** a separate process (e.g., scheduled task) writes an event to the database
- **WHEN** the SSE endpoint detects the new event
- **THEN** the event SHALL be delivered to connected clients

### Requirement: Duplicate Event Prevention

The engine SHALL avoid publishing duplicate events for the same resource change.

#### Scenario: Single event per operation

- **GIVEN** a single operation that modifies a resource (e.g., message creation)
- **WHEN** the operation completes
- **THEN** exactly one event SHALL be published for that change
- **AND** duplicate events for the same change SHALL be avoided

### Requirement: Reconnection and Replay

The engine SHALL support event replay for reconnecting clients.

#### Scenario: Client reconnects with Last-Event-ID

- **GIVEN** a client was previously connected and received event ID 42
- **WHEN** the client reconnects with `Last-Event-ID: 42` header
- **THEN** the server SHALL replay all events with ID > 42
- **AND** the replayed events SHALL be delivered in order

#### Scenario: Client reconnects without Last-Event-ID

- **GIVEN** a client connects without `Last-Event-ID` header
- **WHEN** the connection is established
- **THEN** only new events SHALL be streamed (no replay)

#### Scenario: Replay limit

- **GIVEN** a client reconnects with `Last-Event-ID`
- **WHEN** more than 100 events have occurred since that ID
- **THEN** the server SHALL replay only the most recent 100 events
- **AND** older events SHALL not be re-sent

### Requirement: OpenAPI Documentation

The SSE endpoint SHALL be documented in the OpenAPI schema.

#### Scenario: Endpoint in schema

- **WHEN** the OpenAPI schema is generated
- **THEN** the `/api/v1/events` endpoint SHALL be documented
- **AND** the response content-type SHALL be `text/event-stream`
- **AND** the event data schema SHALL be defined

### Requirement: App SSE Client

The app SHALL connect to the engine's SSE endpoint for real-time updates.

#### Scenario: Establish SSE connection

- **GIVEN** the app is configured with a valid engine URL
- **WHEN** the app starts or the chat page is opened
- **THEN** the app SHALL establish an SSE connection to `/api/v1/events`

#### Scenario: Automatic reconnection

- **GIVEN** the SSE connection is lost
- **WHEN** the connection drops
- **THEN** the app SHALL attempt to reconnect with exponential backoff
- **AND** the reconnection request SHALL include `Last-Event-ID` if available

#### Scenario: Refresh data on notification

- **GIVEN** the app is connected to the event stream
- **WHEN** a notification for the current session is received
- **THEN** the app SHALL fetch the updated data from the relevant REST endpoint
- **AND** the UI SHALL update to reflect the changes

#### Scenario: Handle connection loss gracefully

- **GIVEN** the SSE connection is lost and reconnected
- **WHEN** the reconnection succeeds
- **THEN** the app MAY fetch full session state to ensure consistency
- **AND** no duplicate data SHALL be displayed
