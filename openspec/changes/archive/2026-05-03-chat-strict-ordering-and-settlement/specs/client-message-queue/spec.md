## ADDED Requirements

### Requirement: Three-State Send Machine

The chat client SHALL track exactly one of three states per session: `idle`, `awaiting`, or `awaiting + queued`. State transitions SHALL be driven by user submit, cycle settlement, and the edit-queued affordance.

#### Scenario: Idle state on fresh session

- **GIVEN** no cycle is in flight and no queued message exists
- **WHEN** the chat page is opened
- **THEN** the state SHALL be `idle`
- **AND** the input SHALL be enabled

#### Scenario: Submit while idle transitions to awaiting

- **GIVEN** the state is `idle`
- **WHEN** the user submits a message
- **THEN** the message SHALL be sent immediately to the engine via `POST /messages`
- **AND** the state SHALL transition to `awaiting`
- **AND** the input SHALL remain enabled

#### Scenario: Submit while awaiting transitions to awaiting + queued

- **GIVEN** the state is `awaiting` and no queued message exists
- **WHEN** the user submits a message
- **THEN** the message SHALL be retained client-side as the queued message
- **AND** the message SHALL NOT be sent to the engine
- **AND** the state SHALL transition to `awaiting + queued`
- **AND** the input SHALL be disabled

#### Scenario: Settle without queued message returns to idle

- **GIVEN** the state is `awaiting`
- **WHEN** the cycle settles (an `AssistantMessage` is appended or a Stop is acknowledged)
- **THEN** the state SHALL transition to `idle`
- **AND** the input SHALL be enabled

#### Scenario: Settle with queued message auto-sends and stays awaiting

- **GIVEN** the state is `awaiting + queued`
- **WHEN** the cycle settles
- **THEN** the queued message SHALL be sent to the engine via `POST /messages`
- **AND** the state SHALL transition to `awaiting`
- **AND** the input SHALL be enabled

### Requirement: At Most One Queued Message

The client SHALL allow at most one queued message per session at any time. Submission while a queued message exists SHALL be impossible because the input is disabled in `awaiting + queued`.

#### Scenario: Input disabled iff queued message exists

- **WHEN** the chat page is rendered
- **THEN** the input SHALL be enabled if and only if no queued message exists for the current session

#### Scenario: No second queue slot

- **GIVEN** the state is `awaiting + queued`
- **WHEN** any code path attempts to enqueue a second message
- **THEN** the attempt SHALL be rejected
- **AND** the existing queued message SHALL remain unchanged

### Requirement: Edit Queued Affordance

The client SHALL provide an affordance that pulls the queued message back into the input field. Activating it SHALL remove the queued message from the chat list and load its text into the input.

#### Scenario: Edit queued returns state to awaiting

- **GIVEN** the state is `awaiting + queued`
- **WHEN** the user activates "edit queued"
- **THEN** the queued message SHALL be removed from the chat list
- **AND** its text SHALL be loaded into the input
- **AND** the state SHALL transition to `awaiting`
- **AND** the input SHALL be enabled

#### Scenario: Edit queued does not contact the engine

- **WHEN** the user activates "edit queued"
- **THEN** no request SHALL be sent to the engine
- **AND** no persisted record SHALL change

### Requirement: Inline Chronological Rendering of Queued Message

The queued message SHALL be rendered inline in the chat list, in chronological position, with a visually distinct "QUEUED" style.

#### Scenario: Queued bubble appears in chronological position

- **GIVEN** a queued message exists
- **WHEN** the chat list is rendered
- **THEN** the queued message SHALL appear after all other client-known messages and before the input
- **AND** the bubble SHALL carry a "QUEUED" visual treatment that distinguishes it from sent and settled messages

#### Scenario: Queued bubble transitions in place when sent

- **GIVEN** a queued message is rendered inline
- **WHEN** the cycle settles and the client auto-sends the queued message
- **THEN** the bubble SHALL update to the sent visual treatment in place
- **AND** the chat list SHALL NOT visibly reorder

### Requirement: Single-Cycle-In-Flight Invariant

The client SHALL ensure no more than one cycle is in flight per session at any time. The state machine and queue mechanism together SHALL make a second concurrent send impossible from this client.

#### Scenario: Second submit during awaiting is queued, not sent

- **GIVEN** the state is `awaiting`
- **WHEN** the user submits a second message
- **THEN** the engine SHALL receive zero new requests for the duration of the in-flight cycle
- **AND** the second message SHALL be visible only as a queued bubble
