## 1. Fix session.created missing title update

- [x] 1.1 In `SseNotifier._handleEvent`, add `loadSessionInfo()` call in the `SessionCreatedEvent` handler when the event's sessionId matches the active session — re-reading `currentSessionId` from settings at comparison time
- [ ] 1.2 Verify: send first message to create a new session, confirm title appears on chat page without navigating away

## 2. Fix SSE client resource cleanup on reconnect

- [x] 2.1 In `SseClient._doConnect()`, cancel the old `_subscription` and close the old `_client` (if not injected) before creating new ones
- [ ] 2.2 Verify: trigger a reconnect (e.g., kill server briefly), confirm no dangling connections and events resume after server restarts

## 3. Fix SSE connection lost after app backgrounding

- [x] 3.1 Add `WidgetsBindingObserver` to the chat page that calls `sseProvider.notifier.connect()` on `AppLifecycleState.resumed`
- [x] 3.2 In `SseClient.connect()`, reset `_reconnectAttempts` to 0 so a fresh connect after resume is not blocked by previous failed attempts
- [ ] 3.3 Verify: background app for extended period, resume, confirm SSE events are received again

## 4. Fix duplicate messages on incremental history load

- [x] 4.1 In `AgenticChatNotifier.loadHistory(fromId:)`, filter out fetched messages whose `id` already exists in `state.messages` before appending
- [ ] 4.2 Verify: send messages from two devices to the same session, confirm no duplicates appear on either device
