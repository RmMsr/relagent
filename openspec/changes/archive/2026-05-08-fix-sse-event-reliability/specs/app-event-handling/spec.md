## MODIFIED Requirements

### Requirement: Update Event Processing

The app SHALL process update events by fetching relevant data from the engine when the update is applicable to the current app state.

#### Scenario: Session updated

- **GIVEN** a `session.updated` event is received
- **WHEN** the named session is currently visible in the chat
- **THEN** updated session info SHALL be fetched from the engine and applied
- **AND** if the named session is not currently visible, the event SHALL be ignored

#### Scenario: Session created

- **GIVEN** a `session.created` event is received
- **WHEN** the named session is currently active in the chat
- **THEN** session info SHALL be fetched from the engine and applied to the chat page
- **AND** the active session ID SHALL be re-read from settings at comparison time rather than using a value captured earlier in the event handler

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
