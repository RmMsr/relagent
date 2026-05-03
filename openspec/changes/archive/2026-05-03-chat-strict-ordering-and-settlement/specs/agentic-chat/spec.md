## MODIFIED Requirements

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

## ADDED Requirements

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
