## ADDED Requirements

### Requirement: Session Listing Display

The system SHALL display a list of recent chat sessions sorted by last modified time, showing session title and relative modification time.

#### Scenario: Sessions page displays list

- **WHEN** the user navigates to the sessions page
- **THEN** the system SHALL display a list of recent sessions
- **AND** sessions SHALL be sorted by last modified time (most recent first)
- **AND** each session SHALL display its title
- **AND** each session SHALL display relative modification time (e.g., "2 minutes ago", "3 hours ago")

#### Scenario: Empty sessions list

- **WHEN** the user navigates to the sessions page
- **AND** there are no existing sessions
- **THEN** the system SHALL display an empty state message
- **AND** the message SHALL guide the user to start a new session

#### Scenario: Session title generation

- **WHEN** a session is created without an explicit title
- **THEN** the system SHALL generate a title from the first user message
- **AND** if no user message exists, the title SHALL be "New Session"
- **AND** the title SHALL be truncated to fit display constraints

### Requirement: Session Selection and Switching

The system SHALL allow users to select any session from the list to switch to that session's conversation.

#### Scenario: User selects a session

- **WHEN** the user taps on a session in the sessions list
- **THEN** the system SHALL navigate to the agentic chat page
- **AND** the chat page SHALL load the selected session's conversation history
- **AND** the session SHALL become the active session

#### Scenario: Session loads existing messages

- **WHEN** a user switches to an existing session
- **THEN** the chat history SHALL display all previous messages from that session
- **AND** the messages SHALL appear in chronological order
- **AND** the user SHALL be able to continue the conversation

#### Scenario: Active session indicator

- **WHEN** viewing the sessions list
- **THEN** the currently active session SHALL be visually distinguished
- **AND** the distinction SHALL use a different background color or highlight

### Requirement: Session Deletion with Confirmation

The system SHALL allow users to delete sessions with a confirmation dialog to prevent accidental deletion.

#### Scenario: User initiates deletion

- **WHEN** the user taps the delete option on a session
- **THEN** the system SHALL display a confirmation dialog
- **AND** the dialog SHALL ask "Delete this session?"
- **AND** the dialog SHALL have "Cancel" and "Delete" options

#### Scenario: User confirms deletion

- **WHEN** the user confirms deletion
- **THEN** the system SHALL delete the session and all its messages
- **AND** the session SHALL be removed from the sessions list
- **AND** a session deleted event SHALL be emitted

#### Scenario: User cancels deletion

- **WHEN** the user cancels the deletion dialog
- **THEN** the dialog SHALL close
- **AND** the session SHALL remain in the list
- **AND** no deletion SHALL occur

### Requirement: API Limit Parameter

The system SHALL support a limit parameter on the session listing endpoint to control the number of returned sessions.

#### Scenario: Default limit applied

- **WHEN** the session listing endpoint is called without a limit parameter
- **THEN** the system SHALL return up to 100 sessions
- **AND** sessions SHALL be sorted by last modified time (most recent first)

#### Scenario: Custom limit applied

- **WHEN** the session listing endpoint is called with a limit parameter
- **THEN** the system SHALL return up to the specified number of sessions
- **AND** the limit SHALL be a positive integer
- **AND** sessions SHALL be sorted by last modified time (most recent first)

#### Scenario: Limit bounds validation

- **WHEN** the limit parameter exceeds a reasonable maximum (e.g., 1000)
- **THEN** the system SHALL cap the results to the maximum allowed
- **AND** SHALL NOT return more sessions than the system can handle efficiently

### Requirement: New Session Button

The system SHALL replace the existing delete button on the agentic chat page with a "New Session" button.

#### Scenario: User starts new session

- **WHEN** the user taps the "New Session" button
- **THEN** the system SHALL create a new empty session
- **AND** the chat page SHALL clear and show the new session
- **AND** a session created event SHALL be emitted
- **AND** the new session SHALL become the active session

#### Scenario: New session has no history

- **WHEN** a new session is created
- **THEN** the chat history SHALL be empty
- **AND** the session SHALL have no messages
- **AND** the session SHALL be ready for user input
