## Why

Users have no built-in way to verify their Relagent setup is working correctly end-to-end. A self-test feature on the about page gives immediate, structured feedback on connectivity, authentication, version compatibility, and engine health — reducing guesswork when configuration goes wrong.

## What Changes

- Add a self-test section to the **about page** in the Flutter app
- Each test displays a status badge: pending / in-progress / ok / warning / error
- Tests run sequentially when the user triggers the self-test
- **App-side tests** (run directly from the app):
  1. Engine reachable — `GET /health` returns HTTP 200 with `status: "ok"`
  2. Engine auth ok — `GET /api/v1/status` returns HTTP 200 with valid JSON
  3. Version match — major + minor version from `/api/v1/status` matches app version (mismatch is a warning, not error)
- **Engine-side tests** (proxied via `GET /api/v1/self-test`):
  1. LLM response time — minimal chat request run twice; ok if second response ≤ 1s (first run discarded to skip model load delay); response time shown in result
  2. LLM tool calling — simulated request requiring the `current_timestamp` tool to be invoked
  3. Data persistence — creates and deletes a session to verify storage works
- New `/api/v1/self-test` endpoint added to the engine
- `/api/v1/status` extended to include engine version in response

## Capabilities

### New Capabilities
- `app-self-test`: Self-test UI on the about page; app-side test runner for connectivity, auth, and version checks; displays engine self-test results
- `engine-self-test`: Engine `/api/v1/self-test` endpoint that runs LLM response time, tool calling, and data persistence tests and returns structured results

### Modified Capabilities
- `version-management`: `/api/v1/status` response must include a `version` field so the app can compare major.minor versions

## Impact

- **Flutter app**: New UI section on about page, new service methods for `/health`, `/api/v1/status`, `/api/v1/self-test`, new provider for self-test state
- **Engine API**: New `GET /api/v1/self-test` endpoint; `/api/v1/status` response schema extended with `version` field
- **Engine**: New self-test runner module with LLM and persistence test logic using existing agent and persistence infrastructure
