## ADDED Requirements

### Requirement: Surfaced Engine Errors Are Descriptive

When the engine reports an error to a client, the response SHALL carry a
human-readable description of what went wrong. An error that is surfaced to the
user SHALL NOT be represented by a status code alone.

The app SHALL display that description to the user rather than only the HTTP
status, so a misconfigured or not-yet-ready setup is distinguishable from a real
defect.

#### Scenario: Engine error response includes a reason

- **WHEN** the engine returns a handled error to a client
- **THEN** the response body SHALL include a machine-readable error discriminator
- **AND** SHALL include a human-readable reason describing the cause

#### Scenario: App shows the description, not just the code

- **GIVEN** an engine error response that carries a reason
- **WHEN** the app renders the error
- **THEN** it SHALL present a friendly headline describing the situation
- **AND** SHALL make the engine's reason available to the user as a detail
- **AND** SHALL NOT show only the bare HTTP status code

### Requirement: Inference Provider Unavailability Is Reported As Retryable

The engine SHALL detect when the configured inference provider cannot be
reached or is not ready yet — both a provider that is offline/unreachable and a
provider that is up but still warming up (for example, a bundled `llama.cpp`
still loading its model). It SHALL report this condition as a retryable `503`
response with a structured `provider_unavailable` discriminator and a
`Retry-After` hint.

A genuine client/configuration error from the provider (a `4xx`) SHALL NOT be
reported as provider unavailability.

#### Scenario: Unreachable provider becomes a retryable 503

- **GIVEN** the configured inference provider is offline or unreachable
- **WHEN** a chat request requires the provider
- **THEN** the engine SHALL respond with HTTP `503`
- **AND** the body SHALL identify the error as `provider_unavailable`
- **AND** the response SHALL include a `Retry-After` hint

#### Scenario: Warming-up provider becomes a retryable 503

- **GIVEN** the provider is reachable but returns a server error while loading its model
- **WHEN** a chat request requires the provider
- **THEN** the engine SHALL respond with HTTP `503` identified as `provider_unavailable`

#### Scenario: Client/config error is not masked as unavailability

- **GIVEN** the provider returns a `4xx` (for example, an unknown model)
- **WHEN** a chat request requires the provider
- **THEN** the engine SHALL NOT report it as `provider_unavailable`

### Requirement: Provider Unavailability Reason Is Actionable

The reason reported for provider unavailability SHALL name the configured
provider endpoint and SHALL surface the provider's own message, so the user can
tell a misconfigured or not-yet-started provider apart from an application
defect.

#### Scenario: Reason names the endpoint and underlying cause

- **WHEN** the engine reports `provider_unavailable`
- **THEN** the reason SHALL include the configured provider endpoint
- **AND** SHALL include the underlying connection or server message when available

### Requirement: Provider Unavailability Is Retryable In The App

The app SHALL present an inference-provider unavailability as a friendly,
retryable error in the conversation. Retrying SHALL re-issue the user's request
without losing it and without duplicating the user's message.

A retry SHALL NOT remove the previous error from the conversation history: the
error SHALL remain visible so the user can follow the sequence of events.

#### Scenario: Provider-unavailable error is retryable

- **GIVEN** a chat request fails because the provider is unavailable
- **WHEN** the app renders the failure
- **THEN** it SHALL present a retryable error message
- **AND** the message SHALL communicate that the provider is unreachable or still starting up

#### Scenario: Retry preserves the error and does not duplicate the user message

- **GIVEN** a failed request left the conversation as `[user message, error]`
- **WHEN** the user retries
- **THEN** the original error SHALL remain in the conversation history
- **AND** the user message SHALL appear only once
- **AND** a successful retry SHALL append the assistant response after the preserved error
