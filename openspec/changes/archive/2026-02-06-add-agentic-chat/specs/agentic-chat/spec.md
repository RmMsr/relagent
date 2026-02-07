## ADDED Requirements

### Requirement: Agentic Chat Page

The system SHALL provide an Agentic Chat page as the primary frontend for the Relagent engine.

#### Scenario: Default app page

- **WHEN** the app is launched
- **THEN** the Agentic Chat page SHALL be displayed by default

#### Scenario: Chat interface layout

- **WHEN** the Agentic Chat page is displayed
- **THEN** the page SHALL include a message list, text input, voice mode selector, and settings navigation
- **AND** the layout SHALL be consistent with the simple chat interface

### Requirement: Engine Connection

The system SHALL connect to the Relagent engine API using the configured Engine URL.

#### Scenario: Successful connection

- **GIVEN** a valid Engine URL is configured
- **WHEN** the app communicates with the engine
- **THEN** messages SHALL be sent and received successfully

#### Scenario: Connection failure

- **GIVEN** the Engine URL is unreachable or invalid
- **WHEN** the app attempts to communicate
- **THEN** an error banner SHALL be displayed with a "Check Settings" action

#### Scenario: Authentication required

- **GIVEN** the engine requires authentication
- **WHEN** basic auth credentials are configured
- **THEN** the `Authorization: Basic` header SHALL be included in all requests

### Requirement: Session Persistence

The system SHALL persist the `session_id` across app restarts to maintain conversation context.

#### Scenario: First launch session creation

- **GIVEN** the app is launched for the first time
- **WHEN** no session_id exists
- **THEN** a new UUID session_id SHALL be generated and persisted

#### Scenario: Session persistence across restarts

- **GIVEN** a session_id exists
- **WHEN** the app is closed and reopened
- **THEN** the same session_id SHALL be used for engine communication

#### Scenario: Session included in requests

- **WHEN** a message is sent to the engine
- **THEN** the session_id SHALL be included in the request

### Requirement: Message History Loading

The system SHALL fetch existing messages from the engine when the app loads.

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

### Requirement: Send Messages

The system SHALL send user messages to the engine API and display responses.

#### Scenario: Send message successfully

- **GIVEN** the engine is connected
- **WHEN** the user submits a message
- **THEN** the message SHALL be sent to the engine
- **AND** the engine response SHALL be displayed in the chat

#### Scenario: Send message with voice input

- **GIVEN** voice mode is active
- **WHEN** speech is recognized and submitted
- **THEN** the recognized text SHALL be sent to the engine
- **AND** the response MAY be spoken via TTS if auto-playback is enabled

### Requirement: Clear Chat and Session Reset

The system SHALL reset both the message history and session_id when the user clears the chat.

#### Scenario: Clear chat action

- **GIVEN** messages exist in the chat
- **WHEN** the user activates the clear chat action
- **THEN** all displayed messages SHALL be removed
- **AND** a new session_id SHALL be generated
- **AND** future messages SHALL use the new session_id

#### Scenario: Clear chat persists new session

- **GIVEN** the user has cleared the chat
- **WHEN** the app is closed and reopened
- **THEN** the new session_id SHALL be persisted
- **AND** message history SHALL be empty (new session)

### Requirement: Voice Input and Output

The system SHALL support the same voice input and output capabilities as the simple chat.

#### Scenario: Voice mode selection

- **WHEN** the Agentic Chat page is displayed
- **THEN** the voice mode selector SHALL be available
- **AND** all voice modes (Silent, Listening, Conversation, Reading) SHALL function

#### Scenario: Speech recognition

- **GIVEN** a continuous listening voice mode is active
- **WHEN** the user speaks
- **THEN** speech SHALL be recognized and displayed in the input field
- **AND** recognized text can be submitted to the engine

#### Scenario: Text-to-speech playback

- **GIVEN** an auto-playback voice mode is active
- **WHEN** an assistant response is received
- **THEN** the response SHALL be spoken aloud via TTS
