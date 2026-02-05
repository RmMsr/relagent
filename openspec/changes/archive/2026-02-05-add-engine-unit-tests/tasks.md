## 1. Test Infrastructure

- [x] 1.1 Create `tests/` directory structure
- [x] 1.2 Create `tests/conftest.py` with shared fixtures (mock ports, sample data)
- [x] 1.3 Verify pytest runs with `uv run pytest`

## 2. Domain Model Tests

- [x] 2.1 Create `tests/domain/test_models.py`
- [x] 2.2 Test model instantiation with defaults
- [x] 2.3 Test model validation and serialization

## 3. Service Layer Tests

- [x] 3.1 Create `tests/domain/test_services.py`
- [x] 3.2 Test `ensure_session` (new session, existing session, not found)
- [x] 3.3 Test `ensure_context` (existing context, not found)
- [x] 3.4 Test `perform_user_input` with mocked ports
- [x] 3.5 Test `ensure_session_title` generation

## 4. Persistence Adapter Tests

- [x] 4.1 Create `tests/adapters/test_yaml_persistence.py`
- [x] 4.2 Test `save_session` / `load_session` round-trip
- [x] 4.3 Test `save_context` / `load_context` round-trip
- [x] 4.4 Test error handling (file not found, invalid YAML, session mismatch)

## 5. API Endpoint Tests

- [x] 5.1 Create `tests/test_api.py`
- [x] 5.2 Test `POST /messages` with valid ChatRequest body
- [x] 5.3 Test `POST /messages` with plain string body
- [x] 5.4 Test `POST /messages` with invalid/malformed body (422 validation error)
- [x] 5.5 Test `GET /messages/{session_id}` with valid session
- [x] 5.6 Test `GET /messages/{session_id}` with invalid UUID format (422 error)
- [x] 5.7 Test `GET /messages/{session_id}` with non-existent session (404 error)
