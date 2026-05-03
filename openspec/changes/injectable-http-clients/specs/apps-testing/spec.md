## ADDED Requirements

### Requirement: HTTP-Client Injection in App Service Modules

App service modules in `apps/lib/**` that perform outbound HTTP requests SHALL accept an injectable `http.Client` so that tests can intercept the wire-level call without re-implementing the production code path.

The injection point depends on the module shape:

- **Top-level functions** SHALL expose the client as an optional named parameter at the end of the parameter list (e.g. `http.Client? httpClient`).
- **Class-based services** SHALL expose the client as an optional constructor parameter and store it as a private field.

A function or method SHALL NOT branch on whether the client was injected; it SHALL resolve a single client (`final c = injected ?? http.Client();`) and use that one for the request.

#### Scenario: Free function accepts an optional client parameter

- **WHEN** a top-level API function in `apps/lib/agentic/services.dart` is invoked from a test
- **AND** the test passes a `MockClient` via the `httpClient:` named parameter
- **THEN** the function SHALL use the injected client for the HTTP call
- **AND** the test SHALL be able to assert on both the outbound request and the production-path response handling

#### Scenario: Class-based service accepts an injected client via constructor

- **WHEN** a test instantiates `ApiHealthCheckService(httpClient: mockClient)`
- **AND** invokes a method that performs an HTTP call
- **THEN** the method SHALL use the injected client
- **AND** SHALL NOT contain a fallback branch that re-targets the global `http` namespace

#### Scenario: No injection falls back to a fresh client

- **WHEN** a function or method is invoked in production with no client argument
- **THEN** the implementation SHALL construct a fresh `http.Client()` for that call
- **AND** the resulting behavior SHALL be observationally equivalent to the previous direct `http.post(...)` / `http.get(...)` invocation

### Requirement: Production-Path Test Convention

Tests for app service modules SHALL drive the production function or method directly with a `MockClient` from `package:http/testing.dart`. Tests SHALL NOT define helper functions that re-construct or re-implement the production HTTP request in order to enable mocking.

This convention exists because re-implementation helpers can drift from production code, and a passing test that exercises a re-implementation does not prove the production path works.

#### Scenario: Test asserts on the production code path

- **WHEN** a test exercises an app service module
- **THEN** the test SHALL invoke the same public function or method that production callers invoke
- **AND** SHALL pass a `MockClient` via the documented injection point

#### Scenario: Re-implementation helpers are removed

- **WHEN** an app-side test file is reviewed or added
- **THEN** it SHALL NOT contain a helper function that builds the request URI, headers, or body in order to send it through a `MockClient` directly
- **AND** any pre-existing helper of that shape SHALL be removed when the surrounding service module is migrated to support injection

### Requirement: Outbound HTTP Calls Go Through the Injection Point

App service modules SHALL NOT call `http.post`, `http.get`, `http.put`, or `http.delete` from `package:http/http.dart` against the global `http` namespace. All outbound HTTP SHALL be routed through the resolved client (injected or freshly constructed inside the function).

This requirement applies to non-test code under `apps/lib/**`. It does not constrain test code, generated code, or platform plugin internals.

#### Scenario: New service module is reviewed

- **WHEN** a new module under `apps/lib/**` makes an outbound HTTP call
- **THEN** the module SHALL accept an injectable client per the previous requirement
- **AND** the call SHALL go through the resolved client variable, not through the `http` namespace directly
