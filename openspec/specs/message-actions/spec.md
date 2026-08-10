# message-actions Specification

## Purpose

Defines the copy-to-clipboard and link-tap-confirmation behavior available on markdown-rendered chat messages, shared across the simple chat and agentic chat surfaces.

## Requirements

### Requirement: Copy Message Text

The system SHALL provide a copy action on every markdown-rendered chat message that places the message's raw, unrendered text on the system clipboard.

#### Scenario: Copying a multi-paragraph assistant message

- **WHEN** a user activates the copy action on an assistant message containing multiple paragraphs
- **THEN** the full raw message text, including the original paragraph breaks, is placed on the system clipboard
- **AND** the copied text is unaffected by how the message is split into widgets for on-screen rendering or TTS highlighting

#### Scenario: Copying a single-paragraph message

- **WHEN** a user activates the copy action on a message
- **THEN** the message's raw text is placed on the system clipboard exactly as stored, without markdown syntax being stripped or rendered

### Requirement: Link Tap Confirmation

The system SHALL, when a user taps a link rendered inside a markdown message, show a confirmation prompt displaying the link's destination URL before leaving the app, and SHALL only navigate to the destination if the user confirms.

#### Scenario: Tapping a link shows the destination

- **WHEN** a user taps a link inside a markdown-rendered message
- **THEN** a confirmation prompt is shown displaying the link's destination URL

#### Scenario: Confirming opens the link

- **WHEN** a user confirms the prompt shown after tapping a link
- **THEN** the system attempts to open the destination URL using the platform's default handler for that URL's scheme

#### Scenario: Cancelling does not navigate

- **WHEN** a user dismisses or cancels the prompt shown after tapping a link
- **THEN** the destination URL is not opened
- **AND** the user remains on the current screen

#### Scenario: Destination cannot be opened

- **WHEN** a user confirms a link and the platform reports it cannot open the destination URL
- **THEN** the system informs the user that the link could not be opened
- **AND** does not fail silently
