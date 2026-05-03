# engine-in-flight-guard Specification

## Purpose
TBD - created by archiving change chat-strict-ordering-and-settlement. Update Purpose after archive.
## Requirements
### Requirement: Wait for Settled State Before Processing New Messages

Before processing `POST /messages` for an existing session, the engine SHALL inspect the trailing persisted message. If the trailing message has `final=false`, the request SHALL wait for the cycle to settle before proceeding. The wait does NOT apply to `POST /continue`, because `/continue` is by definition the action that advances an in-flight cycle and would otherwise deadlock against itself.

#### Scenario: No in-flight cycle proceeds immediately

- **GIVEN** the trailing message for the target session has `final=true` (or the session has no messages)
- **WHEN** `POST /messages` is called
- **THEN** the engine SHALL proceed with normal processing without delay

#### Scenario: In-flight cycle waits for settle

- **GIVEN** the trailing message for the target session has `final=false`
- **WHEN** `POST /messages` is called
- **THEN** the engine SHALL poll the persistence layer at a short interval (default 250 ms) until the trailing message has `final=true`
- **AND** the engine SHALL then proceed with normal processing using the now-up-to-date history

#### Scenario: Wait timeout returns 409 Conflict

- **GIVEN** the trailing message for the target session has `final=false`
- **WHEN** the wait exceeds the configured timeout (default 30 seconds)
- **THEN** the engine SHALL return `409 Conflict`
- **AND** the response body SHALL include the session id and a description of the still-in-flight cycle (e.g., the trailing message id)
- **AND** the engine SHALL NOT process the request

#### Scenario: Continue endpoint does not wait

- **GIVEN** the trailing message has `final=false` (the in-flight cycle that `/continue` is meant to advance)
- **WHEN** `POST /continue` is called
- **THEN** the engine SHALL proceed without waiting
- **AND** any race with another concurrent `/continue` from a second client is an accepted v1 risk

### Requirement: Configurable Polling Parameters

The polling interval and timeout SHALL be configurable via engine settings, with sensible defaults.

#### Scenario: Default poll interval

- **WHEN** no override is configured
- **THEN** the engine SHALL poll every 250 milliseconds

#### Scenario: Default timeout

- **WHEN** no override is configured
- **THEN** the engine SHALL time out the wait after 30 seconds

### Requirement: Guard Applies to /messages Only

The wait SHALL be invoked from `POST /messages` (the entry point that starts a new cycle) before any agent-affecting work. It SHALL NOT be invoked from `POST /continue` or from state-mutating endpoints, since those operate on the in-flight cycle itself rather than competing with it.

#### Scenario: Guard wraps message endpoint

- **WHEN** `POST /messages` is invoked for an existing session
- **THEN** the wait SHALL run before any agent-affecting work begins

#### Scenario: Guard does not run for continue endpoint

- **WHEN** `POST /sessions/{id}/continue` is invoked
- **THEN** the wait SHALL NOT run; `/continue` advances the in-flight cycle directly

#### Scenario: Guard does not run for state-only endpoints

- **WHEN** `POST /sessions/{id}/approvals/{approval_id}/grant`, `POST /sessions/{id}/approvals/{approval_id}/decline`, or `POST /sessions/{id}/stop` is invoked
- **THEN** the wait SHALL NOT run, because these endpoints mutate the in-flight state itself rather than competing with it

### Requirement: Polling Uses Existing Persistence Reads

The wait SHALL be implemented using the same trailing-message read used by history reconstruction. No new concurrency primitive (lock, semaphore, event subscription) SHALL be introduced at the persistence port for this guard.

#### Scenario: No new persistence-port API

- **WHEN** the guard is implemented
- **THEN** the persistence port SHALL NOT gain a lock, semaphore, or pub/sub primitive solely to support this feature
- **AND** the implementation SHALL rely on repeated reads of the trailing message

