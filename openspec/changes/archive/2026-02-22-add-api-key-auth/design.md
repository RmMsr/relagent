## Context

The Relagent engine already enforces `X-API-Key` authentication on all `/api/v1/*` routes via the `require_api_key` FastAPI dependency in `engine/api/helpers.py`. The Flutter app, however, only knows how to construct and send HTTP Basic Auth headers (`Authorization: Basic …`) for either backend — it has no API key support at all. OpenAI-compatible providers (LM Studio, Ollama, hosted APIs) typically accept `Authorization: Bearer <key>` as their API key scheme.

The existing credential infrastructure is already solid: `SecureCredentialService` stores passwords per URL in `flutter_secure_storage`, and `CredentialsManager` wraps it with separate namespaces (`engine:<url>`). `AuthType.basic` / `AuthType.none` are the only values today; usernames live in SharedPreferences while passwords live in secure storage.

The `GET /api/v1/status` endpoint already exists and is protected by API key auth. It will serve as the connection test target.

The engine does not implement HTTP Basic Auth and will not — that is the responsibility of a reverse proxy (nginx, Caddy, etc.) configured by the user. The app must support both schemes as a client regardless of which layer enforces them.

## Goals / Non-Goals

**Goals:**
- Let users configure an API key for the engine (`X-API-Key`) and for the OpenAI-compatible backend (`Authorization: Bearer`) in the settings page
- Inject the appropriate header into every request when a key is stored for that backend
- Use `GET /api/v1/status` as the authenticated connection test for the engine
- Bind all credentials (password, API key) to their respective URL — changing the URL clears them
- Store API keys in `flutter_secure_storage`, never in SharedPreferences
- Detect which auth is missing from the 401 response signals (WWW-Authenticate → Basic, JSON body without WWW-Authenticate → API key)

**Non-Goals:**
- Automatic re-authentication flows or credential prompts mid-session
- Multiple simultaneous engine URLs with independent credentials

## Decisions

### 1. API key as independent credential field, not an `AuthType` variant

Both Basic Auth and API key can be active at the same time. Adding `apiKey` to the `AuthType` enum would force mutual exclusivity. Instead, keep `engineAuthType`/`authType` for Basic Auth and add new boolean indicators `engineHasApiKey` and `simpleChatHasApiKey` to `Settings` (persisted in SharedPreferences). The actual keys are stored in `SecureCredentialService` under namespaced keys (`engine_api_key_<url>`, `chat_api_key_<url>`).

**Alternative considered**: A bitmask or `Set<AuthType>` approach. Rejected for complexity and incompatibility with the existing `copyWith` pattern.

### 2. No engine changes for Basic Auth — proxy responsibility

Basic Auth is enforced by a reverse proxy (nginx, Caddy, etc.) placed in front of the engine by the user. The proxy returns HTTP 401 with `WWW-Authenticate: Basic` header when credentials are missing or wrong. The app treats this signal identically regardless of which layer produced it. The engine itself only changes in that `GET /api/v1/status` is used as the connection test (it already exists and is already protected by API key).

### 3. `GET /api/v1/status` as the engine connection test

This endpoint already exists, is already protected by API key (and will gain Basic Auth protection), and is cheap. No new endpoint needed. The app currently calls `GET /health` for engine connectivity; this will be replaced by `GET /api/v1/status` so authentication is actually validated.

### 4. Extend `_buildHeaders()` and `CredentialsManager` rather than a new abstraction

Each service's `_buildHeaders()` gains an `apiKey` parameter and injects the backend-appropriate header: `X-API-Key` in `agentic/services.dart`, `Authorization: Bearer` in `chat/services.dart`. `CredentialsManager` gains `storeEngineApiKey`/`getEngineApiKey`/`clearEngineApiKey` and `storeChatApiKey`/`getChatApiKey`/`clearChatApiKey` using the existing `SecureCredentialService` — a consistent pattern that avoids introducing new infrastructure.

**Alternative considered**: An `EngineCredentials` / `ChatCredentials` value object aggregating all credential types. Valuable long-term but an over-abstraction for two fields today.

### 5. URL change clears both Basic Auth password and API key

When `engineBaseUrl` changes the settings provider already clears the session and SSE state. It must also call `credentialsManager.clearEngineCredentials(oldUrl)` (password) and `credentialsManager.clearEngineApiKey(oldUrl)` for the old URL before saving the new one. Same pattern for `simpleChatBaseUrl`: `clearCredentials(oldUrl)` + `clearChatApiKey(oldUrl)`.

### 6. Detection logic for 401 responses

- 401 + `WWW-Authenticate` header present → Basic Auth required
- 401 + no `WWW-Authenticate` + `Content-Type: application/json` → API key required
- Both can be signalled separately; the app handles whichever one fires from the connection test

## Risks / Trade-offs

- **`engineHasApiKey` boolean in SharedPreferences can get out of sync with actual secure storage**: if the user wipes app data partially. Mitigation: treat a missing key in secure storage as "not configured" regardless of the boolean, and reset the boolean on read.
- **`flutter_secure_storage` on Linux uses the Secret Service API** (requires `gnome-keyring` or `kwallet`). This is already a known requirement for the password. Adding the API key to the same storage raises no new platform risk.
- **All existing API callers must be updated**: engine callers (`getSessionInfo`, `getMessageHistory`, `sendAgenticMessage`, `getSessionsList`, `deleteSessionApi`) and `getChatResponse` in `chat/services.dart`. Each already accepts `authType/username/password`; adding `apiKey` is mechanical but touches many call sites. Mitigation: handle in a single task per service file.

## Migration Plan

1. **Engine**: No changes needed — `GET /api/v1/status` already exists and is already protected by API key. Basic Auth is the proxy's concern.
2. **App**: Extend `Settings`, `CredentialsManager`, `SecureCredentialService`, `_buildHeaders()` in both service files, and the settings UI. Existing users without an API key stored will get `engineHasApiKey = false` / `simpleChatHasApiKey = false` and no API key headers — identical to current behaviour.
3. **Health check endpoint swap**: Replace `GET /health` with `GET /api/v1/status` in the engine health check provider. Existing users without auth configured still get a 200.
