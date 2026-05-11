## Context

The engine persists `sensitivity_level` in `ChatContext` and already returns it in `ChatResponse` (POST /messages, POST /continue). However `MessagesResponse` (GET /messages) omits it, so the Flutter app has no way to restore the level when loading session history. The app's `AgenticChatState` defaults to `Personal` on every load, making the indicator unreliable and approval mismatch banners potentially wrong.

## Goals / Non-Goals

**Goals:**
- `GET /messages/{id}` returns `sensitivity_level` alongside messages
- `loadHistory()` applies the returned level to state on both full-load and incremental paths
- No regression on the existing `ChatResponse` sensitivity path

**Non-Goals:**
- Changing how sensitivity is set (PUT endpoint unchanged)
- Handling the new-session / pre-first-message timing edge case (separate concern)
- Modifying `SessionInfo` or the `GET /sessions/{id}` endpoint

## Decisions

**Add `sensitivity_level` to `MessagesResponse`, not to `SessionInfo`**

The app already calls `GET /messages` on every session load; it would need a second call if the field lived on `SessionInfo`. Putting it in `MessagesResponse` is zero extra round-trips and mirrors how `ChatResponse` already carries sensitivity alongside messages. `SessionInfo` is metadata-only by design.

**Apply sensitivity on both load paths in `loadHistory()`**

The full-load path (no `afterMessageId`) and the incremental path (`afterMessageId` set) both call the same endpoint. Both should apply the returned level so an incremental SSE-driven refresh doesn't accidentally reset state to default.

**Only apply when level is present (null-safe)**

`MessagesResponse.sensitivity_level` is optional so older engine versions without the field don't break existing clients. Flutter reads it only when non-null.

**Send `sensitivity_level` in `POST /messages` for new sessions, not via pre-created empty session**

When no session exists yet, `changeSensitivity()` cannot call `PUT /sensitivity` (no session ID). An alternative — creating an empty session eagerly on sensitivity change — would pollute the session list with untitled orphan sessions and require a new `POST /sessions` endpoint. Instead, including the desired level as an optional field in `ChatRequest` lets the engine apply it before the first cycle runs. No new endpoint, no orphans, contained to a single optional field. Only sent when `sessionId` is null (new sessions); existing sessions already have their level persisted.

## Risks / Trade-offs

- **Stale incremental sensitivity** — an incremental fetch reflects the level at that moment, which could theoretically differ from state if the user changed it concurrently. Acceptable: the engine is the source of truth and overwriting with the current engine value is correct.
- **No regression guard on `ChatResponse` path** — not touching that path; existing test coverage holds.
