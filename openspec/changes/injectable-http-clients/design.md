## Context

The Flutter app's outbound HTTP today is a mix of patterns:

- **Top-level functions calling the global `http` namespace** (no client to swap). Audit:
  - `apps/lib/agentic/services.dart` — 10 call sites (`http.post`, `http.get`, `http.delete`).
  - `apps/lib/agentic/health_check.dart`.
  - `apps/lib/agentic/self_test_service.dart`.
  - `apps/lib/chat/services.dart`.
- **One class with a half-injected client** — `apps/lib/services/api_health_check.dart` (`ApiHealthCheckService`). The constructor accepts `http.Client? httpClient`, but the body branches: `if (_httpClient != null) ... else http.post(...)`. The fallback path remains untestable.

Tests have evolved around this. `apps/test/services/api_health_check_test.dart` uses two patterns side-by-side:
- Some tests instantiate `ApiHealthCheckService(httpClient: mockClient)` and drive the production method directly (good).
- Others call `_performHealthCheckWithMockClient(service, mockClient, ...)` — a helper that **re-implements** the production HTTP call. It was added to test the global-http branch, and never retired.

The `chat-strict-ordering-and-settlement` change ran into this when writing tasks 13.2 and 13.4: there is no harness for HTTP-roundtrip tests against `apps/lib/agentic/services.dart`. 13.4 was downgraded to a parser-only unit test; 13.2 was deferred entirely. This change removes the blocker.

## Goals / Non-Goals

**Goals:**
- Every outbound HTTP call in `apps/lib/**` SHALL be testable by injecting an `http.Client`.
- Production behavior unchanged when no client is injected (lazily create a fresh `http.Client()` per call, matching current global-namespace semantics).
- Delete the `_performHealthCheckWithMockClient` workaround and the `if (_httpClient != null)` fallback branch.
- Land the deferred `chat-strict-ordering-and-settlement` HTTP-roundtrip tests (Stop e2e, 409 from `/messages`/`/continue`) against the new harness.
- Encode the convention in a new `apps-testing` capability spec.

**Non-Goals:**
- Introducing a global `EngineApiClient` class with shared state (sessions, retries, auth interceptors). That is a separate, larger change.
- Migrating to a different HTTP library (`dio`, `chopper`, etc.).
- Adding connection pooling, retry middleware, or request logging globally.
- Touching engine-side Python code.

## Decisions

### D1. Function-level `http.Client?` parameter, not a class wrapper

Every API function (currently top-level in `services.dart`, `health_check.dart`, etc.) gains an optional `http.Client? client` parameter at the **end of the named-parameter list**. Internally:

```dart
Future<X> sendMessage({
  required String baseUrl,
  // ... existing params ...
  http.Client? client,
}) async {
  final c = client ?? http.Client();
  try {
    final response = await c.post(uri, headers: headers, body: body);
    // ... existing logic ...
  } catch (e) {
    // ... existing logic ...
  }
}
```

**Rationale.** Three alternatives were considered:

| Option | Pros | Cons |
|---|---|---|
| **(A) Optional parameter on each function** *(chosen)* | Smallest patch. No call-site changes. Backward-compatible. Matches the partial pattern already in `ApiHealthCheckService`. | Each function repeats the `?? http.Client()` line. |
| (B) Wrap functions in a class (`EngineApiClient`) holding a single `http.Client` | More OO-idiomatic. Single place to add interceptors later. | Every caller (providers, widgets) updates to construct/inject the class. Large-touch refactor. |
| (C) Module-level `late http.Client _client` with a setter | One-line patch. | Global mutable state. Test isolation breaks. Hostile to parallel tests. |

Option (A) wins on cost/value. Option (B) is a fine future evolution if/when shared cross-cutting concerns appear (auth interceptors, retry middleware) — at that point the function bodies can delegate to a class and the same optional parameter becomes the class instance. The migration path remains open.

### D2. Lifecycle: caller owns the client; production never closes

When a caller injects `client`, the caller is responsible for `client.close()`. Production never injects, so the implicit `http.Client()` from `c = client ?? http.Client()` is **not** closed. This matches the current global `http.post(...)` behavior (which lazily creates an internal client and never closes it explicitly either).

A more conservative alternative is to wrap each call in `try { ... } finally { if (client == null) c.close(); }`. Rejected: it changes behavior subtly (one `Client` per call, with explicit teardown) and adds noise. The current behavior is already to leak the global client for the process lifetime; we preserve it.

Tests that pass a `MockClient` are short-lived (per-test) and do not need `.close()` (MockClient holds no resources).

### D3. Remove the `_httpClient != null` branch in `ApiHealthCheckService`

The class becomes:

```dart
class ApiHealthCheckService {
  final http.Client? _httpClient;
  ApiHealthCheckService({http.Client? httpClient}) : _httpClient = httpClient;
  // ...
  Future<HealthCheckResult> performHealthCheck({...}) async {
    final client = _httpClient ?? http.Client();
    final response = await client.post(uri, ...);
    // ...
  }
}
```

The dual-path branch (`if (_httpClient != null) ... else http.post(...)`) goes away. Behavior is preserved in both the injected and the implicit case.

### D4. Test convention — direct injection, no helpers that re-implement

Update `apps-testing` spec to forbid test helpers that re-construct the production HTTP call. The convention:

- Tests construct a `MockClient` and pass it via the constructor (class case) or function parameter (free-function case).
- Tests assert against the production code path. No re-implementation.

`_performHealthCheckWithMockClient` is deleted from `api_health_check_test.dart`. Existing tests using it are rewritten to use `ApiHealthCheckService(httpClient: mockClient)`.

### D5. Audit scope — 4 files, not 2

The proposal listed `services.dart` and `api_health_check.dart`. The audit during design surfaced two more:
- `apps/lib/agentic/health_check.dart`
- `apps/lib/agentic/self_test_service.dart`
- `apps/lib/chat/services.dart`

All four files are in scope; tasks list each individually. No grep-and-rename pass in `apps/lib/providers/**` or widgets — those callers don't construct HTTP requests directly.

### D6. Test additions land here, not in chat-strict-ordering

The two HTTP-roundtrip tests deferred from `chat-strict-ordering-and-settlement` (Stop e2e, 409 conflict from `/messages`/`/continue`) are added in this change, alongside the harness they need. This avoids a circular dependency on test infrastructure. The archived `chat-strict-ordering-and-settlement` change records the handoff in its task notes.

## Risks / Trade-offs

- **[Risk] Inconsistency: free functions vs. class.** `services.dart` exposes free functions; `ApiHealthCheckService` is a class. Different call shapes for similar behavior. → **Mitigation:** documented as deliberate in D1; future consolidation behind a class remains an option without breaking the optional-parameter contract.
- **[Risk] Implicit `http.Client()` leakage.** Each call creates and abandons a Client instance. → **Mitigation:** matches current `http.post(...)` semantics; not a regression. Connection-pool reuse is a future concern that the class-wrapper option (B) would address.
- **[Risk] Forgotten call site.** Manual audit can miss a file. → **Mitigation:** add a `dart_code_metrics` rule or a CI grep that flags top-level `http.post|get|put|delete` outside of test files. Out of scope for this change but called out in tasks as a follow-up consideration.
- **[Trade-off] No shared client across calls.** Each call constructs its own `http.Client()`. Cost is connection-setup overhead. Acceptable for a chat client (low call rate, latency dominated by the LLM).

## Migration Plan

This is a Flutter-app-only refactor with no engine coupling. Single-step rollout:

1. Land `services.dart`, `health_check.dart`, `self_test_service.dart`, `chat/services.dart`, `api_health_check.dart` refactors together. (Each function/method gains the optional client parameter; `_performHealthCheckWithMockClient` and the `_httpClient != null` branch removed.)
2. Rewrite `apps/test/services/api_health_check_test.dart` to drop the helper.
3. Add new HTTP-roundtrip tests in `apps/test/agentic/services_test.dart` (Stop e2e, 409 conflict).
4. Verify `fvm flutter test` passes the entire suite.
5. No data migration. No release-note user impact.

**Rollback:** revert the commit. No persistent state, no API surface change for end users.

## Open Questions

- **OQ1.** Should the optional parameter be named `client` or `httpClient`? `ApiHealthCheckService` uses `httpClient`; free functions in the new code default to `client` for brevity. Resolution candidate: standardize on `httpClient` for clarity (matches the existing pattern). Decide before tasks land.
- **OQ2.** Add a CI check that forbids new uses of global `http.post|get|put|delete` outside test files? Likely yes, but out of scope for this change; track separately.
