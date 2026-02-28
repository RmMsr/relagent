## Why

The chat navigation exposes implementation details (separate "Simple Chat" and "Agentic Chat" pages) instead of presenting a single unified "Chat" experience controlled by the backend setting. Several smaller bugs compound this: health checks run for both backends regardless of which is active, the connection error banner lacks a retry button, the settings page swaps input values when switching backend type, and the about/info page doesn't show the active chat type or engine version.

## What Changes

- **Unified chat navigation**: Remove the two separate chat entries from the navigation menu. Show a single "Chat" entry. The underlying pages can remain separate but the user navigates to "Chat" and the correct page loads based on `selectedBackend`.
- **Material navigation drawer**: Replace PopupMenuButton with a proper Material NavigationDrawer. No checkmark on Chat — use standard selected state. Entries: Chat, Sessions (engine only), Settings, About.
- **Remove settings button from chat app bars**: Settings is already accessible via the navigation drawer, so the dedicated settings icon button in the app bar is redundant.
- **About page shows chat type and engine version**: The info/about page displays which backend is active (OpenAI-compatible vs Relagent Engine), the configured base URL, and engine version (when available from the health check result). The app icon (minion) is shown at the top of the about page.
- **Android app icon cropping**: Commit e4ddb24c2e10429eac40c9d9cbe73b593fc01b28 added a 16% inset to the Android adaptive icon foreground, shrinking the minion. Revert the inset so the Android icon matches the original non-cropped appearance. The cropped icon from `assets/icon/app-icon.png` is used for splash screen, about page, and web favicon.
- **Conditional health checks**: Only run health checks for the active backend type. When `selectedBackend` is `openAiCompatible`, don't run engine health checks and vice versa.
- **Health check recovery triggers data reload**: When the startup health check transitions from failing to successful, clear the connection error banner and trigger data reload (fetch events, load messages for agentic; no action needed for simple chat).
- **Retry button on connection error banner**: Add a "Retry" button next to the existing "Check Settings" button on the connection issue info box in both chat pages.
- **Fix settings input value swapping**: When switching backend type on the settings page, inputs should not swap values. Each backend's fields (base URL, model, auth) are independent and their controllers must retain their own values. The switch only toggles visibility.
- **Consistent settings save behavior**: Remove the implicit save-on-editing-complete from the model name field. All settings are saved only via the explicit "Save" button. Enter/Tab should move through fields, not trigger save.
- **Engine base URL change resets engine state**: When the engine base URL is changed, clear chat data: sessions list, last seen SSE event ID, health check results, and agentic session ID.

## Capabilities

### New Capabilities

_(none — all changes modify existing capabilities)_

### Modified Capabilities

- `user-settings`: Backend switch must not swap/contaminate input values; consistent save behavior (explicit Save button only); Enter/Tab moves between fields; engine base URL change resets engine state (sessions, SSE event ID, health checks, session ID)
- `api-health-check`: Health checks should only run for the currently active backend type; connection error banner gets retry button; health check recovery triggers data reload
- `agentic-chat`: Material navigation drawer instead of PopupMenu; about page shows app icon, backend type, and engine version; Android icon cropping fix

## Impact

- **Router**: `app_router.dart` — single `/chat` route that delegates based on backend
- **Chat pages**: `chat_page.dart`, `agentic_chat_page.dart` — Material NavigationDrawer, settings button removal, retry button in error banner
- **Info page**: `info_page.dart` — app icon at top, display active backend, base URL, engine version
- **Health check providers**: `health_check_provider.dart`, `engine_health_check_provider.dart` — conditional activation, recovery-triggered data reload
- **Settings page**: `settings_page.dart` — fix controller value swapping; consistent save (remove onEditingComplete save); Enter/Tab moves focus
- **Settings provider**: `settings_provider.dart` — engine base URL change resets sessions, SSE last event ID, health checks, session ID
- **SSE provider**: `sse_provider.dart` — method to clear persisted last event ID
- **Android icon**: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — revert 16% inset
