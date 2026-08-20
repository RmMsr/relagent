# cli-chat-repl Specification

## Purpose
Provide an interactive terminal chat session against the engine, with a
live multi-line input area and inline handling of tool-call approval
requests, without requiring the full Flutter app.
## Requirements
### Requirement: Fresh Session Per Launch
The REPL SHALL create a new chat session on the first user input of each
launch and SHALL NOT resume or reuse a session from a previous launch.

#### Scenario: New session created on first message
- **WHEN** the user submits their first message after starting the REPL
- **THEN** the REPL creates a new session with the engine before sending
  that message

### Requirement: Streamed Response Display
The REPL SHALL display the assistant's reply incrementally as it streams
from the engine, appended to the terminal's normal scrollback rather than
redrawn or cleared.

#### Scenario: Tokens appear as they arrive
- **WHEN** the engine streams an assistant reply
- **THEN** the REPL prints each portion of the reply as it is received
- **AND** previously printed transcript is not modified or redrawn

### Requirement: Multi-line Expanding Input
The REPL SHALL provide an input area that grows to accommodate multi-line
input as the user types, without altering previously printed transcript.

#### Scenario: Input area grows with multi-line text
- **WHEN** the user enters text that spans more than one line before
  submitting
- **THEN** the input area visibly expands to show all entered lines

#### Scenario: Transcript unaffected by input growth
- **WHEN** the input area expands or shrinks while composing a message
- **THEN** chat history already printed above the input area remains
  unchanged

### Requirement: Sequential Turn Enforcement
The REPL SHALL NOT submit a new message while a previous cycle has not yet
settled.

#### Scenario: Input inactive while awaiting a response
- **WHEN** a message has been sent and its cycle has not yet settled
  (including while an approval decision is pending)
- **THEN** the REPL does not accept or submit a new message until that
  cycle settles

### Requirement: Interactive Approval Decision
When the engine reports a pending tool-call approval, the REPL SHALL
prompt the user to either grant it or continue without it, and SHALL NOT
proceed until the user responds.

#### Scenario: User grants a pending approval
- **WHEN** the engine reports a pending approval during a cycle
- **THEN** the REPL prompts the user with a grant/continue-without choice
- **AND** if the user grants it, the REPL signals the grant to the engine
  and resumes the cycle

#### Scenario: User declines a pending approval
- **WHEN** the engine reports a pending approval during a cycle
- **AND** the user chooses to continue without granting it
- **THEN** the REPL signals the decline to the engine and the cycle
  resumes without that tool's result

