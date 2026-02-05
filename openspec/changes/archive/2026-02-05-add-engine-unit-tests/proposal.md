# Change: Add Unit Tests to Engine

## Why

The engine backend lacks unit tests, making it harder to refactor with confidence and catch regressions. Adding a test suite establishes quality assurance for the domain logic, persistence layer, and tools.

## What Changes

- Add pytest-based test infrastructure with fixtures for mocking ports
- Add unit tests for domain models (validation, serialization)
- Add unit tests for ChatService (business logic with mocked dependencies)
- Add unit tests for YamlPersistenceAdapter (file I/O with temp directories)
- Add API endpoint tests using FastAPI TestClient (valid and invalid inputs)

## Impact

- Affected specs: New `engine-testing` capability
- Affected code: New `tests/` directory at repository root
