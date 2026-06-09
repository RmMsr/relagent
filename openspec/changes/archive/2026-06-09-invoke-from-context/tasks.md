## 1. Dependency

- [x] 1.1 Add `receive_sharing_intent` to `apps/pubspec.yaml` and run `fvm flutter pub get`

## 2. Android Manifest

- [x] 2.1 Add `ACTION_SEND` / `text/plain` intent-filter to `MainActivity` in `AndroidManifest.xml`
- [x] 2.2 Add `ACTION_PROCESS_TEXT` intent-filter to `MainActivity` in `AndroidManifest.xml`

## 3. Platform Channel — PROCESS_TEXT

- [x] 3.1 Add a `MethodChannel` in `MainActivity.kt` that reads `Intent.EXTRA_PROCESS_TEXT` on `onCreate` and `onNewIntent` and sends the text to Dart
- [x] 3.2 Add the Dart-side channel listener that receives the text from the platform

## 4. Pending Invocation Holder

- [x] 4.1 Create `lib/providers/invocation_provider.dart` — a `NotifierProvider` holding `String?` (the pending text); expose `set(text)` and `consume()` methods

## 5. Intent Reception — Dart Layer

- [x] 5.1 In `lib/main.dart` (or a dedicated init helper), initialise `receive_sharing_intent` for cold-start and warm-intent streams; on text received, call `invocationProvider.notifier.set(text)`
- [x] 5.2 Wire the PROCESS_TEXT platform channel listener (from 3.2) to call `invocationProvider.notifier.set(text)`

## 6. Invocation Screen

- [x] 6.1 Create `lib/pages/invocation_page.dart` with a single `TextField` pre-filled with `"please explain\n\n"` + blockquote-formatted received text (`> ` per line)
- [x] 6.2 Pre-select the `"please explain"` portion on first render so first keystroke replaces it; raise keyboard automatically
- [x] 6.3 Add Send button: calls `agenticChatProvider.notifier.clearChat()`, then `sendMessage(fieldText)`, then `context.go('/chat')`
- [x] 6.4 Add Cancel/Dismiss action: navigates to `/chat` without sending

## 7. Routing

- [x] 7.1 Add `/invoke` route to `app_router.dart` pointing to `InvocationPage`
- [x] 7.2 Update `SplashPage._navigateAfterDelay()` to check `invocationProvider` after the delay: route to `/invoke` if pending, `/chat` otherwise

## 8. Verification

- [x] 8.1 Test cold-start via share sheet: share text from another app → splash → invocation screen pre-filled correctly
- [x] 8.2 Test cold-start via text-selection menu: select text → "Ask Relagent" → invocation screen
- [x] 8.3 Test warm share: app already open, share text → invocation screen appears, existing session discarded on Send
- [x] 8.4 Test Cancel: dismiss invocation screen → lands on chat page, no new session started
- [x] 8.5 Test empty instruction: clear instruction, Send → chat receives blockquote-only message
- [x] 8.6 Run `dart-flutter_analyze_files` and fix all issues
