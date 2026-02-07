## ADDED Requirements

### Requirement: Chat Backend Selection
The system SHALL allow users to select between two chat backend types:
- **OpenAI-compatible**: Any server implementing the OpenAI chat completions API
- **Relagent Engine**: The full-featured Relagent backend with persistence and agentic capabilities

The selected backend type MUST be persisted and restored on app restart.
Both backend URLs MUST be stored independently so users can switch without losing configuration.
The router MUST display the appropriate chat page based on the selected backend.

#### Scenario: User selects OpenAI-compatible backend
- **GIVEN** the user is on the settings page
- **WHEN** the user selects "OpenAI-compatible" backend option
- **THEN** the selection is persisted
- **AND** navigating to the chat shows the simple chat page

#### Scenario: User selects Relagent Engine backend
- **GIVEN** the user is on the settings page
- **WHEN** the user selects "Relagent Engine" backend option
- **THEN** the selection is persisted
- **AND** navigating to the chat shows the agentic chat page

#### Scenario: User switches between backends
- **GIVEN** the user has configured both backend URLs
- **WHEN** the user switches from one backend type to another
- **THEN** the previous backend's configuration is preserved
- **AND** the chat page changes to match the selected backend
