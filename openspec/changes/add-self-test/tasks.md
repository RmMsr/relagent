## 1. Engine: Status Version Field

- [x] 1.1 Add `version` field to the `/api/v1/status` response model in `engine/run.py`, populated from `importlib.metadata.version("relagent")`
- [x] 1.2 Verify the field appears in `GET /api/v1/status` response JSON

## 2. Engine: Self-Test Module

- [x] 2.1 Create `engine/self_test.py` with `SelfTestStatus` enum (ok/warning/error) and `SelfTestResult` dataclass (name, status, detail)
- [x] 2.2 Implement `test_llm_response_time()`: run two minimal agent calls (no tools), discard first timing, evaluate second ≤ 1s; include both times in detail
- [x] 2.3 Implement `test_llm_tool_calling()`: run agent call that requires the `current_timestamp` tool; verify tool was invoked; report ok or error
- [x] 2.4 Implement `test_data_persistence()`: create session with ID `selftest-<timestamp>` via `YamlPersistenceAdapter`, then delete it; report ok or error with stray ID on failure
- [x] 2.5 Implement `run_all_tests()`: call all three tests sequentially, collect results; a failure in one test does not stop subsequent tests

## 3. Engine: Self-Test Endpoint

- [x] 3.1 Add `GET /api/v1/self-test` route to `engine/run.py` with the same authentication as `/api/v1/status`
- [x] 3.2 Wire the route to `run_all_tests()` from `engine/self_test.py`, returning the list of `SelfTestResult` as JSON
- [x] 3.3 Update `engine/openapi-schema.json` (run `engine/bin/generate_schema.py`)

## 4. Flutter: Self-Test Model and Service

- [x] 4.1 Create `lib/models/self_test_result.dart` with `SelfTestStatus` enum (pending/running/ok/warning/error) and `SelfTestResult` class (id, label, status, detail)
- [x] 4.2 Add `fetchHealth()` method to the engine service: GET `/health`, return ok if HTTP 200 and body status is "ok"
- [x] 4.3 Add `fetchStatus()` method: GET `/api/v1/status` with auth headers, return the parsed JSON response including `version`
- [x] 4.4 Add `fetchSelfTests()` method: GET `/api/v1/self-test` with auth headers and 60s timeout, return list of engine test results

## 5. Flutter: Self-Test Provider

- [x] 5.1 Create `lib/providers/self_test_provider.dart` with `SelfTestState` (list of `SelfTestResult`, isRunning bool) and `SelfTestNotifier` using `NotifierProvider`
- [x] 5.2 Implement `runSelfTests()`: reset all results to pending, then run each test sequentially, updating state after each
- [x] 5.3 Implement engine-reachable test: call `fetchHealth()`; on failure set status to error and mark remaining app-side tests as skipped
- [x] 5.4 Implement engine-auth test: call `fetchStatus()`; retain response for version check; on 401/403 mark remaining app-side tests as skipped
- [x] 5.5 Implement version-match test: compare app major.minor (via `PackageInfo`) against engine version from status response; ok / warning / error per spec
- [x] 5.6 Implement engine self-tests step: set placeholder to running, call `fetchSelfTests()`, replace placeholder with individual engine results

## 6. Flutter: About Page

- [x] 6.1 Create `lib/pages/about_page.dart` displaying app name and version string at the top
- [x] 6.2 Implement test list widget: for each `SelfTestResult` show a status icon (pending/spinner/check/warn/error), label, and optional detail text
- [x] 6.3 Add "Run self-test" button: disabled while `isRunning` is true; calls `ref.read(selfTestProvider.notifier).runSelfTests()` on tap

## 7. Flutter: Navigation

- [x] 7.1 Add `/about` route to `lib/router/app_router.dart` pointing to `AboutPage`
- [x] 7.2 Add an about menu item to the chat page app bar that navigates to `/about`

## 8. Quality

- [x] 8.1 Run `dart-flutter_analyze_files` and fix all warnings and errors
- [x] 8.2 Run `dart-flutter_dart_format` on all changed Dart files
- [x] 8.3 Run `uv run ruff check engine/` and fix any issues in changed Python files
- [x] 8.4 Run `uv run pyright engine/` and fix any type errors in changed Python files
