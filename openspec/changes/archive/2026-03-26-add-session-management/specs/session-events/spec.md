## ADDED Requirements

### Requirement: Session Created Event

The system SHALL emit an event whenever a new session is created.

#### Scenario: Event emitted on session creation

- **WHEN** a new session is created
- **THEN** the system SHALL emit a "session_created" event
- **AND** the event SHALL include the session ID
- **AND** the event SHALL include the session title
- **AND** the event SHALL include the creation timestamp

#### Scenario: Sessions page receives created event

- **WHEN** the user is viewing the sessions page
- **AND** a session created event is emitted
- **THEN** the new session SHALL be added to the sessions list
- **AND** the list SHALL maintain chronological sorting by last modified time
- **AND** the new session SHALL appear in the correct position in the list

### Requirement: Session Deleted Event

The system SHALL emit an event whenever a session is deleted.

#### Scenario: Event emitted on session deletion

- **WHEN** a session is deleted
- **THEN** the system SHALL emit a "session_deleted" event
- **AND** the event SHALL include the session ID
- **AND** the event SHALL include the deletion timestamp

#### Scenario: Sessions page receives deleted event

- **WHEN** the user is viewing the sessions page
- **AND** a session deleted event is emitted
- **THEN** the deleted session SHALL be removed from the sessions list
- **AND** the list SHALL update without requiring a page refresh

### Requirement: Active Session Deleted Notification

The system SHALL notify the user and create a new session when the currently active session is deleted.

#### Scenario: User receives notification when active session deleted

- **WHEN** the currently active session is deleted (by any means)
- **THEN** the system SHALL display a notification to the user
- **AND** the notification SHALL inform the user that the active session was deleted
- **AND** the notification SHALL be dismissible

#### Scenario: New session created automatically

- **WHEN** the currently active session is deleted
- **THEN** the system SHALL automatically create a new empty session
- **AND** the new session SHALL become the active session
- **AND** the chat page SHALL transition to the new session
- **AND** the user SHALL be able to start chatting immediately

#### Scenario: Active session deletion on chat page

- **WHEN** the user is on the agentic chat page
- **AND** the active session is deleted externally (e.g., from sessions page on another device)
- **THEN** the system SHALL show the notification
- **AND** the chat SHALL transition to a new empty session
- **AND** the previous session's messages SHALL no longer be displayed

### Requirement: Event Subscription

The system SHALL provide a mechanism for components to subscribe to session lifecycle events.

#### Scenario: Component subscribes to events

- **WHEN** a component needs to listen for session events
- **THEN** the component SHALL be able to subscribe to session event streams
- **AND** the subscription SHALL receive all future session events
- **AND** the component SHALL be able to unsubscribe when no longer needed

#### Scenario: Event delivery to multiple subscribers

- **WHEN** multiple components subscribe to session events
- **AND** a session event is emitted
- **THEN** all subscribed components SHALL receive the event
- **AND** each component SHALL be able to handle the event independently
