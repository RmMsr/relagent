## ADDED Requirements

### Requirement: About Page

The app SHALL provide an about page accessible from the chat page app bar, displaying the app version and a self-test section.

#### Scenario: Navigate to about page

- **WHEN** the user taps the about menu item in the chat page app bar
- **THEN** the app navigates to `/about`
- **AND** the about page displays the current app version string

### Requirement: Self-Test Trigger

The about page SHALL provide a button to manually trigger the self-test sequence.

#### Scenario: Run self-test button

- **WHEN** the user taps "Run self-test"
- **THEN** all tests are reset to pending status
- **AND** the test sequence starts immediately
- **AND** the button is disabled while tests are running

#### Scenario: Re-run after completion

- **WHEN** all tests have completed and the user taps "Run self-test" again
- **THEN** all tests reset to pending and the sequence runs again from the start

### Requirement: Self-Test Status Display

The about page SHALL display each test as a list item with a label, a status indicator, and an optional detail string.

#### Scenario: Pending state before run

- **GIVEN** the self-test has not been triggered
- **WHEN** the about page is displayed
- **THEN** all test items show pending status with no detail text

#### Scenario: In-progress state during run

- **WHEN** a test is actively executing
- **THEN** that test item shows a running indicator
- **AND** tests not yet started remain in pending status

#### Scenario: Ok result

- **WHEN** a test completes successfully
- **THEN** the test item shows ok status
- **AND** any detail text (e.g., response time) is displayed beneath the label

#### Scenario: Warning result

- **WHEN** a test completes with a non-critical issue (e.g., minor version mismatch)
- **THEN** the test item shows warning status with a detail message

#### Scenario: Error result

- **WHEN** a test fails
- **THEN** the test item shows error status with a detail message describing the failure

### Requirement: App-Side Test — Engine Reachable

The self-test SHALL verify the engine is reachable by making a GET request to `/health`.

#### Scenario: Engine reachable

- **WHEN** the engine reachable test runs
- **AND** `GET /health` returns HTTP 200 with a body containing `status: "ok"`
- **THEN** the test result is ok

#### Scenario: Engine not reachable

- **WHEN** `GET /health` returns a non-200 status or fails to connect
- **THEN** the test result is error
- **AND** subsequent tests are skipped (marked error with "skipped" detail)

### Requirement: App-Side Test — Engine Auth

The self-test SHALL verify authentication by making a GET request to `/api/v1/status` with configured credentials.

#### Scenario: Auth ok

- **WHEN** `GET /api/v1/status` returns HTTP 200 with valid JSON
- **THEN** the test result is ok
- **AND** the response is retained for use in the version check test

#### Scenario: Auth failed

- **WHEN** `GET /api/v1/status` returns HTTP 401 or HTTP 403
- **THEN** the test result is error with a message indicating authentication failure
- **AND** the version check test is skipped

#### Scenario: Unexpected response

- **WHEN** `GET /api/v1/status` returns a non-200, non-401/403 status
- **THEN** the test result is error with the HTTP status code in the detail

### Requirement: App-Side Test — Version Match

The self-test SHALL verify the app and engine share the same major and minor version.

#### Scenario: Versions match

- **GIVEN** the status response contains a `version` field
- **WHEN** the app's major.minor matches the engine's major.minor
- **THEN** the test result is ok with both versions shown in the detail

#### Scenario: Minor version mismatch

- **WHEN** the app's major version matches but the minor version differs
- **THEN** the test result is warning with both versions shown in the detail

#### Scenario: Major version mismatch

- **WHEN** the app's major version differs from the engine's major version
- **THEN** the test result is error with both versions shown in the detail

#### Scenario: Version field missing

- **WHEN** the status response does not contain a `version` field
- **THEN** the test result is warning with a message indicating the engine version is unavailable

### Requirement: Engine Self-Tests Display

The self-test SHALL fetch engine self-test results from `GET /api/v1/self-test` and display each result as a separate test item.

#### Scenario: Engine tests shown as single running item during fetch

- **WHEN** the app-side tests have passed and the engine self-test request is in flight
- **THEN** a single "Engine tests" item is shown with running status

#### Scenario: Engine test results expanded after fetch

- **WHEN** `GET /api/v1/self-test` returns a response
- **THEN** the "Engine tests" placeholder is replaced with individual items for each engine test result
- **AND** each item shows the engine-reported status and detail

#### Scenario: Engine self-test request fails

- **WHEN** `GET /api/v1/self-test` returns a non-200 response or times out
- **THEN** the "Engine tests" item shows error status with the failure detail
