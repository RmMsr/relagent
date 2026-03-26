## ADDED Requirements

### Requirement: Self-Test Endpoint

The engine SHALL expose an authenticated `GET /api/v1/self-test` endpoint that runs all engine self-tests and returns structured results.

#### Scenario: Successful self-test run

- **WHEN** an authenticated GET request is made to `/api/v1/self-test`
- **THEN** the response is HTTP 200 with a JSON array of test result objects
- **AND** each result object contains `name` (string), `status` ("ok" | "warning" | "error"), and `detail` (string or null)

#### Scenario: Unauthenticated request rejected

- **WHEN** a GET request is made to `/api/v1/self-test` without valid credentials
- **THEN** the response is HTTP 401

#### Scenario: Tests run sequentially to completion

- **WHEN** the endpoint is called
- **THEN** all configured tests run before the response is returned
- **AND** a failure in one test does not prevent subsequent tests from running

### Requirement: LLM Response Time Test

The engine self-test SHALL measure LLM response latency using a minimal simulated chat request, run twice to discard the model warm-up delay.

#### Scenario: Fast second response

- **GIVEN** the LLM is loaded and responsive
- **WHEN** the response time test runs
- **THEN** two requests are made sequentially with a minimal one-message payload
- **AND** only the second request's latency is evaluated against the 1-second threshold
- **AND** the result detail includes both measured times (e.g., `"first: 4.2s, second: 0.7s"`)
- **AND** the result status is ok if the second response time is ≤ 1 second

#### Scenario: Slow second response

- **WHEN** the second LLM request takes more than 1 second
- **THEN** the result status is warning
- **AND** the result detail includes both times

#### Scenario: LLM request fails

- **WHEN** either LLM request raises an exception or returns an error
- **THEN** the result status is error
- **AND** the result detail contains the error message

### Requirement: LLM Tool Calling Test

The engine self-test SHALL verify tool calling by sending a simulated request that requires invoking the `current_timestamp` tool.

#### Scenario: Tool called successfully

- **GIVEN** the LLM supports tool calling
- **WHEN** the tool calling test sends a request that requires the current timestamp
- **THEN** the agent invokes the `current_timestamp` tool during processing
- **AND** the result status is ok

#### Scenario: Tool not called

- **WHEN** the LLM responds without invoking the `current_timestamp` tool
- **THEN** the result status is error with a message indicating no tool call was made

#### Scenario: Tool calling request fails

- **WHEN** the agent raises an exception processing the tool calling request
- **THEN** the result status is error with the exception message in detail

### Requirement: Data Persistence Test

The engine self-test SHALL verify the persistence layer by creating and deleting an ephemeral test session.

#### Scenario: Persistence round-trip succeeds

- **WHEN** the persistence test runs
- **THEN** a session with a namespaced ID (e.g., `selftest-<timestamp>`) is created via the persistence adapter
- **AND** the session is immediately deleted
- **AND** the result status is ok

#### Scenario: Session creation fails

- **WHEN** the persistence adapter raises an exception on session creation
- **THEN** the result status is error with the exception message in detail

#### Scenario: Session deletion fails

- **WHEN** session creation succeeds but deletion raises an exception
- **THEN** the result status is error with the exception message in detail
- **AND** the stray session ID is included in the detail for manual cleanup
