## Why

The Flutter app's API service modules call HTTP via the global `http` namespace (e.g., `http.post(uri, ...)` at 10 sites in `apps/lib/agentic/services.dart` and similar in `apps/lib/services/api_health_check.dart`). Tests cannot intercept these calls with `package:http/testing.dart`'s `MockClient` because there is no `http.Client` instance to swap in. Two consequences are already biting us:

- `apps/test/services/api_health_check_test.dart` ships a `_performHealthCheckWithMockClient` helper that **re-implements** the production HTTP call against a `MockClient`. The helper and the production code can drift; the test no longer proves the production path works.
- The `chat-strict-ordering-and-settlement` change had to defer task **13.2** (Stop end-to-end integration test) and downgrade task **13.4** (409 Conflict integration) to a parser-only unit test. Closing both required a harness that does not exist.

This change introduces that harness so testability stops being a one-off workaround and becomes the default.

## What Changes

- **Refactor `apps/lib/agentic/services.dart`** — every top-level API function gains an optional `http.Client? client` parameter. Internally each function uses `client ?? http.Client()`. No call-site needs to change; tests pass a `MockClient` when they want to intercept.
- **Refactor `apps/lib/services/api_health_check.dart`** — apply the same pattern. Delete `_performHealthCheckWithMockClient` from the test; rewrite the existing tests to drive the production `performHealthCheck` directly with an injected `MockClient`.
- **Establish a convention** — record in a new `apps-testing` capability spec that all app service modules SHALL accept an injectable `http.Client`, and that test files SHALL NOT re-implement production HTTP flows in helpers.
- **Land the deferred chat-strict-ordering tests** as part of this change (since the harness is the blocker):
  - HTTP-roundtrip test for `stopSession` settling the cycle (closes 13.2).
  - HTTP-roundtrip test for 409 Conflict from `sendMessage` / `continueSession` producing typed `SessionInFlightException` end-to-end (closes the gap behind the current parser-only 13.4 test).

No end-user behavior changes. No public API signature changes for callers that omit the new optional parameter.

## Capabilities

### New Capabilities
- `apps-testing`: Test-infrastructure conventions for the Flutter app (parallel to the existing `engine-testing` capability). Initial scope: HTTP-client injection requirement and the prohibition on re-implementing production HTTP flows in test helpers.

### Modified Capabilities
None. This change is implementation-only with respect to existing capabilities — `agentic-chat`, `api-health-check`, `chat-network-retry`, and `session-continuation` keep all their requirements unchanged. Their test coverage tightens, but their behavior contracts do not move.

## Impact

- **Code touched**: `apps/lib/agentic/services.dart`, `apps/lib/services/api_health_check.dart`. Any other `apps/lib/**/*.dart` that uses the global `http` namespace for outbound calls (audit during design phase).
- **Tests touched**: `apps/test/services/api_health_check_test.dart` (rewrite to use injectable client), `apps/test/agentic/services_test.dart` (extend with HTTP-roundtrip cases), plus new tests for `stopSession` and 409 paths.
- **Dependencies**: No new packages — `package:http/testing.dart` is already pulled in transitively via `package:http`.
- **Backwards compatibility**: Optional parameter; all existing callers continue to work unchanged.
- **Follow-up**: Once merged, mark `chat-strict-ordering-and-settlement` task 13.2 done and revisit the parser-only 13.4 to add the integration-level coverage that was deferred.
