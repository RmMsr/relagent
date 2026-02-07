# Proposal: Add API Authentication Support

## Why

Many self-hosted or enterprise OpenAI-compatible APIs require authentication, which prevents users from connecting to these services. The app currently only supports unauthenticated API endpoints or APIs where authentication is handled externally.

## Summary

Add support for authenticated OpenAI-compatible chat completion APIs using HTTP Basic authentication with secure credential storage. Form-based authentication was removed from scope to maintain simplicity and focus on the most common authentication method used by self-hosted AI APIs.

## Problem

Currently, the app only supports unauthenticated API endpoints or APIs where authentication is handled externally. Many self-hosted or enterprise OpenAI-compatible APIs require authentication, which prevents users from connecting to these services.

Users need to:
- Connect to APIs requiring HTTP Basic authentication (username/password) ✅
- Store credentials securely so other apps cannot access them ✅
- Test API connectivity before using the service ✅
- Receive clear feedback when authentication is required ✅

Note: Form-based authentication was deemed too complex and removed from scope. HTTP Basic Auth covers the vast majority of self-hosted AI API authentication needs.

## Goals

1. **Secure Credential Management**: Store authentication credentials using platform-specific secure storage (not SharedPreferences) ✅
2. **HTTP Basic Auth**: Support standard HTTP Basic authentication with username/password ✅
3. **Form-Based Auth**: Support HTML form-based login with automatic cookie capture and management ❌ REMOVED FROM SCOPE
4. **Authentication Detection**: Automatically detect authentication requirements based on HTTP response codes and headers ✅
5. **Health Check**: Provide connection testing to validate API configuration and authentication ✅
6. **User Guidance**: Guide users to appropriate settings when authentication is required ✅

## Non-Goals

- OAuth 2.0 authentication (future consideration)
- API key authentication (can be added later if needed)
- Multi-factor authentication
- Manual cookie editing
- Custom authentication schemes beyond Basic
- **Form-based authentication** (complexity outweighs benefit) ✅ REMOVED FROM SCOPE

## Scope

This change affects:
- **Settings UI**: Add credential input fields to settings page
- **Settings Model**: Extend to include authentication type and credential references
- **Secure Storage**: Introduce flutter_secure_storage for credential management
- **HTTP Client**: Modify chat API service to handle authentication headers and cookies
- **Health Check**: Add new API health check functionality
- **Error Handling**: Enhance error messages to guide users to authentication settings

## Dependencies

- **New Package**: flutter_secure_storage (^9.2.2) - Platform-specific secure credential storage
- **Existing**: http package - Will be extended for cookie and auth header management

## Risks and Mitigations

**Risk**: Credentials stored insecurely if flutter_secure_storage fails
- **Mitigation**: Never fall back to SharedPreferences; fail gracefully and require re-entry

**Risk**: Cookie expiration causes authentication failures during normal operation
- **Mitigation**: Detect 401/403 responses and guide user to re-authenticate

**Risk**: Form-based authentication too complex or service-specific
- **Mitigation**: Start with simple form detection (302 → HTML); iterate based on real-world usage

**Risk**: Breaking existing users with unauthenticated APIs
- **Mitigation**: Authentication is optional; existing settings continue to work unchanged

## Implementation Strategy

1. **Phase 1: Secure Storage Foundation** ✅ - Add flutter_secure_storage and credential management
2. **Phase 2: HTTP Basic Auth** ✅ - Implement username/password authentication with UI
3. **Phase 3: Form-Based Auth** ❌ - Form-based authentication removed from scope (too complex)
4. **Phase 4: Health Check** ✅ - Implement connection testing with authentication validation
5. **Phase 5: Error Handling** ✅ - Enhance user feedback and guidance
6. **Phase 6: Performance Optimization** ✅ - Add credential caching and health check debouncing
7. **Phase 7: Testing & Bug Fixes** ✅ - Comprehensive testing and critical bug resolution

## Current Status: PRODUCTION READY

**Completed Implementation:**
- ✅ Core HTTP Basic Authentication functionality
- ✅ Secure credential storage with platform-specific encryption
- ✅ API health check with authentication validation
- ✅ Settings UI with Test Connection functionality
- ✅ Performance optimizations (credential caching, debounced health checks)
- ✅ Comprehensive test coverage (61 tests passing)
- ✅ Critical bug fixes (build errors, authentication synchronization)
- ✅ All Flutter analysis checks passing

**Deferred for Future Iteration:**
- Enhanced UI/UX improvements and additional user guidance features
- Advanced error messaging and user onboarding

## Success Criteria

- Users can connect to APIs requiring HTTP Basic authentication ✅
- Users can connect to APIs requiring form-based login ❌ REMOVED FROM SCOPE
- Credentials are stored securely and persist across app restarts ✅
- API health check validates authentication before chat usage ✅
- Clear error messages guide users when authentication fails or is required ✅
- Existing unauthenticated API connections continue to work without changes ✅
- All 61 tests passing and Flutter analysis shows no errors ✅
- Performance optimized with caching and debouncing ✅

## Decisions

1. **Credential Storage Scope**: Single credential set per endpoint
   - Credentials are tied to the current API URL
   - When URL changes, user enters new credentials if needed
   - Simpler implementation and UI, meets current needs

2. **Cookie Expiration Handling**: Auto-retry with re-authentication prompt
   - When a request fails with 401/403, automatically prompt user to re-authenticate
   - Retry the failed request after successful re-auth
   - Provides smoother user experience during active sessions

3. **Health Check Triggers**: Automatic on URL/credential changes AND after app startup
   - Runs automatically when user changes API URL or credentials
   - Also runs after app startup to validate saved configuration
   - Provides immediate feedback on configuration validity

4. **Secure Storage Unavailability**: Warn but allow session-only credentials
   - Show warning if secure storage is not available
   - Allow credentials to be entered for current session only
   - Credentials are lost on app restart, requiring re-entry
   - Trade-off between security and functionality on unsupported platforms

## Related Changes

- None (this is a new capability)

## References

- HTTP Basic Authentication: [RFC 7617](https://tools.ietf.org/html/rfc7617)
- flutter_secure_storage: [pub.dev/packages/flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)
- OpenAI API Authentication: Similar pattern to self-hosted services
