## 1. Credential Storage Layer

- [x] 1.1 Add `storeApiKey(String url, String key)`, `getApiKey(String url)`, and `clearApiKey(String url)` methods to `SecureCredentialService` using a `_makeApiKeyStorageKey(url)` helper (distinct namespace from password key)
- [x] 1.2 Add engine API key methods to `CredentialsManager`: `storeEngineApiKey`, `getEngineApiKey`, `clearEngineApiKey` (namespace: `engine_api_key_<url>`)
- [x] 1.3 Add simple chat API key methods to `CredentialsManager`: `storeChatApiKey`, `getChatApiKey`, `clearChatApiKey` (namespace: `chat_api_key_<url>`)

## 2. Settings Model

- [x] 2.1 Add `engineHasApiKey` and `simpleChatHasApiKey` boolean fields to `Settings` with `false` defaults
- [x] 2.2 Update `Settings.copyWith()`, `toJson()`, `fromJson()`, `==`, and `hashCode` to include both new fields

## 3. Auth Detection

- [x] 3.1 Extend `detectAuthType()` in `lib/chat/auth_detection.dart` to detect API key requirement: HTTP 401 + `Content-Type: application/json` + no `WWW-Authenticate` header → new `AuthType.apiKey` (or equivalent signal)
- [x] 3.2 Add `AuthType.apiKey` to the `AuthType` enum in `lib/models/settings.dart` for detection signalling (distinct from storage — only used in detection result, not persisted)

## 4. Engine Health Check Service

- [x] 4.1 In `EngineHealthCheckService.checkStatus()` (`lib/agentic/health_check.dart`): change target URL from `$normalizedUrl/health` to `$normalizedUrl/api/v1/status`
- [x] 4.2 Add `apiKey` parameter to `checkStatus()` and inject `X-API-Key: <key>` header when non-null
- [x] 4.3 Update 401 handling in `checkStatus()` to use `detectAuthType()` so API key requirement is correctly identified (returns `authRequired` with API key signal, not generic `authRequired`)

## 5. Simple Chat Health Check Service

- [x] 5.1 Add `apiKey` parameter to `ApiHealthCheckService.performHealthCheck()` (`lib/services/api_health_check.dart`)
- [x] 5.2 Inject `Authorization: Bearer <key>` header when `apiKey` is non-null (do not inject if null)

## 6. Agentic Services — Header Injection

- [x] 6.1 Add `apiKey` parameter to `_buildHeaders()` in `lib/agentic/services.dart` and inject `X-API-Key: <key>` header when non-null
- [x] 6.2 Add `apiKey` parameter to all public functions in `lib/agentic/services.dart`: `getSessionInfo`, `getMessageHistory`, `sendAgenticMessage`, `getSessionsList`, `deleteSessionApi`

## 7. Chat Services — Bearer Header Injection

- [x] 7.1 Add `apiKey` parameter to `getChatResponse()` in `lib/chat/services.dart`
- [x] 7.2 Inject `Authorization: Bearer <key>` when `apiKey` is non-null; when both Basic Auth and API key are present use Bearer and omit Basic (no conflicting Authorization headers)

## 8. Settings Provider — URL Change and Save

- [x] 8.1 On `engineBaseUrl` change: call `credentialsManager.clearEngineApiKey(oldUrl)` and set `engineHasApiKey = false` in the updated settings (alongside existing session/SSE state clearing)
- [x] 8.2 On `simpleChatBaseUrl` change: call `credentialsManager.clearChatApiKey(oldUrl)` and set `simpleChatHasApiKey = false`
- [x] 8.3 On settings save with a non-empty engine API key field: call `credentialsManager.storeEngineApiKey(url, key)` and set `engineHasApiKey = true`
- [x] 8.4 Empty API key field on save keeps the existing stored key (no auto-clear); clearing is done explicitly via the Clear Credentials button which calls `credentialsManager.clearEngineApiKey(url)` and sets `engineHasApiKey = false`
- [x] 8.5 Same pattern as 8.3–8.4 for simple chat API key using `credentialsManager.storeChatApiKey` / `clearChatApiKey` and `simpleChatHasApiKey`

## 9. Provider Wire-up — Pass API Key to Service Calls

- [x] 9.1 In `engine_health_check_provider.dart`: load `engineApiKey` via `credentialsManager.getEngineApiKey(url)` and pass it to `EngineHealthCheckService.checkStatus()`
- [x] 9.2 In `health_check_provider.dart`: load `chatApiKey` via `credentialsManager.getChatApiKey(url)` and pass it to `ApiHealthCheckService.performHealthCheck()`
- [x] 9.3 In `agentic_chat_provider.dart` (and `sessions_provider.dart`, `sse_provider.dart`): load `engineApiKey` via `credentialsManager.getEngineApiKey(url)` and pass it to all `lib/agentic/services.dart` calls
- [x] 9.4 In the provider that calls `getChatResponse()`: load `chatApiKey` via `credentialsManager.getChatApiKey(url)` and pass it through

## 10. Settings Page UI

- [x] 10.1 Add API key input field (password-style, obscured) to the Engine authentication section; show "API key saved" hint when `engineHasApiKey` is true; field is empty on load
- [x] 10.2 Add API key input field (password-style, obscured) to the Simple Chat authentication section; show "API key saved" hint when `simpleChatHasApiKey` is true; field is empty on load
- [x] 10.3 Wire up both fields to the settings save/clear flow in task group 8

## 11. Quality

- [x] 11.1 Run `dart-flutter_analyze_files` and fix all warnings and errors
- [x] 11.2 Run `dart-flutter_run_tests` and ensure all existing tests pass
- [x] 11.3 Add unit tests for `SecureCredentialService` API key methods (store, retrieve, clear, namespace isolation)
- [x] 11.4 Add unit tests for the updated `detectAuthType()` covering the new API key detection scenario
