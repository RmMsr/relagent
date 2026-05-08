## MODIFIED Requirements

### Requirement: Persistent Message IDs

Each message in a session SHALL carry a non-nullable `message_id: UUID` that uniquely identifies it across all sources (engine and clients) and across the lifetime of the session. The UUID SHALL be assigned at the moment of creation: by the app for `UserMessage` and locally-generated error messages, and by the engine for `AssistantMessage` and `SystemAction`. Insertion order within a session SHALL be determined by the persistence adapter and SHALL NOT be exposed as a domain field.

#### Scenario: User message UUID assigned by app

- **GIVEN** the user submits a message
- **WHEN** the app constructs the local `AgenticMessage` for that submission
- **THEN** the message SHALL be assigned a UUID at construction time
- **AND** the same UUID SHALL be sent in the body of `POST /sessions/{id}/messages`

#### Scenario: Engine-originated messages UUID assigned by engine

- **GIVEN** the engine appends an `AssistantMessage` or `SystemAction` to a session
- **WHEN** the message is persisted
- **THEN** the persisted record SHALL have a non-null `message_id`

#### Scenario: Idempotent POST on known message_id

- **GIVEN** the engine has previously processed a `POST /sessions/{id}/messages` with a given `message_id`
- **WHEN** a subsequent POST arrives with the same `message_id` for the same session
- **THEN** the engine SHALL NOT insert a new row
- **AND** the engine SHALL NOT start a new cycle
- **AND** the engine SHALL return the prior cycle's response

#### Scenario: Backwards-compat self-heal for missing message_id

- **GIVEN** a stored message row whose `message_id` is NULL (written before this change)
- **WHEN** the persistence adapter loads the row
- **THEN** a UUID SHALL be minted
- **AND** the row SHALL be UPDATEd with the minted UUID before the message is returned to callers
- **AND** subsequent reads SHALL observe the persisted UUID

### Requirement: Message History Loading

The system SHALL fetch existing messages from the engine when the app loads, with support for incremental fetching anchored at the UUID of the last known final message.

#### Scenario: Load history on app start

- **GIVEN** a valid session_id exists
- **WHEN** the Agentic Chat page is initialized
- **THEN** previous messages for that session SHALL be fetched from the engine
- **AND** messages SHALL be displayed in the chat history
- **AND** `SystemAction` messages (role=system) SHALL be parsed and rendered as system notes and approval cards

#### Scenario: Empty session history

- **GIVEN** a new session_id with no previous messages
- **WHEN** the Agentic Chat page is initialized
- **THEN** the chat history SHALL be empty
- **AND** no error SHALL be shown

#### Scenario: History loading failure

- **GIVEN** the engine is unreachable
- **WHEN** history loading is attempted
- **THEN** an error banner SHALL be displayed
- **AND** the user SHALL be able to retry or check settings

#### Scenario: Incremental fetch uses last final UUID as cursor

- **GIVEN** the app has messages loaded locally
- **WHEN** a `session.messages.appended` event is received for the active session
- **THEN** the app SHALL compute the cursor as the UUID of the last message in state whose `final` is `true`
- **AND** the app SHALL call `GET /sessions/{id}/messages?after=<uuid>` with that cursor
- **AND** if no final message exists in state, the app SHALL fetch the full history
- **AND** non-final messages SHALL be re-fetched and replaced on every notification (desired behavior — engine may add new messages or change content during unsettled cycles)

#### Scenario: Engine after query parameter

- **GIVEN** the engine receives `GET /sessions/{id}/messages?after=<uuid>`
- **WHEN** `after` is provided and resolves to a known message in the session
- **THEN** the response SHALL include only messages strictly after that row in insertion order
- **AND** the response format SHALL match the standard messages response

### Requirement: Single Ingestion Path

The app SHALL route every addition to chat state through a single ingest function whose contract is: append messages whose UUID is not present in state (preserving incoming order); skip messages whose UUID is present and whose cached entry has `final=true`; replace in place messages whose UUID is present and whose cached entry has `final=false`.

#### Scenario: New message is appended

- **GIVEN** the app's state contains messages with UUIDs A, B, C
- **WHEN** ingest is called with a message whose UUID is D
- **THEN** the message SHALL be appended after C
- **AND** the order of A, B, C SHALL be unchanged

#### Scenario: Settled cached entry preserved

- **GIVEN** the app's state contains a message with UUID B and `final=true`
- **WHEN** ingest is called with a message whose UUID is B (any content)
- **THEN** the cached entry SHALL be unchanged

#### Scenario: In-flight cached entry replaced

- **GIVEN** the app's state contains a message with UUID B and `final=false`
- **WHEN** ingest is called with a message whose UUID is B and updated fields (e.g., flipped `final` or updated approval grants)
- **THEN** the cached entry SHALL be replaced with the incoming message at the same index

#### Scenario: Mixed batch is processed in one pass

- **GIVEN** the app's state contains messages A (final), B (in-flight), C (final)
- **WHEN** ingest is called with [B (now final), D (new)]
- **THEN** B SHALL be replaced in place
- **AND** D SHALL be appended after C
- **AND** A and C SHALL be unchanged

### Requirement: Send Messages

The system SHALL send user messages to the engine API and display responses, subject to the strict-ordering constraint that at most one cycle is in flight per session at a time. When a cycle is already in flight, submitted messages SHALL be queued client-side rather than sent (see `client-message-queue`). Sends SHALL include the user message's `message_id` in the request body so that the engine can deduplicate retries.

#### Scenario: Send message successfully when idle

- **GIVEN** the engine is connected
- **AND** no cycle is in flight for the session
- **WHEN** the user submits a message
- **THEN** the message SHALL be sent to the engine with its `message_id` in the body
- **AND** the engine response SHALL be displayed in the chat
- **AND** if the response is a `SystemAction`, it SHALL be rendered as system notes and/or approval cards (not as an assistant text bubble)

#### Scenario: Retry after lost response does not duplicate

- **GIVEN** a `POST /sessions/{id}/messages` was sent with a particular `message_id`
- **AND** the response was lost (network error, app crash, etc.)
- **WHEN** the app retries the POST with the same `message_id`
- **THEN** the engine SHALL NOT create a duplicate user message
- **AND** the engine SHALL return the response of the original cycle

#### Scenario: Submit while cycle in flight queues the message

- **GIVEN** a cycle is in flight (the trailing message has `final=false`)
- **WHEN** the user submits a message
- **THEN** the message SHALL NOT be sent to the engine immediately
- **AND** the message SHALL be retained as the queued message
- **AND** the input SHALL be disabled until the queued message is sent or pulled back via "edit queued"

#### Scenario: Send message with voice input

- **GIVEN** voice mode is active
- **AND** no cycle is in flight
- **WHEN** speech is recognized and submitted
- **THEN** the recognized text SHALL be sent to the engine
- **AND** the response MAY be spoken via TTS if auto-playback is enabled

#### Scenario: Voice input while cycle in flight is queued

- **GIVEN** voice mode is active
- **AND** a cycle is in flight
- **WHEN** speech is recognized and submitted
- **THEN** the recognized text SHALL be queued (not sent)
- **AND** voice input SHALL be paused or otherwise gated until the queued message is sent or pulled back

#### Scenario: Chat response includes sensitivity level

- **WHEN** a `ChatResponse` is received from the engine
- **THEN** the app SHALL parse the `sensitivity_level` field
- **AND** the chat state SHALL update to reflect the current sensitivity level
