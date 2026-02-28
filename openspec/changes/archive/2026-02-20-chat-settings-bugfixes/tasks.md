## 1. Unified Chat Route

- [x] 1.1 Add `/chat` redirect route in `app_router.dart` that reads `selectedBackend` from settings and redirects to `/simple` or `/agentic`
- [x] 1.2 Update `splash_page.dart` to navigate to `/chat` instead of `/simple` or `/agentic`

## 2. Material Navigation Drawer

- [x] 2.1 ~~Update `chat_page.dart` navigation menu~~ (superseded by 2.5)
- [x] 2.2 ~~Update `agentic_chat_page.dart` navigation menu~~ (superseded by 2.6)
- [x] 2.3 Remove settings icon button from `chat_page.dart` app bar actions
- [x] 2.4 Remove settings icon button from `agentic_chat_page.dart` app bar actions
- [x] 2.5 Replace `PopupMenuButton` in `chat_page.dart` with `NavigationDrawer` via `Scaffold.drawer` — entries: Chat (selected), Settings, About. Use `NavigationDrawerDestination` with standard selected state (no checkmark)
- [x] 2.6 Replace `PopupMenuButton` in `agentic_chat_page.dart` with `NavigationDrawer` via `Scaffold.drawer` — entries: Chat (selected), Sessions, Settings, About. Use `NavigationDrawerDestination` with standard selected state

## 3. Connection Error Banner Retry Button

- [x] 3.1 Add "Retry" `OutlinedButton` next to "Check Settings" in `chat_page.dart` `_buildHealthCheckBanner`, calling `performImmediateHealthCheck()` and resetting banner dismissal
- [x] 3.2 Add "Retry" `OutlinedButton` next to "Check Settings" in `agentic_chat_page.dart` `_buildHealthCheckBanner`, calling `triggerHealthCheck()` and resetting banner dismissal

## 4. Conditional Health Checks

- [x] 4.1 Add backend type guard in `HealthCheckNotifier._performHealthCheck()` — skip if `selectedBackend` is not `openAiCompatible`
- [x] 4.2 Add backend type guard in `EngineHealthCheckNotifier.triggerHealthCheck()` — skip if `selectedBackend` is not `relagentEngine`

## 5. Fix Settings Input Value Swapping

- [x] 5.1 Add `ValueKey` on both OpenAI `Autocomplete` widgets (base URL and model) in `settings_page.dart` so they fully dispose on backend switch
- [x] 5.2 Add `ValueKey` on the engine URL `Autocomplete` widget in `settings_page.dart`

## 6. About Page Backend Info

- [x] 6.1 Convert `InfoPage` from `StatelessWidget` to `ConsumerWidget`, add import for `settingsProvider` and `engineHealthCheckProvider`
- [x] 6.2 Add "Chat Backend" card showing "OpenAI-compatible" or "Relagent Engine" based on `selectedBackend`
- [x] 6.3 Add "Base URL" card showing the active backend's configured URL
- [x] 6.4 Add "Engine Version" card (only when engine backend is active and `engineHealthCheckProvider` has a successful result with `engineVersion`)
- [x] 6.5 Add app icon (minion) from `assets/icon/app-icon.png` at the top of the about page, consistent with splash screen style

## 7. Consistent Settings Save Behavior

- [x] 7.1 Remove `_saveSettings()` from `onEditingComplete` on the model name `Autocomplete` field in `settings_page.dart`
- [x] 7.2 Change model name field `textInputAction` from `TextInputAction.done` to `TextInputAction.next` so Enter/Tab moves to next field

## 8. Engine Base URL Change Resets State

- [x] 8.1 Add `clearLastEventId()` method to `SseNotifier` that removes the `sse_last_event_id` key from SharedPreferences
- [x] 8.2 In `SettingsNotifier.updateEngineBaseUrl()`, when URL actually changed: call `clearAgenticSessionId()`, clear SSE last event ID, clear engine health check result, clear sessions state
- [x] 8.3 Expose engine state reset via refs accessible from `SettingsNotifier` (SSE provider, engine health check provider, sessions provider)

## 9. Health Check Recovery Triggers Data Reload

- [x] 9.1 In `agentic_chat_page.dart`, add `ref.listen` on `engineHealthCheckProvider` to detect fail→success transition: dismiss banner, trigger `loadHistory()` and SSE `reconnect()`
- [x] 9.2 In `chat_page.dart`, add `ref.listen` on `healthCheckProvider` to detect fail→success transition: dismiss banner

## 10. Android App Icon Cropping Fix

- [x] 10.1 Revert `ic_launcher.xml` to use `<foreground android:drawable="@drawable/ic_launcher_foreground"/>` without the 16% inset wrapper

## 11. Verification

- [x] 11.1 Run `dart-flutter_analyze_files` and fix any analysis issues
- [x] 11.2 Run `dart-flutter_run_tests` and verify all tests pass
