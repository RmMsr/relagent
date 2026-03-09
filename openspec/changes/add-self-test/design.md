## Context

The app currently has no diagnostic tooling. Users who misconfigure the engine URL, authentication, or have a version mismatch get opaque errors. The app has two pages: `chat_page.dart` and `settings_page.dart`. The engine exposes `/health` and `/api/v1/status` but `/api/v1/status` does not yet return a version field.

## Goals / Non-Goals

**Goals:**
- Add an about page as a third app page with a self-test section
- Run 3 app-side tests sequentially with live status updates
- Proxy engine self-tests via `GET /api/v1/self-test` and display results
- Add version field to `/api/v1/status` response
- Add new `/api/v1/self-test` endpoint to the engine

**Non-Goals:**
- Automated or scheduled self-tests (manual trigger only)
- Streaming/incremental engine test results (too complex for v1)
- Testing non-engine backends (OpenAI-compatible only via the engine path)

## Decisions

### 1. New about page, not embedded in settings

An about page (`/about`, `lib/pages/about_page.dart`) is a natural home for version info and diagnostics. Embedding self-tests in the settings page would clutter it and conflate configuration with diagnostics. The about page is accessed via a menu item in the chat page app bar.

### 2. Self-test state managed by a dedicated Riverpod NotifierProvider

A `SelfTestProvider` holds a list of `SelfTestResult` objects (one per test). Each result carries: `id`, `label`, `status` (pending/running/ok/warning/error), and optional `detail` string. Tests are triggered by calling `runSelfTests()` on the notifier, which updates each result in place as tests complete. This fits the existing Riverpod pattern and gives the UI live updates.

### 3. App-side tests run sequentially; engine tests are a single blocking call

The three app-side tests are fast (HTTP round-trips) and depend on each other logically (no point testing auth if the engine is unreachable), so sequential is natural. The engine self-test is a single `GET /api/v1/self-test` call that blocks until all engine tests finish. The engine runs its tests internally in sequence. The app displays a single "Engine tests" item as `running` until the call returns, then expands the individual results.

**Alternative considered**: Server-Sent Events for streaming engine test results. Rejected — adds significant complexity to both engine and app for a diagnostic screen.

### 4. Engine self-test uses existing agent and persistence infrastructure

The engine self-test module calls the existing `pydantic_ai` agent with a minimal payload (no tool for response-time tests, with tool for tool-calling test) and existing `YamlPersistenceAdapter` for the persistence test. No new abstractions — just a thin test runner that reuses production code paths, which is the most representative diagnostic.

### 5. LLM response-time test runs twice; first result discarded

The first call may trigger model loading. The second call measures warm latency. Both results may be included in the response detail for transparency (e.g., `"first: 4.2s, second: 0.7s"`), but only the second is evaluated against the 1-second threshold.

### 6. Version comparison: major.minor only, mismatch is a warning

A patch-level difference (e.g., app `0.1.13` vs engine `0.1.12`) is acceptable. Only major.minor mismatch triggers a warning. An error state is not used here — the user can still proceed. The version is read from `pubspec.yaml` at build time via the `package_info_plus` package (already a common Flutter pattern) and compared against the `version` field added to `/api/v1/status`.

**Alternative considered**: Using the existing `/health` endpoint which already returns `version`. Rejected — `/health` is unauthenticated; using `/api/v1/status` for the version check means we get connectivity, auth, AND version from a single call (test 2 and 3 share the same HTTP response).

### 7. Persistence test uses a clearly-namespaced ephemeral session

The persistence test creates a session with ID `selftest-<timestamp>` and immediately deletes it. Using a namespaced ID avoids collision with real sessions and makes stray entries (if deletion fails) identifiable.

## Risks / Trade-offs

- **Engine self-test is slow** (two LLM calls + tool call can take 10–20s) → App sets a 60s timeout on the `/api/v1/self-test` call and shows a spinner with elapsed time
- **Persistence test leaves stray data if deletion fails** → Failure is reported as an error result; a future cleanup job could prune `selftest-*` sessions
- **LLM not configured / model not loaded** → Engine test returns `error` with message; app displays it verbatim
- **`package_info_plus` adds a dependency** → It's a well-maintained Flutter package widely used in the ecosystem; acceptable addition

### 8. Section header clarifies scope: "Engine Setup Check"

The self-test section header reads "Engine Setup Check" instead of "Self-Test" to make it immediately clear that these checks verify the engine connection and configuration, not the app itself. The button label is "Check engine setup".

### 9. Failed checks include actionable hints

Each failure detail includes a short user-facing hint suggesting what to try. Hints are appended after the technical detail, separated by a newline or " — ". This keeps the technical info for copy-paste while giving users a next step. Hints are defined in the provider (app-side failures) and engine module (engine-side failures).

## Open Questions

- Should the about page show additional info (build date, commit hash)? → Deferred; version string is sufficient for now
- Should the engine self-test endpoint require authentication? → Yes, same as `/api/v1/status` — consistent with other authenticated endpoints
