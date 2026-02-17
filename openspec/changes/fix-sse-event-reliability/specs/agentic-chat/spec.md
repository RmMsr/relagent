## MODIFIED Requirements

### Requirement: Message History Loading

The system SHALL fetch existing messages from the engine when the app loads, with support for incremental fetching using persistent message IDs.

#### Scenario: Load history on app start

- **GIVEN** a valid session_id exists
- **WHEN** the Agentic Chat page is initialized
- **THEN** previous messages for that session SHALL be fetched from the engine
- **AND** messages SHALL be displayed in the chat history

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

#### Scenario: Refresh on messages appended event

- **GIVEN** the app has existing messages loaded
- **WHEN** a `session.messages.appended` event is received with `latest_message_id`
- **THEN** the app SHALL refresh the message history
- **AND** the UI SHALL update to show any new messages

#### Scenario: Incremental history deduplication

- **GIVEN** the app has messages loaded locally (including optimistic messages from POST responses)
- **WHEN** an incremental history fetch returns messages
- **THEN** messages whose sequence ID already exists in the local message list SHALL be skipped
- **AND** only messages with new sequence IDs SHALL be appended
- **AND** locally-created messages without a sequence ID SHALL NOT be affected

#### Scenario: Engine from_id query parameter

- **GIVEN** the engine receives a GET messages request with `from_id` parameter
- **WHEN** `from_id` is provided
- **THEN** the response SHALL include only messages with ID >= from_id
- **AND** the response format SHALL match the standard messages response
