## Purpose

Automatically detect when a backend requires API key authentication by analyzing HTTP 401 responses, enabling the app to prompt users for credentials.

## Requirements

### Requirement: API Key Auth Detection

The system SHALL detect when an API requires an API key based on HTTP 401 responses with a JSON body and no `WWW-Authenticate` header.

#### Scenario: Detect missing API key from 401 JSON response
- **GIVEN** a request is made to an engine or OpenAI-compatible endpoint without an API key
- **WHEN** the API responds with HTTP 401 Unauthorized
- **AND** the response has `Content-Type: application/json`
- **AND** the response does NOT include a `WWW-Authenticate` header
- **THEN** the system SHALL identify the authentication type as API key required
- **AND** the settings SHALL be updated to prompt the user to enter an API key

#### Scenario: Distinguish API key auth from Basic Auth
- **GIVEN** a request returns HTTP 401
- **WHEN** the response includes a `WWW-Authenticate` header
- **THEN** the system SHALL NOT identify this as an API key requirement
- **AND** detection SHALL follow the existing Basic Auth detection path instead

#### Scenario: API key detection does not trigger on non-401 errors
- **GIVEN** a request returns HTTP 403
- **WHEN** the response has `Content-Type: application/json` and no `WWW-Authenticate` header
- **THEN** the system SHALL NOT interpret this as an API key detection signal
- **AND** the error SHALL be reported as a permission or access error

#### Scenario: Re-detect after API key change
- **GIVEN** a request with an incorrect API key returns HTTP 401 with JSON body
- **WHEN** the 401 is received
- **THEN** the system SHALL treat this as an authentication failure (not a new detection)
- **AND** the user SHALL be prompted to update the API key
