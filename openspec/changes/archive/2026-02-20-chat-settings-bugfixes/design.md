## Context

The app currently has two separate chat pages (`/simple` and `/agentic`) exposed as distinct navigation items. The splash page routes to one based on `selectedBackend`. Both pages have their own settings icon buttons, health check banners, and navigation menus listing both chat types. The settings page uses `Autocomplete` widgets with `fieldViewBuilder` that syncs internal controllers on every rebuild, which can cause value contamination when switching backend types. Health checks for both backends run regardless of which is active.

## Goals / Non-Goals

**Goals:**
- Material NavigationDrawer replacing PopupMenuButton for chat page navigation
- Single "Chat" navigation entry that loads the correct page based on `selectedBackend`
- Only run health checks for the currently active backend
- Health check recovery (fail→success) triggers data reload
- Add retry button to connection error banners
- Remove redundant settings icon button from chat app bars
- Show app icon and active backend type, base URL, engine version on the about page
- Fix Android app icon cropping (revert 16% inset)
- Fix settings input value swapping when switching backend type
- Consistent save behavior: explicit "Save" button only, Enter/Tab moves fields
- Engine base URL change resets engine-related state (sessions, SSE, health checks, session ID)

**Non-Goals:**
- Merging the two chat page implementations into one (they can remain separate)
- Changing the settings data model (fields are already properly separated)
- Adding new settings or configuration options

## Decisions

### 1. Unified navigation via router redirect + Material NavigationDrawer

Keep both chat page implementations but add a single `/chat` route with a `ChatRouterPage` `ConsumerWidget` that reads `selectedBackend` and renders the correct page. The splash page navigates to `/chat`.

Replace `PopupMenuButton` in both chat pages with Flutter's `NavigationDrawer` widget (opened via the hamburger icon / `Scaffold.drawer`). The drawer uses `NavigationDrawerDestination` entries: Chat, Sessions (engine only), Settings, About. The currently active page uses the drawer's `selectedIndex` — no manual checkmark needed (Material handles the selected state).

**Rationale**: Material NavigationDrawer is the standard pattern, gives better UX (swipe-to-open, proper selected state, header area for branding).

**Alternative considered**: A single `ChatPage` widget that switches between child widgets — rejected because the two chat pages have significantly different state management (SSE, sessions, etc.).

### 2. Conditional health checks via settings watch

Both `HealthCheckNotifier` and `EngineHealthCheckNotifier` already read `settingsProvider`. Add a guard at the beginning of their check methods that skips execution if the current backend doesn't match. The startup health check in `chat_page.dart` and `agentic_chat_page.dart` only triggers the relevant provider.

**Rationale**: Simple guard clause, no architectural change needed.

### 3. Retry button alongside "Check Settings"

Add a second button in the connection error banner's action row. The retry button calls `performImmediateHealthCheck()` (simple) or `triggerHealthCheck()` (engine). Use `OutlinedButton` for retry to visually differentiate from the primary `FilledButton` for settings.

**Rationale**: Users often want to retry without navigating away from chat.

### 4. Fix Autocomplete value swap via controller key management

The root cause of the value swap: `Autocomplete`'s `fieldViewBuilder` is called on every rebuild, and the line `fieldTextEditingController.text = _baseUrlController.text` syncs the internal controller. When backend switches and the widget tree rebuilds, the Autocomplete widgets may be recreated but the internal controller can receive stale text from a previous build frame. Additionally, listeners accumulate on rebuilds since `addListener` is called every time `fieldViewBuilder` runs.

**Fix**: Use `UniqueKey` on each `Autocomplete` widget keyed to the backend type so they are fully disposed and recreated on switch. This is simpler than managing listener lifecycle manually.

**Alternative considered**: Manually removing listeners — rejected because Autocomplete owns its internal `TextEditingController` and doesn't expose lifecycle hooks.

### 5. About page enhancement

Add `ConsumerWidget` to `InfoPage` to read `settingsProvider` and `engineHealthCheckProvider`. Show the app icon (from `assets/icon/app_icon.png`) at the top, followed by cards:
- Chat Backend: "OpenAI-compatible" or "Relagent Engine"
- Base URL: the configured URL for the active backend
- Engine Version: from `EngineHealthResult.engineVersion` (only when engine backend is active and health check succeeded)

**Rationale**: Reuses existing health check state. No additional network requests needed. The app icon gives the page a branded feel consistent with the splash screen.

### 6. Remove settings icon from chat app bars

Both `chat_page.dart` and `agentic_chat_page.dart` have an `IconButton(icon: Icons.settings)` in their `actions`. Remove these — settings is accessible via the navigation drawer.

### 7. Consistent settings save behavior

Currently the model name field has `onEditingComplete: _saveSettings()`, which triggers a save (and health check) when the user presses Enter on that field. Other fields use `TextInputAction.next` to move focus. This inconsistency confuses users.

**Fix**: Remove `_saveSettings()` from `onEditingComplete` on the model field. Change its `textInputAction` to `TextInputAction.next` so Enter/Tab moves to the next field. All saves happen via the explicit "Save" button only.

### 8. Engine base URL change resets engine state

When `updateEngineBaseUrl` detects the URL has actually changed, it should also:
1. Clear `agenticSessionId` (the session belongs to the old engine)
2. Clear the persisted SSE `lastEventId` (events are engine-specific)
3. Clear the engine health check result
4. Clear sessions list state

This prevents stale session data from the previous engine being shown after switching to a new one.

**Implementation**: Add a `clearLastEventId()` method to `SseNotifier`. Call it plus `clearAgenticSessionId()` from `updateEngineBaseUrl()`. The health check and sessions providers will naturally refresh on next use.

### 9. Health check recovery triggers data reload

When the health check transitions from a failure state to success (detected via `ref.listen` on the health check provider), the chat page should:
- Dismiss the connection error banner
- For agentic chat: trigger `loadHistory()` and SSE `reconnect()` to pick up any missed data
- For simple chat: no additional action needed (messages are not persisted server-side)

### 10. Android app icon cropping fix

Revert the 16% inset added in commit e4ddb24c to `ic_launcher.xml`. The original `<foreground android:drawable="@drawable/ic_launcher_foreground"/>` without inset is correct — Android's adaptive icon system already handles safe-zone cropping.

## Risks / Trade-offs

- **Router redirect adds a hop**: The `/chat` redirect is nearly instant (no network, no async) and won't be visible to users → Acceptable.
- **UniqueKey forces Autocomplete recreation**: Slightly heavier than patching listeners, but guarantees clean state → Worth it for correctness.
- **Engine version only available after health check**: If the engine health check hasn't run yet, the about page won't show version info. This is acceptable since the field simply won't appear.
- **Engine URL change clears session**: Users lose their current agentic session when changing engine URL. This is expected — the old session belongs to the old engine.
- **NavigationDrawer vs PopupMenu**: Slightly more code but standard Material pattern. Better accessibility and discoverability.
