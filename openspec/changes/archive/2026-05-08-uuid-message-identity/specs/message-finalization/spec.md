## MODIFIED Requirements

### Requirement: Read-Time Default for Missing Final Field

The persistence adapter SHALL handle records that lack the `final` field by assuming `final=true` in-memory without writing back to storage. Cases where this differs from the truth are close to zero, so write-back is unnecessary.

#### Scenario: Old record without final field

- **GIVEN** a persisted message written before this change rolled out, with no `final` field in storage
- **WHEN** the persistence adapter loads the record
- **THEN** the in-memory model SHALL have `final=true`
- **AND** no UPDATE SHALL be triggered by the read
- **AND** subsequent reads SHALL return the same in-memory value

#### Scenario: New record with explicit final field

- **GIVEN** a persisted message written after this change rolled out, with `final=false` in storage
- **WHEN** the persistence adapter loads the record
- **THEN** the in-memory model SHALL have `final=false`
- **AND** no UPDATE SHALL be triggered by the read

#### Scenario: Read-only fallback path is annotated for removal

- **GIVEN** the read-only fallback path for missing `final`
- **WHEN** the codebase is inspected
- **THEN** the path SHALL carry an explicit comment marking it as backwards-compatibility code
- **AND** the comment SHALL describe the trigger for removal (e.g., "remove once all stored rows have non-NULL final")

### Requirement: Settlement and Mutation Events Identify Cycle by UserMessage UUID

When the engine appends or mutates messages within a cycle (settlement on `AssistantMessage` append, settlement via `stop_cycle`, or appending an additional in-flight `SystemAction` during `continue_session`), the engine's internal cycle reference SHALL be the `message_id` (UUID) of the `UserMessage` that opened the cycle. The published `session.messages.appended` event SHALL be notification-only and SHALL NOT carry the cycle's identifier — clients reload using their own cursor and the ingest function reconciles changes idempotently.

#### Scenario: perform_user_input settles cycle

- **GIVEN** a session with no prior in-flight cycle
- **WHEN** `perform_user_input` appends a `UserMessage` and an `AssistantMessage`
- **THEN** the engine SHALL flip `final=true` on the `UserMessage` opened by this call
- **AND** a single `messages.appended` event SHALL be published carrying only `session_id`

#### Scenario: continue_session settles cycle

- **GIVEN** a session whose trailing in-flight chain is `UserMessage(final=false)` followed by one or more `SystemAction(final=false)`
- **WHEN** `continue_session` appends an `AssistantMessage` and settles the cycle
- **THEN** every preceding in-flight message back to and including the cycle's `UserMessage` SHALL be flipped to `final=true`
- **AND** a single `messages.appended` event SHALL be published carrying only `session_id`

#### Scenario: continue_session appends another SystemAction without settling

- **GIVEN** a session with an in-flight cycle
- **WHEN** `continue_session` appends a new `SystemAction(final=false)` (no settlement)
- **THEN** a `messages.appended` event SHALL be published carrying only `session_id`
- **AND** no message's `final` flag SHALL be flipped

#### Scenario: stop_cycle publishes notification

- **GIVEN** a session with an in-flight cycle ending in `SystemAction(final=false)`
- **WHEN** `stop_cycle` settles the cycle
- **THEN** every in-flight message in the cycle SHALL be flipped to `final=true`
- **AND** a single `messages.appended` event SHALL be published carrying only `session_id`
