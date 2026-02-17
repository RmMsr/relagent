## MODIFIED Requirements

### Requirement: App SSE Client

The app SHALL connect to the engine's SSE endpoint for real-time updates.

#### Scenario: Establish SSE connection

- **GIVEN** the app is configured with a valid engine URL
- **WHEN** the app starts or the chat page is opened
- **THEN** the app SHALL establish an SSE connection to `/api/v1/events`

#### Scenario: Automatic reconnection

- **GIVEN** the SSE connection is lost
- **WHEN** the connection drops
- **THEN** the app SHALL attempt to reconnect with exponential backoff
- **AND** the reconnection request SHALL include `Last-Event-ID` if available

#### Scenario: Resource cleanup on reconnect

- **GIVEN** the SSE client is reconnecting after a connection drop
- **WHEN** a new connection attempt starts
- **THEN** the previous stream subscription SHALL be cancelled before creating a new one
- **AND** the previous HTTP client SHALL be closed before creating a new one
- **AND** an injected test client SHALL NOT be closed

#### Scenario: App lifecycle resume reconnection

- **GIVEN** the app was backgrounded and the SSE connection was lost
- **WHEN** the app returns to the foreground
- **THEN** the SSE connection SHALL be re-established
- **AND** the reconnect attempt counter SHALL be reset so that the maximum attempts limit does not prevent reconnection
- **AND** missed events SHALL be replayed via `Last-Event-ID`

#### Scenario: Refresh data on notification

- **GIVEN** the app is connected to the event stream
- **WHEN** a notification for the current session is received
- **THEN** the app SHALL fetch the updated data from the relevant REST endpoint
- **AND** the UI SHALL update to reflect the changes

#### Scenario: Handle connection loss gracefully

- **GIVEN** the SSE connection is lost and reconnected
- **WHEN** the reconnection succeeds
- **THEN** the app MAY fetch full session state to ensure consistency
- **AND** no duplicate data SHALL be displayed
