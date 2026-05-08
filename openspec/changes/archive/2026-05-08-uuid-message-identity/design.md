## Context

The current message identity (`sequence_id: int`) carries three meanings: (1) which message this is, (2) what order it sits in within the session, and (3) the cursor for incremental fetch (`?from_id=N`). The app side has multiple ingestion paths, each with its own append/merge semantics — `sendMessage` blindly appends the POST response, `loadHistory(fromId:)` calls `_mergeRefresh` (which already implements skip-final / replace-non-final / append-new keyed on sequence_id), `triggerContinuation` blindly appends, `stopCycle` merges, `retryFailedMessages` walks the tail looking for `id == null` user messages. Optimistic local user messages have `id == null` until the POST returns, which is a special case in every path that touches them.

`fix-sse-event-reliability` patched the most visible duplicate-message bug by adding the merge to incremental load. It was the right tactical fix but did not change the underlying invariant: there are still many ways to add messages, identity is still nullable for one path, and the fetch cursor is still an int.

This change makes the invariant structural by giving every message a UUID `message_id`, requiring it to be set at the moment of creation (client for user/error, server for assistant/system), routing every addition through a single ingest function, and replacing the int cursor with a UUID cursor based on the last final message.

## Goals / Non-Goals

**Goals:**

- Every message has a stable, non-nullable UUID identity from creation.
- The app has exactly one function that mutates the message list, with a clear contract.
- Sending a user message is idempotent on its UUID — retry after a lost response cannot duplicate.
- Incremental fetch uses the UUID of the last known *final* message as cursor; non-final entries are always re-fetched and replaced.
- Existing engine sessions remain readable and resumable across the cutover via self-healing reads.

**Non-Goals:**

- Strict cross-device ordering for unsettled cycles. In a multi-device write-during-write race, an optimistic local user message can briefly display in the wrong relative position against another device's incoming messages. The order self-corrects once the cycle settles and `lastFinal` advances. v1 accepts this.
- Removing the backward-compat self-healing paths. They are annotated for later removal in a follow-up cleanup change.
- Changing the SSE protocol itself (still SSE, still `Last-Event-ID` for stream replay, still session-scoped events). Only the `messages.appended` payload contracts.
- Multi-message POST. The current POST takes one user message; that stays.

## Decisions

### 1. Message identity is a UUID, not an integer

`message_id: UUID` is added to `UserMessage`, `AssistantMessage`, `SystemAction`. `sequence_id` is removed from the domain. Ordering moves to the persistence adapter (SQLite auto-increment primary key on the message rows). Domain code never names the persistence ordering key.

**Alternatives considered:**
- *Keep `sequence_id` internally for ordering, add UUID for identity.* Rejected: still a domain field, still needs to be assigned and threaded through every code path, creates confusion about which field is canonical when both are present.
- *Use `timestamp` for ordering.* Rejected: timestamps from concurrent writes can collide; clocks drift; relying on timestamps as a sort key means storing them at higher precision than they need to be for display.

### 2. UUID cursor for incremental fetch, anchored at last final

The app's cursor for `GET /sessions/{id}/messages?after=<uuid>` is `state.messages.lastWhere((m) => m.isFinal, orElse: () => null)?.messageId`. If null (empty or no final yet), the call is a full fetch.

Non-final messages are mutable by definition — the engine may add new messages or change content during an unsettled cycle. Re-fetching non-final entries on every notification is **desired behavior**, not a drawback. The engine returns everything strictly after the cursor row in insertion order; the app's ingest function replaces non-finals in place by UUID and appends new entries.

**Alternatives considered:**
- *Cursor = last engine-confirmed message UUID.* Required tracking a `confirmedByEngine` flag on every message. Rejected: extra field, extra branch in retry, extra branch in ingest. The "last final" formulation does the same job for free.
- *Always full fetch on every notification.* Rejected: O(N) bandwidth on every event, scales poorly as sessions grow.

### 3. Idempotent user-message POST keyed on UUID

The app generates the user message's UUID at construction time (in `AgenticMessage.user(text)`), includes it in the POST body, and the engine treats a POST whose `message_id` already exists as idempotent: it does not insert a new row, does not start a new cycle, and returns the prior cycle response.

This collapses several existing edge cases:
- The "id == null until POST returns" state on local user messages goes away.
- `retryFailedMessages` no longer needs to track which messages "have an engine id" — it just resends; the engine deduplicates.
- The duplicate-on-retry hazard described in `fix-sse-event-reliability` issue 3 is structurally prevented.

### 4. Single ingestion function on the app side

`AgenticChatNotifier._ingestMessages(List<AgenticMessage> incoming)` is the only function that mutates `state.messages`. Its contract:

- For each incoming message, look up its `messageId` in current state.
- *Not present*: append at the end, preserving incoming order.
- *Present and current entry is `final=true`*: skip — final is immutable.
- *Present and current entry is `final=false`*: replace in place at the existing index.
- Set `state = state.copyWith(messages: out)` once at the end of the call.

Every code path that adds to chat state uses this function: full and incremental `loadHistory`, the optimistic local user message in `sendMessage`, the POST response, the `triggerContinuation` response, the `stopCycle` settled list, errors, `retryFailedMessages` re-issued sends.

The invariant is enforced by convention, not by the type system. We considered extracting a `MessageList` value type whose only mutator is `ingest`, but elected the lighter-weight rename for v1. If duplications come back, the structural enforcement is the right next step.

### 5. SSE flow simplification

`MessageEventDedup` is removed. The notifier holds `_fetchInFlight: bool` and `_refetchPending: bool`. On a `messages.appended` event for the active session:

- If `_fetchInFlight`, set `_refetchPending = true` and return.
- Else set `_fetchInFlight = true`, fetch with the cursor, ingest, clear `_fetchInFlight`. If `_refetchPending` was set during the fetch, clear it and recurse once.

The merge being idempotent means this is correct under any interleaving — overlapping rows from a refetch hit the "skip-if-known-and-final" or "replace-if-known-and-non-final" branches and converge.

### 6. Backwards-compat handling on the engine

Two separate fallback paths for rows written before this change:

**`message_id` NULL → mint + persist.** When the SQLite event store loads a row whose `message_id` column is NULL, it mints a UUID, executes a single UPDATE on that row to persist it, and returns the message with the freshly minted ID. This is necessary because message identity is required for the new domain model. Code path carries a `# BACKWARD COMPAT:` comment (e.g., "remove once all stored rows have non-NULL message_id").

**`final` NULL → read-only `true`.** When the `final` column is NULL, the persisted model assumes `final=true` and returns it in-memory without writing back. The cases where this differs from the truth are close to zero, so a write-back is unnecessary. Code path carries a `# BACKWARD COMPAT:` comment (e.g., "remove once all stored rows have non-NULL final").

This avoids a stop-the-world migration job while keeping the read paths correct.

## Risks / Trade-offs

- **Convention-based ingestion (Decision 4) is bypassable.** Any code can still call `state = state.copyWith(messages: ...)` directly inside the notifier. Mitigation: code review on PRs touching this file; if duplicates recur, escalate to a `MessageList` value type.
- **Eventually consistent ordering across devices (Goals).** Optimistic local user messages can briefly display in the wrong relative position against incoming messages from another device on the same session. Multi-device usage is a rare edge case; eventual consistency mid-term is the priority. Self-corrects once the cycle settles.
- **`final` NULL → read-only `true` (Decision 6).** Cases where this differs from the truth are close to zero, so no write-back is performed. No migration job needed.
- **`message_id` NULL → mint + persist (Decision 6).** Bounded writes (one UPDATE per row, on first read after cutover). Idempotent and necessary for domain identity.
- **POST idempotency requires lookup on every send (Decision 3).** Adds an indexed lookup on `message_id` per POST. Negligible at expected volumes. Mitigation: index on `message_id`.
- **Sequencing against `fix-sse-event-reliability`.** This change replaces task 4 of that one. If both are open simultaneously, this change must rebase onto whatever task 4 lands; conversely, task 4 should not be backed out by this change — it stays in the history.
