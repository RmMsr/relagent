# form-based-authentication Specification

## Purpose
TBD - created by archiving change add-api-authentication-support. Update Purpose after archive.
## Requirements
### Requirement: Form Authentication Detection

The system SHALL detect when an API requires form-based authentication based on HTTP redirect responses.

#### Scenario: Detect form auth via redirect to HTML
- **GIVEN** a health check request is made to the chat completions endpoint
- **WHEN** the API returns HTTP 302 redirect
- **AND** following the redirect results in a response with Content-Type "text/html" or "application/html"
- **THEN** the system SHALL identify this as form-based authentication requirement
- **AND** the authentication type SHALL be set to "form"

#### Scenario: Distinguish from other redirects
- **GIVEN** a health check request is made
- **WHEN** the API returns HTTP 302 redirect
- **AND** following the redirect results in Content-Type "application/json"
- **THEN** the system SHALL NOT identify this as form authentication
- **AND** the redirect SHALL be followed normally without triggering form auth flow

### Requirement: WebView Login Form Display

The system SHALL display web-based login forms in an embedded WebView for user authentication.

#### Scenario: Show login form in WebView dialog
- **GIVEN** form-based authentication is required for the API
- **WHEN** the user needs to authenticate (triggered by health check or 401 response)
- **THEN** a WebView dialog SHALL be displayed
- **AND** the WebView SHALL load the login form URL (from 302 redirect)
- **AND** the dialog SHALL have "Cancel" and a loading indicator

#### Scenario: User interacts with login form
- **GIVEN** the WebView login dialog is displayed
- **WHEN** the user enters credentials in the form fields
- **AND** submits the form
- **THEN** the WebView SHALL handle the form submission
- **AND** the system SHALL monitor navigation events for authentication completion

#### Scenario: Cancel form authentication
- **GIVEN** the WebView login dialog is displayed
- **WHEN** the user clicks "Cancel" button
- **THEN** the WebView SHALL close
- **AND** authentication SHALL be marked as incomplete
- **AND** the user SHALL return to settings with "Not authenticated" status

### Requirement: Cookie Capture from WebView

The system SHALL capture session cookies from WebView authentication flows and store them securely.

#### Scenario: Capture Set-Cookie from form submission
- **GIVEN** the user is authenticating via WebView login form
- **WHEN** the form submission response includes "Set-Cookie" headers
- **THEN** the system SHALL extract all Set-Cookie values
- **AND** the cookies SHALL be stored in secure credential storage
- **AND** the cookies SHALL be associated with the API endpoint URL

#### Scenario: Capture multiple cookies
- **GIVEN** the authentication flow sets multiple cookies (e.g., session_id, csrf_token)
- **WHEN** the WebView receives multiple Set-Cookie headers
- **THEN** all cookies SHALL be captured and stored
- **AND** each cookie SHALL preserve its attributes (Domain, Path, Secure, HttpOnly, Expires)

#### Scenario: Detect successful authentication
- **GIVEN** the user has submitted the login form in WebView
- **WHEN** the WebView navigates to a non-HTML page (e.g., JSON endpoint or redirect to API)
- **AND** cookies have been captured
- **THEN** the system SHALL consider authentication successful
- **AND** the WebView dialog SHALL close automatically
- **AND** the authentication status SHALL update to "Authenticated ✓"

### Requirement: Cookie Management in API Requests

The system SHALL include stored cookies in API requests for form-authenticated endpoints.

#### Scenario: Add cookies to chat request
- **GIVEN** the user has authenticated via form and cookies are stored
- **WHEN** a chat completion request is made
- **THEN** the request SHALL include a "Cookie" header
- **AND** the Cookie header SHALL contain all stored cookies for the API endpoint
- **AND** the cookies SHALL be formatted as "name1=value1; name2=value2"

#### Scenario: No cookies for unauthenticated endpoint
- **GIVEN** no form authentication has been performed
- **WHEN** a chat completion request is made
- **THEN** the request SHALL NOT include a "Cookie" header
- **AND** the request SHALL be sent without cookies (unauthenticated)

#### Scenario: Update cookies from response
- **GIVEN** a chat request is made with existing cookies
- **WHEN** the API response includes new "Set-Cookie" headers
- **THEN** the stored cookies SHALL be updated with the new values
- **AND** the updated cookies SHALL be used in subsequent requests

### Requirement: Form Authentication Session Management

The system SHALL handle cookie expiration and session renewal.

#### Scenario: Detect expired session via 401 response
- **GIVEN** the user was previously authenticated via form auth
- **WHEN** a chat request returns HTTP 401 or 403 Unauthorized
- **THEN** the system SHALL assume the session cookie has expired
- **AND** the user SHALL be prompted to re-authenticate via the login form
- **AND** the expired cookies SHALL be cleared from storage

#### Scenario: Re-authenticate after session expiry
- **GIVEN** a chat request failed due to expired session (401/403)
- **WHEN** the user completes re-authentication in the WebView
- **AND** new cookies are captured
- **THEN** the original chat request SHALL be automatically retried with new cookies
- **AND** the chat SHALL continue normally if authentication succeeds

#### Scenario: Preserve cookies across app restarts
- **GIVEN** the user has authenticated via form and cookies are stored
- **WHEN** the app is closed and reopened
- **THEN** the stored cookies SHALL be loaded from secure storage
- **AND** the cookies SHALL be included in the first chat request
- **AND** the user SHALL NOT need to re-authenticate (unless cookies expired)

### Requirement: Form Authentication Settings UI

The system SHALL provide UI controls for form-based authentication status and management.

#### Scenario: Display form auth status
- **GIVEN** form-based authentication is required for the API
- **WHEN** the user opens the settings page
- **THEN** the Authentication section SHALL display "Authentication Type: Form-based (Web Login)"
- **AND** a "Login via Form" button SHALL be visible
- **AND** the current authentication status SHALL be shown ("Authenticated ✓" or "Not authenticated")

#### Scenario: Trigger form authentication
- **GIVEN** the user is on the settings page and form auth is required
- **WHEN** the user clicks "Login via Form" button
- **THEN** the WebView login dialog SHALL open
- **AND** the login form URL SHALL be loaded

#### Scenario: Show logout option
- **GIVEN** the user is authenticated via form (cookies stored)
- **WHEN** the settings page is displayed
- **THEN** a "Logout" button SHALL be visible
- **AND** clicking "Logout" SHALL clear stored cookies
- **AND** the authentication status SHALL change to "Not authenticated"

#### Scenario: Form auth unavailable on URL change
- **GIVEN** the user was authenticated to "https://api1.example.com" via form
- **WHEN** the user changes the API URL to "https://api2.example.com"
- **THEN** the stored cookies SHALL be cleared
- **AND** the authentication status SHALL reset to "Not authenticated"
- **AND** if the new API requires form auth, the "Login via Form" button SHALL be enabled

