## Why

Concurrent requests on the same session can corrupt the message history.
Phoenix trace `27d80f45f403fbecfca0256c67d13143` captured a 500 error:
`pydantic_ai.UserError: Cannot provide a new user prompt when the message
history contains unprocessed tool calls.`

The error occurs because a user message was appended between a `SystemAction`
(tool approval) and its eventual `AssistantMessage` response. The history
reconstruction in `_get_known_history_from_messages` assumes a resolved
`SystemAction` is followed by an `AssistantMessage`; the interleaved user
message breaks that invariant and produces a `ModelResponse` with dangling
`ToolCallPart`s. The next request then carries a `user_prompt` alongside
those unprocessed tool calls, which pydantic_ai rejects.

The persisted state has no marker indicating that an agent run is in
progress, so a second request loading the context cannot tell a completed
cycle from one still being generated. The fix requires explicit
coordination across concurrent requests for the same session.

This change is the **short-term, minimal-surface fix**. It introduces a
per-session lock without changing public APIs, message models, or the
overall request/response architecture. A separate change
(`decouple-message-acceptance-from-response`) covers the longer-term
redesign.

## What Changes

- Add a per-session lock to the `Persistence` port:
  `context_lock(session_id) -> AbstractContextManager`. The lock is
  acquired at the start of a request handler and released when the
  handler returns.
- Wrap the read–run–write sequence in `ChatService.perform_user_input`
  and `ChatService.continue_session` with the per-session lock. The
  lock spans `load context → run agent → save context`.
- Concurrent requests for the **same session** SHALL block until the
  previous request completes; concurrent requests for **different
  sessions** SHALL NOT block each other.
- The lock is **not** held across the user-approval gap. When
  `perform_user_input` returns a `SystemAction` requesting approval,
  the lock is released. The next call (`continue_session` after
  approval, or another `perform_user_input`) re-acquires it.
- Event publishing (`_publish_*`) happens after the lock is released to
  avoid holding the lock during external I/O.

### Out of Scope

- No change to API contracts, request/response shapes, or message models.
- No change to the agent execution adapter — the existing
  trailing-approvals logic and history reconstruction are left as-is.
  With the lock in place, the invariants those routines assume hold by
  construction.
- No async/event-driven response delivery (covered by a separate change).

### Trade-off Accepted

If a user sends two messages in quick succession on the same session,
the second blocks for the duration of the first agent run (1–8 seconds
based on observed traces). This is acceptable as a stopgap; it is
strictly better than the current behavior, which is either a 500 error
or a corrupted history. The follow-up change addresses this UX cost.

## Capabilities

### New Capabilities

- `session-concurrency-control`: per-session serialization of context
  reads and writes, ensuring agent runs and message appends for the
  same session happen one at a time while different sessions remain
  independent.

### Modified Capabilities

None. The behavior change is observable only as "concurrent requests on
the same session now wait their turn instead of corrupting state"; no
existing requirement is being redefined.

## Impact

- **`engine/domain/ports/persistence.py`**: add `context_lock` method
  to the `Persistence` protocol.
- **`engine/adapters/persistence/`**: implement `context_lock` in the
  concrete adapter(s). Mechanism choice is an implementation detail of
  the adapter — likely an in-memory `asyncio.Lock` per session
  (sufficient for single-process deployments) with the option to layer
  `portalocker` for multi-process safety later.
- **`engine/domain/services.py`**: wrap `perform_user_input` and
  `continue_session` bodies with the lock; move event publishing
  outside the locked region.
- **Tests**: new integration tests exercising
  - concurrent requests on the same session (must serialize and produce
    a coherent final state),
  - concurrent requests on different sessions (must not block),
  - lock release on exception (must not deadlock subsequent requests).
- **No API contract change**; only timing behavior shifts.
- **No new external dependency** if `asyncio.Lock` is the chosen
  implementation. `portalocker` is opt-in for future multi-process
  deployments.
