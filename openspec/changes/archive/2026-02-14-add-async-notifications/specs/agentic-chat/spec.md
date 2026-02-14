## ADDED Requirements

### Requirement: Persistent Message IDs

Each message in a session SHALL have a unique, incrementing ID within that session.

#### Scenario: Message ID assignment

- **GIVEN** a chat context for a session
- **WHEN** a message is added to the context
- **THEN** the message SHALL be assigned a unique integer ID
- **AND** the ID SHALL be greater than all previous message IDs in that session

#### Scenario: Message ID persistence

- **GIVEN** messages have been added to a session
- **WHEN** the session is saved and reloaded
- **THEN** all message IDs SHALL be preserved
- **AND** the next message added SHALL receive the next sequential ID

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

#### Scenario: Engine from_id query parameter

- **GIVEN** the engine receives a GET messages request with `from_id` parameter
- **WHEN** `from_id` is provided
- **THEN** the response SHALL include only messages with ID >= from_id
- **AND** the response format SHALL match the standard messages response
