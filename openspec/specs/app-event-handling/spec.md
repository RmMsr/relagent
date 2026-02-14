# app-event-handling Specification

## Purpose
TBD - created by archiving change add-async-notifications. Update Purpose after archive.
## Requirements
### Requirement: App Event System

The app SHALL provide a typed event system that receives and processes events from the engine and from local app sources.

#### Scenario: Typed event model

- **GIVEN** an SSE message or local event source produces an event
- **WHEN** the event is parsed
- **THEN** it SHALL be transformed into a specific typed event object per event kind (e.g., `SessionUpdatedEvent`, `MessagesAppendedEvent`)
- **AND** each typed event SHALL carry only the fields relevant to that event kind
- **AND** a single generic container with optional fields for all event kinds SHALL NOT be used

#### Scenario: Event continuation

- **GIVEN** an event is received from the engine
- **WHEN** it has been processed by the app
- **THEN** the app SHALL remember the event id
- **AND** the app SHALL use the last seen event id for all later event subscriptions

#### Scenario: Local event sources

- **GIVEN** an app-internal event occurs (e.g., disconnect, reconnect, settings saved)
- **WHEN** such an event is generated
- **THEN** the app SHALL create a typed event locally
- **AND** local events SHALL be processed through the same event system as engine events

### Requirement: Update Event Processing

The app SHALL process update events by fetching relevant data from the engine when the update is applicable to the current app state.

#### Scenario: Session updated

- **GIVEN** a `session.updated` event is received
- **WHEN** the named session is currently visible in the chat
- **THEN** updated session info SHALL be fetched from the engine and applied
- **AND** if the named session is not currently visible, the event SHALL be ignored

#### Scenario: Session messages appended

- **GIVEN** a `session.messages.appended` event is received
- **WHEN** the named session is currently visible in the chat
- **AND** the local message sequence_id is lower than the sequence_id from the event
- **THEN** new messages SHALL be fetched from the engine and applied
- **AND** if the session is not visible or the local sequence_id is already current, the event SHALL be ignored

#### Scenario: Multiple pending update events

- **GIVEN** multiple update events are available but not yet processed
- **WHEN** the app starts processing them
- **THEN** duplicate events SHALL be identified and marked to be ignored
- **AND** the app SHALL process remaining events in order

