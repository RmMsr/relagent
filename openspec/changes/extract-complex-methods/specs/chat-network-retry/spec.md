## MODIFIED Requirements

### Requirement: Error Handling and Retry Logic

The error handling and retry system SHALL use small, focused methods for better readability and maintainability.

#### Scenario: Error Classification

- **WHEN** errors occur during message sending
- **THEN** dedicated error classification methods determine retry eligibility
- **AND** main error handling focuses on state management

#### Scenario: Retry Scheduling

- **WHEN** retries need to be scheduled
- **THEN** dedicated scheduling methods handle timing and backoff
- **AND** complex timing logic is isolated from business logic

#### Scenario: Backoff Calculation

- **WHEN** retry delays need to be calculated
- **THEN** utility functions handle exponential backoff logic
- **AND** calculations are testable and reusable