# engine-testing Specification

## Purpose
TBD - created by archiving change add-engine-unit-tests. Update Purpose after archive.
## Requirements
### Requirement: Test Directory Structure

The engine SHALL have a `tests/` directory at the repository root with subdirectories mirroring the engine module structure.

#### Scenario: Standard test layout

- **GIVEN** the repository structure
- **WHEN** tests are organized
- **THEN** tests reside in `tests/domain/` for domain logic, `tests/adapters/` for adapters, and `tests/` root for cross-cutting tests

### Requirement: Shared Test Fixtures

The test suite SHALL provide shared fixtures in `tests/conftest.py` for mocking ports and creating sample data.

#### Scenario: Mock persistence port available

- **GIVEN** a test file imports pytest fixtures
- **WHEN** the test requests `mock_persistence` fixture
- **THEN** a mock implementation of the `Persistence` port is provided

#### Scenario: Mock agent execution port available

- **GIVEN** a test file imports pytest fixtures
- **WHEN** the test requests `mock_agent_execution` fixture
- **THEN** a mock implementation of the `AgentExecution` port is provided

#### Scenario: Sample data factories available

- **GIVEN** a test file imports pytest fixtures
- **WHEN** the test requests `sample_session` or `sample_context` fixtures
- **THEN** pre-built test data objects are provided

### Requirement: Domain Model Tests

The test suite SHALL verify domain model behavior including defaults, validation, and serialization.

#### Scenario: Model defaults applied

- **WHEN** a `SessionInfo` is instantiated without arguments
- **THEN** `session_id` is a valid UUID and `created_at`/`updated_at` are set to current time

#### Scenario: ChatMessage discrimination

- **WHEN** messages are serialized and deserialized
- **THEN** `UserMessage` and `AssistantMessage` are correctly distinguished by role

### Requirement: Service Layer Tests

The test suite SHALL verify ChatService business logic using mocked dependencies.

#### Scenario: New session created when none provided

- **GIVEN** a ChatService with mocked ports
- **WHEN** `ensure_session` is called with `session_id=None`
- **THEN** a new `SessionInfo` is returned

#### Scenario: Existing session loaded

- **GIVEN** a ChatService with mocked ports returning an existing session
- **WHEN** `ensure_session` is called with a valid session_id
- **THEN** the existing session is returned from persistence

#### Scenario: Session title generated on first message

- **GIVEN** a session without a title and a context with at least one message
- **WHEN** `ensure_session_title` is called
- **THEN** the agent execution port is invoked to generate a title

### Requirement: Persistence Adapter Tests

The test suite SHALL verify YamlPersistenceAdapter file operations using temporary directories.

#### Scenario: Session round-trip persistence

- **GIVEN** a `YamlPersistenceAdapter` with a temporary directory
- **WHEN** a `SessionInfo` is saved and then loaded
- **THEN** the loaded session matches the saved session

#### Scenario: Context round-trip persistence

- **GIVEN** a `YamlPersistenceAdapter` with a temporary directory
- **WHEN** a `ChatContext` with messages is saved and then loaded
- **THEN** the loaded context contains all original messages

#### Scenario: Session not found error

- **GIVEN** a `YamlPersistenceAdapter` with an empty directory
- **WHEN** `load_session` is called with a non-existent session_id
- **THEN** `SessionNotFound` exception is raised

### Requirement: API Endpoint Tests

The test suite SHALL verify FastAPI endpoints using TestClient with mocked service dependencies.

#### Scenario: POST /messages with valid ChatRequest

- **GIVEN** a TestClient with mocked ChatService
- **WHEN** `POST /messages` is called with a valid `ChatRequest` JSON body
- **THEN** response status is 200 and body contains `session_id` and `message`

#### Scenario: POST /messages with plain string

- **GIVEN** a TestClient with mocked ChatService
- **WHEN** `POST /messages` is called with a plain string body
- **THEN** response status is 200 and body is a plain string response

#### Scenario: POST /messages with invalid body

- **GIVEN** a TestClient
- **WHEN** `POST /messages` is called with malformed JSON or missing required fields
- **THEN** response status is 422 (Validation Error)

#### Scenario: GET /messages with valid session

- **GIVEN** a TestClient with mocked ChatService returning messages
- **WHEN** `GET /messages/{session_id}` is called with a valid UUID
- **THEN** response status is 200 and body contains `session_id` and `messages` list

#### Scenario: GET /messages with invalid UUID format

- **GIVEN** a TestClient
- **WHEN** `GET /messages/{session_id}` is called with an invalid UUID string
- **THEN** response status is 422 (Validation Error)

#### Scenario: GET /messages with non-existent session

- **GIVEN** a TestClient with mocked ChatService raising ChatContextNotFound
- **WHEN** `GET /messages/{session_id}` is called with a non-existent session UUID
- **THEN** response status is 404 (Not Found)

