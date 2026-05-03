# agentic-chat Specification

## Purpose

TBD - created by archiving change add-agentic-chat. Update Purpose after archive.
## Requirements
### Requirement: Agentic Chat Page

The system SHALL provide an Agentic Chat page as the primary frontend for the Relagent engine.

#### Scenario: Default app page

- **WHEN** the app is launched
- **THEN** the chat page for the selected backend SHALL be displayed by default

#### Scenario: Chat interface layout

- **WHEN** the Agentic Chat page is displayed
- **THEN** the page SHALL include a message list, text input, voice mode selector, navigation drawer, and a sensitivity indicator in the app bar
- **AND** the layout SHALL be consistent with the simple chat interface

#### Scenario: Material navigation drawer

- **WHEN** the user opens the navigation drawer (via hamburger icon or swipe)
- **THEN** the drawer SHALL follow Material Design NavigationDrawer pattern
- **AND** the drawer SHALL show entries: Chat (selected), Sessions (engine only), Settings, About
- **AND** the currently active page SHALL be indicated using the drawer's built-in selected state (no manual checkmark)
- **AND** the drawer SHALL NOT show separate "Simple Chat" and "Agentic Chat" entries

### Requirement: Engine Connection

The system SHALL connect to the Relagent engine API using the configured Engine URL.

#### Scenario: Successful connection

- **GIVEN** a valid Engine URL is configured
- **WHEN** the app communicates with the engine
- **THEN** messages SHALL be sent and received successfully

#### Scenario: Connection failure

- **GIVEN** the Engine URL is unreachable or invalid
- **WHEN** the app attempts to communicate
- **THEN** an error banner SHALL be displayed with "Retry" and "Check Settings" actions

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

### Requirement: Send Messages

The system SHALL send user messages to the engine API and display responses, subject to the strict-ordering constraint that at most one cycle is in flight per session at a time. When a cycle is already in flight, submitted messages SHALL be queued client-side rather than sent (see `client-message-queue`).

#### Scenario: Send message successfully when idle

- **GIVEN** the engine is connected
- **AND** no cycle is in flight for the session
- **WHEN** the user submits a message
- **THEN** the message SHALL be sent to the engine
- **AND** the engine response SHALL be displayed in the chat
- **AND** if the response is a `SystemAction`, it SHALL be rendered as system notes and/or approval cards (not as an assistant text bubble)

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

### Requirement: About page shows app icon and backend info

The about/info page SHALL display the app icon at the top, followed by the active chat backend type, configured base URL, and engine version when available.

#### Scenario: App icon displayed

- **WHEN** the user opens the About page
- **THEN** the app icon (minion) from `assets/icon/app-icon.png` SHALL be displayed prominently at the top of the page

#### Scenario: OpenAI-compatible backend info

- **GIVEN** the selected backend is OpenAI-compatible
- **WHEN** the user opens the About page
- **THEN** the page SHALL show "OpenAI-compatible" as the chat backend
- **AND** the page SHALL show the configured simple chat base URL

#### Scenario: Relagent Engine backend info

- **GIVEN** the selected backend is Relagent Engine
- **WHEN** the user opens the About page
- **THEN** the page SHALL show "Relagent Engine" as the chat backend
- **AND** the page SHALL show the configured engine base URL

#### Scenario: Engine version displayed when available

- **GIVEN** the selected backend is Relagent Engine
- **AND** a successful engine health check has been performed
- **WHEN** the user opens the About page
- **THEN** the page SHALL show the engine version from the health check result

#### Scenario: Engine version not shown when unavailable

- **GIVEN** no successful engine health check has been performed
- **WHEN** the user opens the About page
- **THEN** the engine version field SHALL NOT be displayed

### Requirement: Unified chat route

The router SHALL provide a single `/chat` route that displays the correct chat page based on the selected backend setting.

#### Scenario: Route to simple chat

- **GIVEN** the selected backend is OpenAI-compatible
- **WHEN** the user navigates to `/chat`
- **THEN** the simple chat page SHALL be displayed

#### Scenario: Route to agentic chat

- **GIVEN** the selected backend is Relagent Engine
- **WHEN** the user navigates to `/chat`
- **THEN** the agentic chat page SHALL be displayed

#### Scenario: Splash page navigates to unified route

- **GIVEN** the app is starting up
- **WHEN** the splash screen completes
- **THEN** navigation SHALL go to `/chat` regardless of the selected backend

### Requirement: Android app icon uses correct cropping

The Android adaptive icon SHALL use the foreground drawable without additional inset, relying on Android's built-in safe-zone handling for adaptive icons.

#### Scenario: No extra inset on Android icon

- **GIVEN** the Android adaptive icon configuration
- **WHEN** the app icon is rendered on Android
- **THEN** the foreground drawable SHALL NOT have an additional 16% inset
- **AND** the icon SHALL use `<foreground android:drawable="@drawable/ic_launcher_foreground"/>` directly

### Requirement: Three Visual Message States

The chat list SHALL render every message in exactly one of three visual states: sent (in flight), queued (held client-side, awaiting send), or settled (`final=true`). The visual treatment SHALL clearly distinguish all three.

#### Scenario: Sent (in-flight) bubble style

- **GIVEN** a `UserMessage` with `final=false` that the engine has acknowledged
- **WHEN** the chat list is rendered
- **THEN** the bubble SHALL use the standard sent-message style

#### Scenario: Queued bubble style

- **GIVEN** a queued message held client-side
- **WHEN** the chat list is rendered
- **THEN** the bubble SHALL use a visually distinct "QUEUED" style (e.g., dashed border, "QUEUED" label)
- **AND** the bubble SHALL appear in chronological position in the list

#### Scenario: Settled bubble style

- **GIVEN** a `UserMessage` or `AssistantMessage` with `final=true`
- **WHEN** the chat list is rendered
- **THEN** the bubble SHALL use the standard settled-message style (no special markings)

### Requirement: Incremental Refresh Honors Final Flag

When the app receives a `session.messages.appended` event with `latest_sequence_id = N`, it SHALL refetch messages from sequence_id `N` onwards. For each fetched message, the app SHALL overwrite the locally cached entry only if the cached entry has `final=false` (or is absent). Cached entries with `final=true` are immutable and SHALL NOT be overwritten.

#### Scenario: In-flight cached entry is overwritten on refresh

- **GIVEN** the app has a cached `SystemAction` with `final=false` at sequence_id 3
- **WHEN** a `messages.appended` event arrives with sequence_id 3 and the refetch returns the same `SystemAction` now with `final=true` and updated approval grants
- **THEN** the app SHALL replace the cached entry with the fetched one

#### Scenario: Settled cached entry is preserved across refresh

- **GIVEN** the app has a cached `AssistantMessage` with `final=true` at sequence_id 5
- **WHEN** a `messages.appended` event triggers a refetch that includes sequence_id 5 (e.g., a later cycle's UserMessage was at sequence_id 5)
- **THEN** the app SHALL NOT overwrite the cached `AssistantMessage`

#### Scenario: New message is appended

- **GIVEN** the app's cache ends at sequence_id 7
- **WHEN** the refetch returns a new message at sequence_id 8
- **THEN** the app SHALL append the new message to its cache

### Requirement: Input Disabled While Queued Message Exists

The chat input SHALL be enabled if and only if no queued message exists for the current session.

#### Scenario: Input enabled in idle state

- **GIVEN** no cycle is in flight and no queued message exists
- **WHEN** the chat page is rendered
- **THEN** the input SHALL be enabled

#### Scenario: Input enabled while awaiting (no queue)

- **GIVEN** a cycle is in flight but no queued message exists
- **WHEN** the chat page is rendered
- **THEN** the input SHALL be enabled

#### Scenario: Input disabled while queued message exists

- **GIVEN** a queued message exists for the current session
- **WHEN** the chat page is rendered
- **THEN** the input SHALL be disabled
- **AND** an affordance to edit the queued message SHALL be available

