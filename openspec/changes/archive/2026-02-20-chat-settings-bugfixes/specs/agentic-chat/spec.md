## MODIFIED Requirements

### Requirement: Agentic Chat Page

The system SHALL provide an Agentic Chat page as the primary frontend for the Relagent engine.

#### Scenario: Default app page

- **WHEN** the app is launched
- **THEN** the chat page for the selected backend SHALL be displayed by default

#### Scenario: Chat interface layout

- **WHEN** the Agentic Chat page is displayed
- **THEN** the page SHALL include a message list, text input, voice mode selector, and navigation drawer
- **AND** the layout SHALL be consistent with the simple chat interface

#### Scenario: Material navigation drawer

- **WHEN** the user opens the navigation drawer (via hamburger icon or swipe)
- **THEN** the drawer SHALL follow Material Design NavigationDrawer pattern
- **AND** the drawer SHALL show entries: Chat (selected), Sessions (engine only), Settings, About
- **AND** the currently active page SHALL be indicated using the drawer's built-in selected state (no manual checkmark)
- **AND** the drawer SHALL NOT show separate "Simple Chat" and "Agentic Chat" entries

### Requirement: Engine Connection

The system SHALL connect to the Relagent engine API using the configured Engine URL.

#### Scenario: Successful connection

- **GIVEN** a valid Engine URL is configured
- **WHEN** the app communicates with the engine
- **THEN** messages SHALL be sent and received successfully

#### Scenario: Connection failure

- **GIVEN** the Engine URL is unreachable or invalid
- **WHEN** the app attempts to communicate
- **THEN** an error banner SHALL be displayed with "Retry" and "Check Settings" actions

#### Scenario: Authentication required

- **GIVEN** the engine requires authentication
- **WHEN** basic auth credentials are configured
- **THEN** the `Authorization: Basic` header SHALL be included in all requests

## ADDED Requirements

### Requirement: About page shows app icon and backend info

The about/info page SHALL display the app icon at the top, followed by the active chat backend type, configured base URL, and engine version when available.

#### Scenario: App icon displayed
- **WHEN** the user opens the About page
- **THEN** the app icon (minion) from `assets/icon/app_icon.png` SHALL be displayed prominently at the top of the page

#### Scenario: OpenAI-compatible backend info
- **GIVEN** the selected backend is OpenAI-compatible
- **WHEN** the user opens the About page
- **THEN** the page SHALL show "OpenAI-compatible" as the chat backend
- **AND** the page SHALL show the configured simple chat base URL

#### Scenario: Relagent Engine backend info
- **GIVEN** the selected backend is Relagent Engine
- **WHEN** the user opens the About page
- **THEN** the page SHALL show "Relagent Engine" as the chat backend
- **AND** the page SHALL show the configured engine base URL

#### Scenario: Engine version displayed when available
- **GIVEN** the selected backend is Relagent Engine
- **AND** a successful engine health check has been performed
- **WHEN** the user opens the About page
- **THEN** the page SHALL show the engine version from the health check result

#### Scenario: Engine version not shown when unavailable
- **GIVEN** no successful engine health check has been performed
- **WHEN** the user opens the About page
- **THEN** the engine version field SHALL NOT be displayed

### Requirement: Unified chat route

The router SHALL provide a single `/chat` route that displays the correct chat page based on the selected backend setting.

#### Scenario: Route to simple chat
- **GIVEN** the selected backend is OpenAI-compatible
- **WHEN** the user navigates to `/chat`
- **THEN** the simple chat page SHALL be displayed

#### Scenario: Route to agentic chat
- **GIVEN** the selected backend is Relagent Engine
- **WHEN** the user navigates to `/chat`
- **THEN** the agentic chat page SHALL be displayed

#### Scenario: Splash page navigates to unified route
- **GIVEN** the app is starting up
- **WHEN** the splash screen completes
- **THEN** navigation SHALL go to `/chat` regardless of the selected backend

### Requirement: Android app icon uses correct cropping

The Android adaptive icon SHALL use the foreground drawable without additional inset, relying on Android's built-in safe-zone handling for adaptive icons.

#### Scenario: No extra inset on Android icon
- **GIVEN** the Android adaptive icon configuration
- **WHEN** the app icon is rendered on Android
- **THEN** the foreground drawable SHALL NOT have an additional 16% inset
- **AND** the icon SHALL use `<foreground android:drawable="@drawable/ic_launcher_foreground"/>` directly
