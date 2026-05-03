## 1. Conventions

- [ ] 1.1 Resolve OQ1 (parameter name): standardize on `httpClient` to match the existing `ApiHealthCheckService` constructor; record the decision inline in `design.md`
- [ ] 1.2 Add a one-paragraph note in `apps/test/README.md` (or create one if missing) summarizing the test convention from the `apps-testing` capability spec: "use injection, not re-implementation helpers"

## 2. Refactor `apps/lib/agentic/services.dart`

- [ ] 2.1 Add `http.Client? httpClient` as the last named parameter on every top-level API function in the file (10 call sites identified by audit: `http.post`, `http.get`, `http.delete`)
- [ ] 2.2 In each function body, resolve the client once: `final client = httpClient ?? http.Client();` and use `client` for the request
- [ ] 2.3 Verify call-site behavior is unchanged for callers that omit the parameter (existing providers/widgets compile and run)
- [ ] 2.4 Remove the leading underscore from `tryParseConflict` is already done in chat-strict-ordering; confirm no regression here

## 3. Refactor `apps/lib/agentic/health_check.dart`

- [ ] 3.1 Add `http.Client? httpClient` parameter to each public function that performs HTTP
- [ ] 3.2 Replace each global `http.<verb>(...)` call with the resolved client variable
- [ ] 3.3 Run the existing health-check tests; expect green with zero source-level changes in the tests

## 4. Refactor `apps/lib/agentic/self_test_service.dart`

- [ ] 4.1 Add `http.Client? httpClient` to the public entry points performing HTTP
- [ ] 4.2 Route every outbound HTTP call through the resolved client
- [ ] 4.3 Run existing self-test tests; expect green

## 5. Refactor `apps/lib/chat/services.dart`

- [ ] 5.1 Add `http.Client? httpClient` to each top-level function performing HTTP
- [ ] 5.2 Route every outbound HTTP call through the resolved client
- [ ] 5.3 Run existing chat-services tests; expect green

## 6. Refactor `apps/lib/services/api_health_check.dart`

- [ ] 6.1 Replace the `if (_httpClient != null) { ... } else { http.post(...) }` branch with a single resolved client: `final client = _httpClient ?? http.Client();`
- [ ] 6.2 Verify the cache-by-URL behavior is unchanged with no client injected
- [ ] 6.3 Verify the same with an injected `MockClient`

## 7. Test cleanup

- [ ] 7.1 Delete `_performHealthCheckWithMockClient` from `apps/test/services/api_health_check_test.dart`
- [ ] 7.2 Rewrite each test that used the helper to construct `ApiHealthCheckService(httpClient: mockClient)` and call `performHealthCheck` directly
- [ ] 7.3 Add a regression test asserting that `ApiHealthCheckService` with no injected client still performs a real HTTP attempt (sanity check on the fallback path; can use a closed-port URL and assert the connection-failed result)

## 8. New HTTP-roundtrip coverage (closes deferred chat-strict-ordering tasks)

- [ ] 8.1 In `apps/test/agentic/services_test.dart`, add a `MockClient` test for `stopSession`: assert it POSTs to `/api/v1/sessions/{id}/stop`, parses the `messages` array, returns `List<AgenticMessage>` with all entries `final=true` (closes the e2e-roundtrip slice of `chat-strict-ordering-and-settlement` task 13.2)
- [ ] 8.2 In the same file, add a `MockClient` test for `sendMessage` returning 409 with `{"detail": {"error": "session_in_flight", "session_id": ..., "trailing_sequence_id": ...}}` body, asserting the function throws `SessionInFlightException` with populated fields (closes the e2e slice of task 13.4)
- [ ] 8.3 Add the same coverage for `continueSession` with the same 409 body
- [ ] 8.4 Add a `MockClient` test asserting that `stopSession` against a session with no in-flight cycle (engine returns 409 with `no_in_flight_cycle`) throws `NoInFlightCycleException`

## 9. Convention enforcement

- [ ] 9.1 Grep `apps/lib/**/*.dart` for residual `http\.(post|get|put|delete)` against the global `http` namespace; expect zero matches
- [ ] 9.2 Decide on OQ2 (CI grep / lint rule against new global-http use): document the decision in `design.md`; if "yes", file a follow-up tracker; if "no", note the rationale

## 10. Verification & release

- [ ] 10.1 `fvm flutter analyze apps/lib apps/test` is clean
- [ ] 10.2 `fvm flutter test` is fully green
- [ ] 10.3 Run `openspec validate injectable-http-clients --strict` — expect "is valid"
- [ ] 10.4 No version bump needed (internal refactor); no CHANGELOG entry required (no end-user behavior change)
