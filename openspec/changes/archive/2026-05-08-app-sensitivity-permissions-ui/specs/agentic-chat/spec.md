## MODIFIED Requirements

### Requirement: Agentic Chat Page

The system SHALL provide an Agentic Chat page as the primary frontend for the Relagent engine.

#### Scenario: Default app page

- **WHEN** the app is launched
- **THEN** the chat page for the selected backend SHALL be displayed by default

#### Scenario: Chat interface layout

- **WHEN** the Agentic Chat page is displayed
- **THEN** the page SHALL include a message list, text input, voice mode selector, navigation drawer, and a floating sensitivity indicator in the top-right corner
- **AND** the layout SHALL be consistent with the simple chat interface

#### Scenario: Material navigation drawer

- **WHEN** the user opens the navigation drawer (via hamburger icon or swipe)
- **THEN** the drawer SHALL follow Material Design NavigationDrawer pattern
- **AND** the drawer SHALL show entries: Chat (selected), Sessions (engine only), Settings, About
- **AND** the currently active page SHALL be indicated using the drawer's built-in selected state (no manual checkmark)
- **AND** the drawer SHALL NOT show separate "Simple Chat" and "Agentic Chat" entries

### Requirement: Send Messages

The system SHALL send user messages to the engine API and display responses.

#### Scenario: Send message successfully

- **GIVEN** the engine is connected
- **WHEN** the user submits a message
- **THEN** the message SHALL be sent to the engine
- **AND** the engine response SHALL be displayed in the chat
- **AND** if the response is a `SystemAction`, it SHALL be rendered as system notes and/or approval cards (not as an assistant text bubble)

#### Scenario: Send message with voice input

- **GIVEN** voice mode is active
- **WHEN** speech is recognized and submitted
- **THEN** the recognized text SHALL be sent to the engine
- **AND** the response MAY be spoken via TTS if auto-playback is enabled

#### Scenario: Chat response includes sensitivity level

- **WHEN** a `ChatResponse` is received from the engine
- **THEN** the app SHALL parse the `sensitivity_level` field
- **AND** the chat state SHALL update to reflect the current sensitivity level

### Requirement: Message History Loading

The system SHALL fetch existing messages from the engine when the app loads, with support for incremental fetching using persistent message IDs.

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
