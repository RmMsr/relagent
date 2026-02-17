## Why

Three reliability bugs in the SSE event handling cause inconsistent state across devices and on the sending device itself: (1) session title not rendered on the chat page after creating a new session, (2) messages sent from one device not reliably appearing on another device with the same session open, and (3) duplicate messages appearing when the same session receives messages from multiple devices.

## What Changes

- **Fix `session.created` handler missing chat title update**: The `session.created` SSE handler updates the sessions list but never calls `loadSessionInfo()` on the `agenticChatProvider`, so the chat page title stays empty. The `session.updated` handler already does this correctly — the same pattern needs to apply to `session.created`.
- **Fix SSE reconnection resource leak**: On reconnect, `SseClient._doConnect()` creates a new `http.Client` without closing the old one or cancelling the old stream subscription. This can cause dangling connections and missed events.
- **Fix SSE connection lost after app backgrounding**: After 10 failed reconnect attempts, the SSE client gives up permanently. When the mobile app resumes from background, nothing re-triggers `connect()`, so events are never received again.
- **Fix duplicate messages on incremental history load**: `AgenticChatNotifier.loadHistory(fromId:)` appends fetched messages without checking if they already exist locally. When two devices both send messages to the same session, the SSE `messages.appended` event triggers a fetch that may return messages already present from the local POST response.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `app-event-handling`: `session.created` events must trigger chat page title refresh for the active session (same as `session.updated` already does)
- `async-notifications`: SSE client must clean up resources on reconnect, handle app lifecycle resume, and reset reconnect attempts on resume
- `agentic-chat`: Incremental history loading must deduplicate messages against locally present messages

## Impact

- **App SSE client** (`apps/lib/agentic/sse_client.dart`): Resource cleanup in `_doConnect()`, reconnect attempt reset
- **App SSE provider** (`apps/lib/providers/sse_provider.dart`): Add `loadSessionInfo()` call in `session.created` handler
- **App agentic chat provider** (`apps/lib/providers/agentic_chat_provider.dart`): Deduplicate messages in `loadHistory(fromId:)`
- **App chat page** (`apps/lib/pages/agentic_chat_page.dart`): Add app lifecycle observer to reconnect SSE on resume
