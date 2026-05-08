## Context

The app uses SSE (Server-Sent Events) to receive real-time notifications from the engine. The SSE client connects on chat page init, parses events, and dispatches them to providers. Three bugs have been identified through multi-device testing:

1. The `session.created` handler in `SseNotifier._handleEvent` updates the sessions list but does not refresh the chat page title — unlike the `session.updated` handler which does.
2. The `SseClient._doConnect()` reconnect path creates a new `http.Client` without cleaning up the previous one. Combined with no app lifecycle handling, the mobile app can permanently lose its SSE connection after backgrounding.
3. `AgenticChatNotifier.loadHistory(fromId:)` blindly appends fetched messages without checking for duplicates against messages already present locally (e.g., from the POST response on the sending device).

## Goals / Non-Goals

**Goals:**
- Session title appears on chat page after first message creates a new session
- SSE connection reliably survives app backgrounding/resuming on mobile
- No duplicate messages when the same session is used from multiple devices

**Non-Goals:**
- Changing the SSE protocol or event format
- Adding new event types
- Handling SSE for sessions not currently active (messages.appended for non-active sessions is correctly ignored)
- Server-side changes — all fixes are app-side

## Decisions

### 1. Add `loadSessionInfo()` to `session.created` handler

The `session.created` case in `_handleEvent` will call `loadSessionInfo()` on the `agenticChatProvider` when the event's `sessionId` matches the active session — identical to what `session.updated` already does. The `currentSessionId` must be re-read from settings at comparison time rather than using the value captured at the top of `_handleEvent`, because for new sessions the session ID is stored asynchronously by `sendMessage()` and may not yet be set when `_handleEvent` starts.

**Alternative considered**: Having `sendMessage()` directly call `loadSessionInfo()` after storing the session ID. Rejected because the title may not be ready yet when the POST response returns (title generation is async on the engine side and happens before the response, but future changes could alter this). The SSE event is the authoritative signal.

### 2. Clean up resources in `_doConnect()` before reconnecting

Add cleanup of the old `_subscription` and `_client` at the start of `_doConnect()`, before creating new ones. This prevents dangling HTTP connections and duplicate stream listeners. Only the injected test client is excluded from closing.

### 3. Add app lifecycle observer to reconnect SSE

The chat page already has `initState` calling `connect()`. Add `WidgetsBindingObserver` to detect `AppLifecycleState.resumed` and re-trigger `connect()`. This covers the case where the OS kills the TCP connection while backgrounded and all 10 reconnect attempts are exhausted before the app resumes.

The `SseNotifier.connect()` method already handles re-initialization cleanly (cancels old subscription, disposes old client, resets dedup state), so calling it on resume is safe.

Additionally, `SseClient` needs a `resetReconnectAttempts()` method (or `connect()` needs to reset the counter) so that a fresh `connect()` after resume doesn't immediately hit the max attempts limit.

### 4. Deduplicate messages by sequence ID in `loadHistory()` — SUPERSEDED

**Superseded by `uuid-message-identity`** — that change removes `sequence_id` from domain models and routes all ingestion through `_ingestMessages` with built-in dedup. This task's sequence-id-based approach will not work after uuid-message-identity lands.

~~When `loadHistory(fromId:)` appends messages incrementally, filter out any messages whose `id` (sequence ID) already exists in `state.messages`. This uses the existing `AgenticMessage.id` field which maps to the engine's `sequence_id`. Messages without an ID (locally-created user messages before POST response) are never duplicated by this path since they don't come from the engine fetch.~~

**Alternative considered**: Replacing all messages on every fetch instead of appending. Rejected because it would lose locally-added messages that haven't been confirmed by the engine yet (e.g., the optimistic user message added in `sendMessage()`).

## Risks / Trade-offs

- **Re-reading `currentSessionId` in `session.created` handler**: Adds a second `ref.read(settingsProvider)` call. Minimal cost, but creates a slight inconsistency with other handlers that use the captured value. Acceptable because only `session.created` has this timing issue.
- **Lifecycle observer on chat page**: If the chat page is disposed and recreated on resume (depending on OS behavior), `initState` already calls `connect()`. The lifecycle observer is a belt-and-suspenders approach — `connect()` is idempotent so double-calling is safe.
- **Dedup by sequence ID**: Assumes sequence IDs are unique within a session. This is guaranteed by the engine's `_add_messages_to_context_with_sequence_ids` implementation.
