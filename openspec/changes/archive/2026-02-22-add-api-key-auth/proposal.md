## Why

The Relagent engine supports API key authentication via the `X-API-Key` header, but the app has no API key support for either backend. Users connecting to protected engine instances need a way to supply an API key, and OpenAI-compatible providers (LM Studio, Ollama, hosted APIs) often require one too. Authentication credentials are inherently tied to a specific URL, so the settings model must bind them per URL rather than globally.

## What Changes

- Add `X-API-Key` header support for the **Relagent engine** alongside existing Basic Auth (both schemes optional and co-existing)
- Add `Authorization: Bearer <key>` support for the **OpenAI-compatible** backend alongside existing Basic Auth
- Detect missing API key via 401 response with `application/json` content-type (distinct from Basic Auth detection via `WWW-Authenticate` header)
- Credentials (Basic Auth username/password, API key) become per-URL attributes in settings persistence — changing the URL clears all credentials for that slot
- Engine connection test switches from `GET /health` (unauthenticated) to `GET /api/v1/status` (requires auth) to actually validate credentials
- All credentials stored in platform secure storage (iOS Keychain, Android Keystore, Linux Secret Service) — not accessible to other apps

## Capabilities

### New Capabilities

- `api-key-authentication`: API key header authentication for both backends — UI fields, header injection per backend convention (`X-API-Key` for engine, `Authorization: Bearer` for OpenAI-compatible), detection, secure storage, and credential clearing on URL change

### Modified Capabilities

- `auth-detection`: Add API key detection pattern (HTTP 401 + `application/json` content-type with no `WWW-Authenticate` header signals missing API key)
- `api-health-check`: Engine connection test endpoint changes from unauthenticated `GET /health` to authenticated `GET /api/v1/status`, which validates both Basic Auth and API key credentials
- `user-settings`: Authentication options (Basic Auth credentials, API key) become per-URL attributes for both engine and simple chat slots — stored and cleared per URL, not globally
- `secure-credential-storage`: Extend to cover API key storage for both backends alongside existing password/cookie support

## Impact

- **Flutter app** (`lib/models/settings.dart`, `lib/providers/settings_provider.dart`): Settings model gains `engineHasApiKey` and `simpleChatHasApiKey` boolean indicators; actual keys excluded from SharedPreferences
- **Flutter app** (`lib/agentic/services.dart`): HTTP client adds `X-API-Key` header injection; health check endpoint updated to `/api/v1/status`
- **Flutter app** (`lib/chat/services.dart`): HTTP client adds `Authorization: Bearer` header injection for OpenAI-compatible requests
- **Flutter app** (`lib/pages/settings_page.dart`): New API key input fields in both engine and simple chat authentication sections
- **Flutter app** (`lib/services/secure_credential_service.dart`, `lib/providers/credentials_manager.dart`): New `storeApiKey`/`getApiKey`/`clearApiKey` methods per backend namespace
- **No engine changes**: `GET /api/v1/status` already exists and is already protected by API key; Basic Auth is enforced by a reverse proxy, not the engine
- **Dependencies**: `flutter_secure_storage` is already in `pubspec.yaml` and the `SecureCredentialService` is already in use
