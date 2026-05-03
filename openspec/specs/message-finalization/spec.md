# message-finalization Specification

## Purpose
TBD - created by archiving change chat-strict-ordering-and-settlement. Update Purpose after archive.
## Requirements
### Requirement: Universal Final Flag on Persisted Messages

Every persisted message (`UserMessage`, `AssistantMessage`, and `SystemAction`) SHALL carry a boolean `final` field that distinguishes in-flight (`final=false`) from settled (`final=true`) state. The flag SHALL transition one-way from `false` to `true` exactly once per message.

#### Scenario: AssistantMessage created final

- **WHEN** the engine appends a new `AssistantMessage` to a session
- **THEN** the persisted record SHALL have `final=true`

#### Scenario: UserMessage created in-flight

- **WHEN** the engine accepts a new user message via `POST /messages`
- **THEN** the persisted `UserMessage` SHALL have `final=false`

#### Scenario: SystemAction created in-flight

- **WHEN** the engine appends a `SystemAction` (e.g., for a deferred tool call) during an open cycle
- **THEN** the persisted record SHALL have `final=false`

#### Scenario: Final flag is one-way

- **GIVEN** a persisted message with `final=true`
- **WHEN** any code path attempts to write to that message
- **THEN** the persistence layer SHALL reject the write
- **AND** an error SHALL be raised describing the immutability violation

### Requirement: Per-Type Mutability While In-Flight

While `final=false`, only the narrowly defined mutable state per message type SHALL be writable. Message content (text fields) SHALL never be mutable after creation.

#### Scenario: UserMessage content immutable

- **GIVEN** a persisted `UserMessage` with `final=false`
- **WHEN** any code attempts to modify its `content` field
- **THEN** the persistence layer SHALL reject the write

#### Scenario: SystemAction approval grant mutable

- **GIVEN** a persisted `SystemAction` with `final=false` carrying approvals with `granted=null`
- **WHEN** the engine sets `granted=true` or `granted=false` on an approval
- **THEN** the write SHALL succeed
- **AND** the `SystemAction.final` flag SHALL remain `false` until a settlement event

#### Scenario: AssistantMessage never mutable

- **GIVEN** a persisted `AssistantMessage` (always created with `final=true`)
- **WHEN** any code attempts to modify any field
- **THEN** the persistence layer SHALL reject the write

### Requirement: Settlement Flips Final on the In-Flight Chain

When a settlement event occurs, the engine SHALL flip `final` to `true` on every preceding in-flight message back to and including the `UserMessage` that opened the cycle.

#### Scenario: AssistantMessage append settles the cycle

- **GIVEN** a session whose trailing in-flight chain is `UserMessage(final=false)`, optionally followed by one or more `SystemAction(final=false)`
- **WHEN** an `AssistantMessage` is appended
- **THEN** the appended `AssistantMessage` SHALL be persisted with `final=true`
- **AND** every preceding in-flight message back to and including the cycle's `UserMessage` SHALL be updated to `final=true`

#### Scenario: Stop settles the cycle without an AssistantMessage

- **GIVEN** a session whose trailing in-flight chain ends in a `SystemAction(final=false)` with one or more undecided approvals
- **WHEN** the cycle is stopped via `POST /sessions/{id}/stop`
- **THEN** every undecided approval SHALL be set to `granted=false`
- **AND** the trailing `SystemAction(s)` SHALL be set to `final=true`
- **AND** the cycle's `UserMessage` SHALL be set to `final=true`
- **AND** no new record SHALL be appended to the session

#### Scenario: Settlement is atomic per cycle

- **WHEN** a settlement event runs
- **THEN** either every message in the in-flight chain transitions to `final=true` together, or none do
- **AND** a partial transition SHALL NOT be observable by readers

### Requirement: Read-Time Default for Missing Final Field

The persistence adapter SHALL supply `final=true` when deserializing a stored record that lacks the `final` field, so that pre-cutover messages load as settled history without a write migration.

#### Scenario: Old record without final field

- **GIVEN** a persisted message written before this change rolled out, with no `final` field in storage
- **WHEN** the persistence adapter loads the record
- **THEN** the in-memory model SHALL have `final=true`

#### Scenario: New record with explicit final field

- **GIVEN** a persisted message written after this change rolled out, with `final=false` in storage
- **WHEN** the persistence adapter loads the record
- **THEN** the in-memory model SHALL have `final=false`

#### Scenario: No bulk write to existing data

- **WHEN** the change is deployed
- **THEN** the engine SHALL NOT execute a migration job that writes to pre-existing message records
- **AND** old sessions SHALL remain readable and resumable using the read-time default

### Requirement: Settlement and Mutation Events Publish Cycle-Start Sequence Id

When the engine appends or mutates messages within a cycle (settlement on `AssistantMessage` append, settlement via `stop_cycle`, or appending an additional in-flight `SystemAction` during `continue_session`), the published `session.messages.appended` event SHALL carry the sequence_id of the `UserMessage` that opened the affected cycle, not the trailing message's sequence_id. This lets clients reload the entire range that may have changed (final flag flips, approval grant updates) rather than only the tail.

#### Scenario: perform_user_input settles cycle and publishes UserMessage sequence_id

- **GIVEN** a session with no prior in-flight cycle
- **WHEN** `perform_user_input` appends a `UserMessage` and an `AssistantMessage`
- **THEN** the published `messages.appended` event SHALL carry the new `UserMessage`'s sequence_id

#### Scenario: continue_session settles cycle and publishes UserMessage sequence_id

- **GIVEN** a session whose trailing in-flight chain is `UserMessage(final=false)` followed by one or more `SystemAction(final=false)`
- **WHEN** `continue_session` appends an `AssistantMessage` and settles the cycle
- **THEN** the published `messages.appended` event SHALL carry the cycle's `UserMessage` sequence_id (not the new `AssistantMessage`'s)

#### Scenario: continue_session appends another SystemAction without settling

- **GIVEN** a session with an in-flight cycle
- **WHEN** `continue_session` appends a new `SystemAction(final=false)` (no settlement)
- **THEN** the published `messages.appended` event SHALL carry the cycle's `UserMessage` sequence_id

#### Scenario: stop_cycle publishes UserMessage sequence_id

- **GIVEN** a session with an in-flight cycle ending in `SystemAction(final=false)`
- **WHEN** `stop_cycle` settles the cycle
- **THEN** the published `messages.appended` event SHALL carry the cycle's `UserMessage` sequence_id

### Requirement: History Reconstruction Honors Final Flag

The history reconstruction in `_get_known_history_from_messages` SHALL use the `final` flag as the authoritative signal for "is this message settled," rather than inferring state from the relative order of `SystemAction` and `AssistantMessage` records.

#### Scenario: Stopped cycle in history

- **GIVEN** a session whose trailing settled cycle is a `UserMessage(final=true)` followed by a `SystemAction(final=true)` with all approvals declined and no `AssistantMessage`
- **WHEN** history is reconstructed for a subsequent agent run
- **THEN** the stopped cycle SHALL be included as immutable history
- **AND** no error SHALL be raised about a missing `AssistantMessage`

#### Scenario: In-flight cycle excluded from agent history

- **GIVEN** a session whose trailing message has `final=false`
- **WHEN** history is reconstructed for a new request
- **THEN** the in-flight chain SHALL be handled by the engine-in-flight-guard rather than passed to the agent as history

