# chat-history Specification

## Purpose
TBD - created by archiving change improve-chat-history-layout. Update Purpose after archive.
## Requirements
### Requirement: Compact Timestamp Display

The system SHALL display message timestamps inline with the role identifier on a single line to reduce vertical space usage.

#### Scenario: Timestamp format for user messages

- **WHEN** a user message is displayed
- **THEN** the timestamp SHALL be shown as "user • HH:MM:SS" format
- **AND** timestamp SHALL be on the same line as the role identifier
- **AND** bullet separator "•" SHALL be used instead of "@"

#### Scenario: Timestamp format for assistant messages

- **WHEN** an assistant message is displayed
- **THEN** the timestamp SHALL be shown as "assistant • HH:MM:SS" format
- **AND** timestamp SHALL be on the same line as the role identifier
- **AND** bullet separator "•" SHALL be used instead of "@"

#### Scenario: Timestamp styling

- **WHEN** timestamp is displayed
- **THEN** font size SHALL be smaller than message content
- **AND** color SHALL be subtle/muted (e.g., gray) for reduced prominence
- **AND** timestamp SHALL remain readable without accessibility issues

#### Scenario: No separate timestamp line

- **WHEN** rendering message bubble
- **THEN** timestamp SHALL NOT occupy a separate centered line above the message
- **AND** vertical space previously used by separate line SHALL be eliminated

### Requirement: Message Grouping by Sender

The system SHALL visually group consecutive messages from the same sender to improve conversation flow and reduce redundancy.

#### Scenario: Consecutive messages from same sender

- **WHEN** multiple messages from the same sender appear consecutively
- **THEN** messages SHALL be visually grouped together
- **AND** minimal spacing SHALL be applied between messages in the group
- **AND** larger spacing SHALL separate groups from different senders

#### Scenario: Timestamp shown once per group

- **WHEN** messages are grouped by sender
- **THEN** timestamp and role identifier SHALL be shown only for the first message in the group
- **AND** subsequent messages in the group SHALL NOT display redundant timestamps
- **AND** each message SHALL remain individually identifiable

#### Scenario: Group break on sender change

- **WHEN** sender changes from user to assistant or vice versa
- **THEN** a new message group SHALL begin
- **AND** visual spacing SHALL increase to indicate group boundary
- **AND** new group's first message SHALL display timestamp and role

#### Scenario: Group break on time gap

- **WHEN** time between consecutive messages from same sender exceeds 5 minutes
- **THEN** a new message group SHALL begin
- **AND** both groups SHALL display timestamps for temporal clarity
- **AND** visual spacing MAY increase slightly to indicate time gap

#### Scenario: Single message group

- **WHEN** a sender has only one message before sender changes
- **THEN** message SHALL display timestamp and role as normal
- **AND** grouping layout SHALL still apply (consistent padding and spacing)

### Requirement: Integrated Action Buttons

The system SHALL position action buttons (speaker, retry) inside message bubble footers using outline style to reduce visual clutter.

#### Scenario: Speaker button in assistant message footer

- **WHEN** an assistant message is displayed
- **THEN** speaker button (play/pause/read aloud) SHALL be positioned in the message bubble footer
- **AND** button SHALL use outline/ghost style (not filled)
- **AND** button SHALL be left-aligned within the footer
- **AND** button functionality SHALL remain unchanged

#### Scenario: Retry button in user message footer

- **WHEN** a user message is displayed
- **THEN** retry button SHALL be positioned in the message bubble footer
- **AND** button SHALL use outline/ghost style (not filled)
- **AND** button SHALL be right-aligned within the footer
- **AND** button functionality SHALL remain unchanged

#### Scenario: Action button visibility

- **WHEN** action buttons are in outline style
- **THEN** buttons SHALL be visually lighter than filled buttons
- **AND** buttons SHALL remain clearly interactive (visible borders/icons)
- **AND** tap/click targets SHALL maintain adequate size (min 44x44 points)

#### Scenario: No external button positioning

- **WHEN** message bubble is rendered
- **THEN** action buttons SHALL NOT be positioned outside the bubble boundaries
- **AND** horizontal space previously used for external buttons SHALL be reclaimed
- **AND** bubble shall contain all interactive elements

### Requirement: Refined Visual Identity

The system SHALL distinguish user and assistant messages through alignment and background styling, with assistant messages blending into the app background.

#### Scenario: Assistant message styling

- **WHEN** an assistant message is displayed
- **THEN** message SHALL NOT have a distinct background color/bubble
- **AND** message SHALL blend with the app's default background
- **AND** message SHALL be left-aligned
- **AND** message content SHALL remain fully readable

#### Scenario: User message styling

- **WHEN** a user message is displayed
- **THEN** message SHALL have a distinct background color (current light blue/gray)
- **AND** message SHALL be right-aligned
- **AND** background SHALL clearly differentiate user input from assistant responses

#### Scenario: Clear visual separation

- **WHEN** viewing conversation history
- **THEN** user messages SHALL be easily distinguishable from assistant messages
- **AND** distinction SHALL be achieved through alignment and background (not colors alone for accessibility)
- **AND** conversation flow SHALL be intuitive and scannable

### Requirement: Reduced Vertical Spacing

The system SHALL minimize vertical spacing between UI elements to increase message density and improve conversation overview.

#### Scenario: Tight spacing within message groups

- **WHEN** consecutive messages from same sender are displayed
- **THEN** spacing between messages SHALL be minimal (e.g., 4-8 points)
- **AND** messages SHALL appear visually connected as a group
- **AND** individual message boundaries SHALL remain clear

#### Scenario: Moderate spacing between sender groups

- **WHEN** sender changes (user to assistant or vice versa)
- **THEN** spacing SHALL be larger than within-group spacing (e.g., 16-24 points)
- **AND** spacing SHALL clearly indicate sender transition
- **AND** spacing SHALL not be excessive (not current large gap)

#### Scenario: Increased message visibility

- **WHEN** chat history is viewed on a typical mobile screen
- **THEN** at least 5-8 messages SHALL be visible without scrolling
- **AND** message density SHALL be 2-3x higher than previous layout
- **AND** readability SHALL not be compromised by tighter spacing

#### Scenario: Padding consistency

- **WHEN** message bubbles are rendered
- **THEN** internal padding (text to bubble edge) SHALL be consistent
- **AND** padding SHALL provide comfortable reading space
- **AND** padding SHALL not contribute to excessive vertical height

### Requirement: Maintained Functionality

The system SHALL preserve all existing chat history functionality while improving layout and spacing.

#### Scenario: Message selection and copying

- **WHEN** user attempts to select message text
- **THEN** text selection SHALL work as before (SelectableRegion)
- **AND** selection SHALL not be impaired by new layout

#### Scenario: Markdown rendering

- **WHEN** assistant message contains markdown
- **THEN** markdown SHALL be rendered correctly (GptMarkdown)
- **AND** code blocks, tables, and formatting SHALL display properly
- **AND** new layout SHALL accommodate various content types

#### Scenario: TTS playback controls

- **WHEN** user interacts with speaker button
- **THEN** TTS playback SHALL start/pause/resume as before
- **AND** button state SHALL update to reflect playback status
- **AND** icon SHALL change appropriately (play/pause)

#### Scenario: Message retry

- **WHEN** user clicks retry button
- **THEN** message SHALL be re-sent to chat provider
- **AND** retry functionality SHALL work identically to previous implementation

#### Scenario: Error message display

- **WHEN** an error message is shown
- **THEN** error SHALL be clearly visible with appropriate styling
- **AND** error SHALL be distinguishable from normal messages
- **AND** error SHALL integrate with new layout system

#### Scenario: Pending message placeholder

- **WHEN** waiting for assistant response
- **THEN** pending placeholder animation SHALL display as before
- **AND** placeholder SHALL fit new layout spacing
- **AND** transition to actual message SHALL be smooth

### Requirement: Accessibility Compliance

The system SHALL maintain accessibility standards while implementing compact layout.

#### Scenario: Touch target sizes

- **WHEN** action buttons are rendered in outline style
- **THEN** tap targets SHALL meet minimum size requirements (44x44 points)
- **AND** buttons SHALL have adequate spacing to prevent mis-taps
- **AND** buttons SHALL provide haptic/visual feedback on press

#### Scenario: Color contrast

- **WHEN** timestamps and subtle elements are displayed
- **THEN** text SHALL meet WCAG AA contrast requirements (4.5:1 for small text)
- **AND** muted colors SHALL remain readable for users with visual impairments

#### Scenario: Screen reader support

- **WHEN** screen reader traverses chat history
- **THEN** messages SHALL be announced with role and content
- **AND** timestamps SHALL be included in announcements
- **AND** action buttons SHALL have clear labels (not just icons)

