# cli-single-turn Specification

## Purpose
Provide a non-interactive command that sends one prompt to the engine and
prints the reply, suitable for scripts and other automation that cannot
interact with a REPL.
## Requirements
### Requirement: Prompt Input Source
The single-turn command SHALL accept the prompt as a positional argument
when one is given, and SHALL otherwise read the prompt from stdin.

#### Scenario: Prompt given as an argument
- **WHEN** the command is invoked with a prompt as a positional argument
- **THEN** that argument is used as the prompt sent to the engine

#### Scenario: Prompt read from stdin
- **WHEN** the command is invoked with no positional prompt argument
- **THEN** the command reads the prompt from stdin

### Requirement: Plain-text Output Contract
On success, the single-turn command SHALL print only the final assistant
message text to stdout, with no additional framing, chrome, or metadata.

#### Scenario: Successful run prints only the reply
- **WHEN** a single-turn run completes successfully
- **THEN** stdout contains exactly the final assistant message text

### Requirement: Automatic Approval Decline
When the engine reports a pending tool-call approval during a single-turn
run, the command SHALL automatically decline it so the run can complete
without interactive input.

#### Scenario: Pending approval is declined automatically
- **WHEN** the engine reports a pending approval during a single-turn run
- **THEN** the command declines it without prompting
- **AND** the run continues until the cycle settles

### Requirement: Exit Code Reflects Outcome
The single-turn command SHALL exit with status 0 when the run completes
successfully, and SHALL exit with a non-zero status and an error message
on stderr when it does not.

#### Scenario: Successful completion
- **WHEN** a single-turn run completes and the cycle settles normally
- **THEN** the command exits with status 0

#### Scenario: Engine unreachable
- **WHEN** the engine cannot be reached for a single-turn run
- **THEN** the command prints an error message to stderr
- **AND** exits with a non-zero status

### Requirement: Fresh Session Per Invocation
Each single-turn invocation SHALL create a new session and SHALL NOT
persist or reuse session state across invocations.

#### Scenario: Independent invocations use independent sessions
- **WHEN** the single-turn command is run twice in succession
- **THEN** each run creates its own new session, with no shared history
  between them

