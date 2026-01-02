# Design: API Authentication Support

## Architectural Overview

This change introduces authentication capabilities for OpenAI-compatible chat APIs, spanning multiple systems: secure storage, HTTP client layer, settings management, and user interface.

## System Components

### 1. Secure Credential Storage Layer

**Purpose**: Isolate credential storage from business logic and provide fallback for platforms without secure storage.

**Design**:
```
SecureCredentialService (new)
├─ flutter_secure_storage (platform-specific)
└─ In-memory fallback (session-only)
```

**Key Decisions**:
- Abstract storage behind a service interface to enable testing and platform fallbacks
- Never persist credentials to SharedPreferences (security requirement)
- Use in-memory storage as fallback when secure storage unavailable
- Warn users prominently when using in-memory fallback

**Trade-offs**:
- **Pro**: Platform-agnostic, testable, secure by default
- **Con**: Additional abstraction layer increases complexity slightly
- **Pro**: Graceful degradation on unsupported platforms
- **Con**: Session-only credentials require re-entry after restart

### 2. Authentication Detection Logic

**Purpose**: Automatically determine authentication requirements from HTTP responses without user configuration.

**Design**:
```
HTTP Response Analysis:
├─ 401 + WWW-Authenticate header → Basic Auth required
├─ 302 redirect → Follow and check content type
│  └─ Content-Type: text/html or application/html → Form Auth required
└─ 200-299 → No authentication or already authenticated
```

**Key Decisions**:
- Detection happens transparently during health check and normal API calls
- No user configuration needed for auth type (auto-detected)
- Form auth identified by redirect to HTML content (common pattern)
- Support future auth types by extending detection logic

**Trade-offs**:
- **Pro**: User-friendly, automatic detection reduces configuration burden
- **Con**: May misidentify edge cases (e.g., API with informational HTML on 302)
- **Pro**: Extensible to new authentication types without UI changes
- **Con**: Requires network round-trip to detect auth requirements

### 3. HTTP Client Enhancement

**Purpose**: Extend existing http package usage to support authentication headers and cookie management.

**Design**:
```
getChatResponse() flow:
1. Check if credentials exist for current endpoint
2. Determine auth type (Basic vs Form via detection)
3. Add authentication:
   - Basic: Add Authorization header
   - Form: Include stored cookies in Cookie header
4. Make request
5. Handle auth failures:
   - 401/403 → Trigger re-auth flow
   - Success → Update cookie storage if Set-Cookie present
```

**Key Decisions**:
- Keep http package (no migration to dio or other HTTP clients)
- Manual cookie management using header strings (no external cookie jar library)
- Re-authentication triggered automatically on auth failure
- Cookie storage persisted to secure storage

**Trade-offs**:
- **Pro**: Minimal dependencies, leverages existing http package
- **Con**: Manual cookie parsing more error-prone than dedicated library
- **Pro**: Automatic re-auth improves UX during expired sessions
- **Con**: Re-auth flow adds complexity to error handling

### 4. Form-Based Authentication Flow

**Purpose**: Support web-based login forms by embedding WebView and capturing authentication cookies.

**Design**:
```
Form Auth Flow:
1. Health check detects 302 → HTML (login form required)
2. Display login form URL in WebView dialog
3. User enters credentials in form
4. Monitor WebView navigation:
   - Capture Set-Cookie headers from all responses
   - Detect successful auth (e.g., redirect to non-HTML endpoint)
5. Store cookies securely
6. Close WebView, mark auth as complete
```

**Key Decisions**:
- Use WebView (via webview_flutter package) to display login forms
- Capture cookies from WebView navigation events
- No attempt to parse form HTML or submit programmatically
- User completes form interaction normally (better compatibility)

**Trade-offs**:
- **Pro**: Works with any HTML form, no parsing required
- **Con**: Requires webview_flutter dependency
- **Pro**: Handles complex auth flows (captcha, 2FA redirects, etc.)
- **Con**: User sees web UI instead of native form (may feel inconsistent)

### 5. Health Check System

**Purpose**: Validate API configuration and authentication before chat operations.

**Design**:
```
Health Check:
1. Attempt request to /chat/completions with minimal payload
2. Detect authentication requirement (see detection logic)
3. If auth required:
   - Prompt user for credentials (if not stored)
   - Retry with authentication
4. Return status:
   - Success: API reachable and authenticated
   - Auth Required: Need credentials
   - Failed: Network error or API unavailable
```

**Key Decisions**:
- Health check uses actual /chat/completions endpoint (not dedicated health endpoint)
- Runs automatically on URL/credential changes AND app startup
- Minimal payload to reduce server load
- Status exposed to UI for user feedback

**Trade-offs**:
- **Pro**: Validates real endpoint, not just network connectivity
- **Con**: Uses API quota if endpoint charges per request
- **Pro**: Automatic validation catches configuration errors early
- **Con**: Adds startup latency (mitigated by async loading)

### 6. Settings UI Extension

**Purpose**: Add authentication controls to existing settings page without major redesign.

**Design**:
```
Settings Page Layout:
├─ API Configuration Section (existing)
│  ├─ Chat Base URL
│  ├─ Chat Model
│  └─ [Test Connection] button (new)
├─ Authentication Section (new)
│  ├─ Authentication Type (Auto-detected, read-only)
│  ├─ Username field (conditional: Basic Auth only)
│  ├─ Password field (conditional: Basic Auth only)
│  ├─ [Login via Form] button (conditional: Form Auth only)
│  └─ Auth Status indicator (authenticated/not authenticated)
└─ Other Settings...
```

**Key Decisions**:
- Add new authentication section below API configuration
- Conditional visibility: show only relevant fields for detected auth type
- Read-only auth type (auto-detected, not user-selectable)
- Test Connection button provides immediate feedback

**Trade-offs**:
- **Pro**: Natural extension of existing settings layout
- **Con**: Settings page becomes longer (may need scrolling)
- **Pro**: Conditional fields reduce clutter when auth not needed
- **Con**: Dynamic UI may confuse users if auth type changes unexpectedly

### 7. Settings Model Extension

**Purpose**: Extend Settings model to include authentication configuration while maintaining backward compatibility.

**Design**:
```dart
enum AuthType { none, basic, form }

class Settings {
  // Existing fields...
  final AuthType authType;
  final String? username; // Only for basic auth
  final bool isAuthenticated; // Runtime status

  // Note: Password and cookies stored in SecureCredentialService, not Settings
}
```

**Key Decisions**:
- Add authType to Settings (persisted to SharedPreferences)
- Username persisted to SharedPreferences (not sensitive)
- Password and cookies only in secure storage (never SharedPreferences)
- isAuthenticated is runtime state, not persisted

**Trade-offs**:
- **Pro**: Backward compatible (auth fields default to none/null)
- **Con**: Split storage (Settings in SharedPreferences, credentials in secure storage)
- **Pro**: Sensitive data properly isolated
- **Con**: Two storage systems to synchronize

## Data Flow

### Typical Chat Request with Basic Auth:
```
1. User sends chat message
2. ChatProvider calls getChatResponse()
3. getChatResponse() checks SecureCredentialService for credentials
4. Credentials found → Add Authorization header
5. POST to /chat/completions with auth header
6. Success → Return response
```

### Auth Failure and Re-authentication:
```
1. POST to /chat/completions returns 401
2. getChatResponse() detects auth failure
3. Trigger re-auth dialog (username/password for Basic)
4. User enters credentials
5. Store in SecureCredentialService
6. Retry original request with new credentials
7. Success → Return response
```

### Form-Based Auth Setup:
```
1. User changes API URL in settings
2. Health check detects 302 → HTML
3. Settings UI shows "Login via Form" button
4. User clicks button
5. WebView dialog opens with form URL
6. User completes login form
7. WebView captures Set-Cookie headers
8. Cookies stored in SecureCredentialService
9. Health check retries, succeeds
10. Settings UI shows "Authenticated ✓"
```

## Security Considerations

**Credential Storage**:
- Use platform keychain/keystore via flutter_secure_storage
- Never log credentials (even in debug mode)
- Clear credentials when user logs out or changes URL

**Cookie Handling**:
- Store cookies with associated URL (don't leak to other endpoints)
- Include Secure and HttpOnly flags when present
- Expire cookies based on Max-Age/Expires directives

**Network Security**:
- Recommend HTTPS for authenticated endpoints (show warning for HTTP)
- No credential transmission over unencrypted connections (if enforceable)

**Error Messages**:
- Don't expose credentials in error messages or logs
- Generic "authentication failed" instead of specific credential errors

## Testing Strategy

**Unit Tests**:
- SecureCredentialService with mock storage
- Authentication detection logic with various response scenarios
- Cookie parsing and storage
- Settings model serialization with auth fields

**Integration Tests**:
- End-to-end Basic Auth flow with mock server
- Form auth flow with mock WebView (if possible)
- Health check with various API responses
- Re-authentication during active chat session

**Manual Testing**:
- Real API with Basic Auth
- Real API with form-based auth
- Secure storage unavailable scenario (Android with device admin restrictions)
- App restart with saved credentials
- Credential expiration and re-auth flow

## Migration Path

**Existing Users**:
- No migration needed (auth fields default to none)
- Settings load normally with new auth fields defaulting
- Existing unauthenticated API connections work unchanged

**Future Extensions**:
- OAuth 2.0: Add oauth auth type, token management
- API Key: Add apiKey auth type, key storage
- Multi-endpoint credentials: Extend Settings model to map URL → credentials

## Performance Impact

**Minimal**:
- Secure storage read/write adds ~10-50ms per operation (acceptable)
- Health check on startup adds <1s latency (async, non-blocking)
- Cookie parsing adds negligible overhead (<1ms per request)

**Optimization Opportunities**:
- Cache credentials in memory after first read (reduce secure storage reads)
- Debounce health check on rapid setting changes
- Lazy health check (only when user attempts chat, not on startup)

## Open Technical Questions

1. **Cookie Scope**: Should cookies be scoped to exact URL or domain?
   - Recommendation: Exact URL for security, can relax if needed

2. **WebView Package**: webview_flutter vs flutter_inappwebview?
   - Recommendation: webview_flutter (official, well-maintained)

3. **Re-auth UX**: Dialog vs. navigate to settings page?
   - Recommendation: Dialog for Basic (inline), settings for Form (better UX)

4. **Credential Clearing**: When should credentials be automatically cleared?
   - Recommendation: Only on URL change or explicit user action (preserve on model change)
