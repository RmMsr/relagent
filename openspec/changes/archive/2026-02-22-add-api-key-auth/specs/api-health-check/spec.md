## MODIFIED Requirements

### Requirement: Health Check Request Construction

The system SHALL make health check requests that validate authentication without consuming excessive API resources. Health checks SHALL use a backend-appropriate endpoint that requires authentication, so that credential validity is confirmed.

#### Scenario: Engine health check uses /api/v1/status
- **GIVEN** a health check is initiated for the Relagent Engine backend
- **WHEN** the request is constructed
- **THEN** the request SHALL be a GET to `/api/v1/status` on the engine base URL
- **AND** the request SHALL include all configured authentication headers (Basic Auth and/or `X-API-Key`)

#### Scenario: Simple chat health check uses /chat/completions
- **GIVEN** a health check is initiated for the OpenAI-compatible backend
- **WHEN** the request is constructed
- **THEN** the request SHALL use the `/chat/completions` endpoint
- **AND** the request SHALL include a minimal message payload (e.g., single "ping" message)
- **AND** the request SHALL include all configured authentication headers (Basic Auth and/or `Authorization: Bearer`)

#### Scenario: Include Basic Auth in engine health check
- **GIVEN** Basic Auth credentials are configured for the engine
- **WHEN** an engine health check request is made
- **THEN** the request SHALL include the `Authorization: Basic …` header
- **AND** the health check SHALL validate both connectivity and authentication

#### Scenario: Include API key in engine health check
- **GIVEN** an API key is stored for the current engine URL
- **WHEN** an engine health check request is made
- **THEN** the request SHALL include the `X-API-Key: <key>` header

#### Scenario: Include API key in simple chat health check
- **GIVEN** an API key is stored for the current simple chat URL
- **WHEN** a simple chat health check request is made
- **THEN** the request SHALL include the `Authorization: Bearer <key>` header

#### Scenario: Follow redirects during health check
- **GIVEN** a health check is initiated
- **WHEN** the API responds with HTTP 302 redirect
- **THEN** the health check SHALL follow the redirect
- **AND** the response SHALL be analyzed for authentication requirements (see auth-detection spec)
