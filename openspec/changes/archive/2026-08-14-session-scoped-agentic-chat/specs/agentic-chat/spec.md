## ADDED Requirements

### Requirement: Session Isolation

Switching the displayed session SHALL NOT leak another session's messages, pending approvals, loading indicators, or title into the newly displayed session's view. A response to a request issued while a given session was displayed SHALL NOT be applied to chat state after the user has switched to a different session, regardless of how long that request takes to resolve.

#### Scenario: Switching sessions clears the previous session's messages and approvals

- **WHEN** the user switches from a session with messages and pending approvals to a different session
- **THEN** the displayed message list SHALL show only the newly selected session's history
- **AND** no message or approval from the previously displayed session SHALL appear

#### Scenario: A stale response does not attach to the newly displayed session

- **GIVEN** a request (send message, continue, stop cycle, grant approval, or background refresh) was issued while session A was displayed
- **WHEN** the user switches to session B before that request resolves
- **AND** the request's response subsequently arrives
- **THEN** the response SHALL NOT be applied to the currently displayed chat state
- **AND** session B's view SHALL remain unaffected by it

#### Scenario: Switching sessions clears stale loading and pending indicators

- **GIVEN** session A has an in-flight send or continuation showing a loading or "assistant is typing" indicator
- **WHEN** the user switches to session B
- **THEN** session B SHALL NOT display a loading or pending indicator left over from session A

#### Scenario: Switching sessions clears the previous session's title

- **GIVEN** session A's title is displayed
- **WHEN** the user switches to session B
- **THEN** session A's title SHALL NOT remain displayed
- **AND** the title SHALL be cleared until session B's own title is loaded

#### Scenario: A session with an unresolved approval is not lost when navigated away from

- **GIVEN** session A has an in-flight cycle awaiting approval resolution
- **WHEN** the user navigates away to a different session
- **AND** later switches back to session A
- **THEN** session A's in-flight state, including the pending approval, SHALL still be present

### Requirement: Sessions List Reflects Background Activity

A session that is not currently displayed SHALL still surface new activity in the sessions list rather than appearing untouched until the user reopens it.

#### Scenario: Background session activity updates the sessions list

- **GIVEN** a session is not currently displayed
- **WHEN** new messages are appended to that session (for example, a background approval is granted and the cycle continues)
- **THEN** the sessions list SHALL show an updated last-activity timestamp for that session
- **AND** the session SHALL move to the top of the sessions list
