## Purpose

Let users view and set the CLI's engine connection settings through an
interactive wizard, and resolve those settings consistently across every
CLI command.

## ADDED Requirements

### Requirement: Configuration Resolution Precedence
The engine URL and auth token SHALL each be resolved in the following
order: an explicit command-line flag, then an environment variable, then a
persisted value, then a default.

#### Scenario: Flag overrides everything else
- **WHEN** a connection flag is given on the command line
- **THEN** that value is used regardless of any environment variable or
  persisted value

#### Scenario: Environment variable overrides persisted value
- **WHEN** no connection flag is given but a corresponding environment
  variable is set
- **THEN** the environment variable's value is used regardless of any
  persisted value

#### Scenario: Persisted value used when no flag or env var is set
- **WHEN** neither a flag nor an environment variable is given for a
  setting
- **THEN** the persisted value for that setting is used if one exists

### Requirement: Engine URL Persistence
The engine URL SHALL be persisted in a local, human-readable settings file
so it does not need to be supplied on every invocation.

#### Scenario: Persisted URL used on later commands
- **WHEN** the engine URL has been set via the config wizard
- **THEN** subsequent CLI commands use that URL without requiring a flag
  or environment variable

### Requirement: Auth Token Secure Storage
The auth token SHALL be stored using OS-level secure storage rather than
in plain text, and its absence or the unavailability of that secure
storage SHALL be treated as "no token configured" rather than as a fatal
error.

#### Scenario: Stored token used on later commands
- **WHEN** an auth token has been set via the config wizard
- **THEN** subsequent CLI commands retrieve it from secure storage without
  requiring a flag or environment variable

#### Scenario: Secure storage unavailable
- **WHEN** the OS-level secure storage cannot be reached
- **THEN** the CLI proceeds as if no token were configured rather than
  failing to start

### Requirement: Wizard Preserves Current Value on Blank Input
Each question the config wizard asks SHALL leave the corresponding setting
unchanged when the user submits a blank answer.

#### Scenario: Blank engine URL answer keeps the existing URL
- **WHEN** the user submits a blank answer to the engine URL question
- **THEN** the persisted engine URL is left unchanged

#### Scenario: Blank token answer keeps the existing token
- **WHEN** the user submits a blank answer to the auth token question
- **THEN** the stored auth token is left unchanged

### Requirement: Wizard Never Displays a Stored Token
The config wizard SHALL NOT display or re-print a previously stored token
value; it SHALL only indicate whether a token is currently set.

#### Scenario: Wizard shows token status, not its value
- **WHEN** the wizard runs and a token is already stored
- **THEN** the wizard indicates that a token is set
- **AND** does not print the token's value anywhere

### Requirement: Connection Test After Configuration
After the wizard finishes asking its questions, the CLI SHALL attempt a
connection to the engine using the resulting configuration and report
success or failure to the user.

#### Scenario: Successful connection is reported
- **WHEN** the wizard's configured engine URL and token are valid and the
  engine is reachable
- **THEN** the wizard reports that the connection succeeded

#### Scenario: Failed connection is reported without discarding input
- **WHEN** the wizard's configured engine URL or token is invalid or the
  engine is unreachable
- **THEN** the wizard reports the failure and its reason
- **AND** the values entered during the wizard remain saved
