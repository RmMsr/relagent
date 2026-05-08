## Why

Today the engine identifies messages by `sequence_id: int`, which conflates three separate concerns: identity (which message is this?), ordering (which comes first?), and incremental-fetch cursor (give me everything after id N). On the app side, multiple ingestion paths (`sendMessage` POST response, `loadHistory` full and incremental, `triggerContinuation`, `stopCycle`, `retryFailedMessages`, optimistic local user message, error message) each append or merge into chat state with subtly different rules. The mismatch shows up as duplicates and order glitches when the same session is touched from multiple devices or when network errors trigger retries — `fix-sse-event-reliability` patched the most acute symptom (incremental-load duplicates) but the underlying invariant ("a message has one identity, every addition goes through one merge") is still informal.

This change makes the invariant structural: every message carries a UUID `message_id`, the user message is given its UUID by the app at construction time and POST is idempotent on it, and the app routes every addition through a single ingest function whose contract is "skip-if-known-and-final, replace-if-known-and-non-final, append-if-new."

## What Changes

- **Engine domain**: Add `message_id: UUID` to `UserMessage`, `AssistantMessage`, `SystemAction`. Remove `sequence_id` from the domain entirely; ordering becomes a pure persistence concern handled by the SQLite store's auto-increment primary key.
- **Engine API**: `GET /sessions/{id}/messages?after=<uuid>` replaces `?from_id=<int>`. `POST /sessions/{id}/messages` accepts a body with `message_id`; a POST whose UUID already exists is idempotent and returns the prior cycle response. `MessagesAppendedEvent` becomes notification-only (drops `latest_sequence_id`).
- **Engine backwards-compat**: When loading a stored row whose `message_id` column is NULL, the persistence adapter mints a UUID and persists it via a single UPDATE before returning (required for domain identity). For missing `final` (assume `true`), no write-back is performed — cases where this differs are close to zero. Both paths are annotated with `# BACKWARD COMPAT:` comments and are removable post-cutover.
- **App models**: `AgenticMessage.id: int?` is replaced by `messageId: String` (non-nullable). User-message and error factories generate UUIDs at construction time. `localId` is unchanged (separate UI concern).
- **App ingest function**: `_mergeRefresh` is renamed to `_ingestMessages` and becomes the only path that mutates `state.messages`. All addition sites (`sendMessage`, `loadHistory`, `triggerContinuation`, `stopCycle`, `retryFailedMessages`, optimistic user message, errors) are routed through it.
- **App SSE flow**: `MessageEventDedup` is removed. The cursor for incremental fetch is `state.messages.lastWhere((m) => m.isFinal)?.messageId`. Fetch coalescing is replaced by a `_fetchInFlight` / `_refetchPending` pair. The `messages.appended` event handler triggers `fetchSinceCursor()`.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `agentic-chat`: Persistent message IDs become UUIDs assigned by the engine (assistant/system) or the app (user/error); message history loading uses a UUID cursor; sending a user message is idempotent on `message_id`.
- `async-notifications`: `session.messages.appended` event payload drops `latest_sequence_id` and becomes notification-only.
- `message-finalization`: The engine references cycles internally by the cycle-opening `UserMessage`'s `message_id` (UUID) rather than `sequence_id`; settlement events become notification-only (no per-cycle identifier in the event payload — clients reload using their own cursor and the ingest function reconciles changes); the read-time default for missing `final` self-heals via a write-on-read instead of staying read-only.

## Impact

- **Engine domain models** (`engine/domain/models.py`): add `message_id` to `UserMessage`, `AssistantMessage`, `SystemAction`; remove `sequence_id` and `ChatContext._next_sequence_id`.
- **Engine domain services** (`engine/domain/services.py`, `immutability.py`, `exceptions.py`): rewrite anything keyed on `sequence_id` to key on `message_id`.
- **Engine persistence** (`engine/adapters/.../sqlite_event_store.py`): `message_id` column with index; `messages_after(session_id, uuid)` query; self-healing reads for NULL `message_id` and NULL `final`.
- **Engine API** (`engine/api/v1.py`): `?after=<uuid>` query param; `POST /messages` accepts and dedupes by `message_id`.
- **Engine SSE events** (`engine/api/events.py`, `engine/domain/ports/events.py`): drop `latest_sequence_id` from messages.appended.
- **App models** (`apps/lib/agentic/models.dart`): non-nullable `messageId`; user/error factories generate UUID.
- **App services** (`apps/lib/agentic/services.dart`): send/load/continue/stop methods take and return UUIDs; `?after=` query.
- **App agentic chat provider** (`apps/lib/providers/agentic_chat_provider.dart`): `_ingestMessages` as sole mutator; all ingestion paths re-routed; `retryFailedMessages` simplified.
- **App SSE provider** (`apps/lib/providers/sse_provider.dart`): remove `MessageEventDedup`; `fetchSinceCursor` with in-flight/pending booleans.
- **App SSE event model** (`apps/lib/agentic/sse_client.dart`): `MessagesAppendedEvent` drops `latestSequenceId`.
- **Tests**: update engine domain/adapter/api tests and app model/provider/sse tests to match.

This change supersedes the merge-by-sequence-id logic introduced by `fix-sse-event-reliability` task 4. It should land after that change.
