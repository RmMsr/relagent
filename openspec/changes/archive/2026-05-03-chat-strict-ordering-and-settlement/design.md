## Context

The chat backend (Python/FastAPI + pydantic_ai) and the Flutter
client today treat each user message as an independent request:
the client sends a message, waits for the response synchronously,
and the engine runs the agent during that window. The data model
allows a `SystemAction` (an approval prompt) to sit in history
without an immediately-following `AssistantMessage`, and the
history reconstruction in
`engine/adapters/pydantic_ai_execution/queries.py` assumes the
opposite invariant.

This design replaces the implicit "messages are independent" model
with an explicit one: each cycle has a strict beginning (a user
message) and a strict end (a settlement event), and only one cycle
can be in flight per session at any time. The client enforces the
in-flight cap; the engine reflects it in the data model via a
universal `final: bool` flag and a new Stop endpoint.

The proposal (`proposal.md`) covers the user-visible behavior. This
document focuses on the technical decisions behind that behavior.

## Goals / Non-Goals

**Goals:**

- A persisted, machine-checkable distinction between in-flight and
  settled state, with single-bit overhead per message.
- Single source of truth for "is this cycle done?" — no need to
  reason about the relative order of `SystemAction`s and
  `AssistantMessage`s to answer it.
- Engine API endpoints that each have one responsibility (state
  change vs. message generation), with no implicit side effects.
- Client UI affordances that visually match the underlying state
  (sent vs. queued vs. settled) and never let the user act in ways
  the engine cannot honor.
- Make the original trace bug
  (`27d80f45f403fbecfca0256c67d13143`) structurally impossible —
  the conditions for it cannot arise under the new model when both
  client and server are at the new version.

**Non-Goals:**

- Multi-device or multi-tab coordination of the client queue. v1
  assumes one active client per session.
- Cross-process or cross-worker engine concurrency control. Adding
  a session lock to the persistence port is a defensive measure we
  may revisit, but it is not required to make the new model
  correct under single-client use.
- Streaming partial assistant responses. The `final=true` invariant
  for `AssistantMessage` would need revisiting if streaming is
  added later.
- Backfilling rich data on existing persisted messages — they are
  treated as fully settled history at migration time.

## Decisions

### D1. Single `final` flag on every message, instead of separate state per type

**Decision:** Add `final: bool` to `UserMessage`,
`AssistantMessage`, and `SystemAction` uniformly.

**Why:** The earlier design sketch had `cycle_state: pending |
resolved | stopped` only on `SystemAction`, and an implicit notion
that user messages were "settled when an assistant response
arrived." This left readers to infer state from neighbouring
messages — the same pattern that made
`_get_known_history_from_messages` brittle.

A uniform `final` flag makes "is this in-flight?" a local question
on each message. The settlement *event* (an `AssistantMessage`
append, or a Stop) is a *transition* that flips the flag on every
preceding in-flight message back to and including the user message
that opened the cycle.

**Alternatives considered:**

- Per-type state fields (e.g., `Approval.granted` plus
  `SystemAction.cycle_state` plus implied user-message state):
  rejected because it scatters the concept and makes consistency
  rules implicit.
- A separate "cycle" entity with its own state: rejected as
  over-engineering for v1; the user message naturally identifies
  the cycle and a single flag per message is enough.

### D2. Stop is a mutation of in-flight state, not an appended marker

**Decision:** When the user clicks Stop, the engine mutates the
trailing in-flight `SystemAction`(s): undecided approvals are set
to `granted=false`, `SystemAction.final=true`, and the user
message that opened the cycle has `final=true`. No new record is
appended to history.

**Why:** Appending a "stopped" marker would create a two-record
relationship (the original approval `SystemAction` plus a stop
record) that readers must traverse together. The marker also adds
a record type whose only job is to communicate state that's
already representable by the existing fields.

The settled state — declined approvals on a final `SystemAction`,
no following `AssistantMessage`, all messages `final` — is
self-describing and enough for downstream readers.

**Alternatives considered:**

- Append `SystemAction(notification="Stopped", final=true)`:
  cleaner audit trail (append-only), but adds a record type and
  forces readers to interpret the pair. Rejected for the
  parsimony reason above.
- Add `outcome: response | stopped` to the user message: similar
  redundancy with the `final` flag and approval state — already
  derivable.

### D3. Engine API: separate state-change and message-generation endpoints; client orchestrates

**Decision:** `/grant`, `/decline`, and `/stop` are pure state-
change endpoints (no message in body, no side effects on the
agent). Existing `/continue` remains the only way to drive the
agent's next iteration. The client decides when to call
`/continue` after collecting per-card decisions.

**Why:** Mixing state changes with agent-generation has been a
source of confusion in the existing API (`/grants` accepts a grant
but doesn't run the agent; `/continue` does). Splitting cleanly:

- `/grant`, `/decline`, `/stop` → state changes. Easy to reason
  about, idempotent, no side effects on conversation flow.
- `/continue` → drives the agent. Returns a message. Same as
  `/messages` in that respect.

The "all decided → continue" check is client-side because the
client is the only place that knows the user's intent in real
time (e.g., the user might want to inspect the SystemAction
before triggering continuation). It also keeps the engine
endpoints simple — no auto-continuation timer to worry about,
no question of "what if a grant arrives during a continuation."

**Alternatives considered:**

- Engine auto-continues when all approvals are decided: rejected
  because it adds an implicit transition that can race with
  other client actions (e.g., a pending Stop). Also forces the
  engine to know about partial-approval workflows.
- Combined endpoint (e.g., `POST /approvals/{id}/decide` with body
  `{decision, also_continue}`): rejected because it re-couples
  state change and agent execution, just behind a flag.

### D4. Single queued message, with edit-as-pull-back semantics

**Decision:** The client allows at most one queued message. The
"edit queued" affordance removes it from the chat list and
reloads its text into the input. Submitting again (after the in-
flight cycle settles) re-queues or re-sends.

**Why:** Multi-queue raises questions the v1 model doesn't need
to answer: can the user reorder drafts? edit a non-trailing one?
what does it look like when the engine settles a message and the
queue advances by one? Keeping it to a single queued message
gives a clear UI invariant ("input is enabled iff no queued
message exists") and prevents the drift toward parallel-feel
that this whole design is trying to eliminate.

Edit-as-pull-back is the simplest mental model for editing without
introducing a draft-history concept. The user's typed text is
either in the input (mutable) or in the queue (immutable until
pulled back). No third state.

**Alternatives considered:**

- Multi-queue with reorder: deferred to a future change.
- Edit-in-place on the queued bubble: rejected because it
  introduces a "draft inside the chat list" affordance with its
  own input and validation, doubling the UI surface area.

### D5. Inline rendering of the queued message in the chat list

**Decision:** The queued message appears in the chat list, in
chronological position, with a visually distinct "QUEUED" style.

**Why:** Strict chronology is the core mental model. Putting
queued messages anywhere except their chronological position
fights the model. The visual style differentiates state without
hiding the message.

A bonus is the absence of a visual jump when the message is sent
— it transitions from "QUEUED" style to sent style in place,
rather than moving from a separate area into the list.

**Alternatives considered:**

- Stack of queued bubbles above the input: rejected per the
  model-fighting reason above (also moot now that there's only
  one queued message).
- Hide queued until sent: rejected because the user loses
  confidence that their message is captured.

### D6. Naive polling-based wait for multi-client safety

**Decision:** Before processing `POST /messages`, the engine inspects
the trailing persisted message for the session. If it is
`final=false`, the request waits for the cycle to settle by polling
the persistence layer at a short interval (default 250 ms) until
the trailing message becomes `final=true` or a timeout elapses
(default 30 s). On timeout, the engine returns `409 Conflict` with
a body that identifies the in-flight cycle. The wait does NOT apply
to `POST /continue`, because `/continue` is the action that advances
an in-flight cycle and would otherwise deadlock against the very
state it is meant to mutate; a race between two concurrent
`/continue` calls is an accepted v1 risk.

**Why:** The single-client strict-ordering model already prevents
this race during normal use. The wait exists for the rare case of
two apps or two tabs operating on the same session, where the
client-side queue is bypassed. Polling is the smallest possible
defense — no per-session lock, no event subscription, no dispatcher
— and is acceptable because:

- The case is rare. Most sessions have one active client.
- The wait is short relative to typical agent run-times. A 250 ms
  poll interval is invisible to humans; a 30 s timeout is far
  longer than realistic cycle durations.
- Polling avoids introducing a new concurrency primitive at the
  persistence port. The same trailing-message read used by
  history reconstruction is reused.
- It is additive: if a future deployment needs stronger guarantees,
  a real lock can replace the wait helper without touching the
  endpoints or the data model.

The check is co-located with `perform_user_input` and
`continue_session` in the services layer so that any new entry
point for agent execution naturally inherits the guard.

**Alternatives considered:**

- Per-session asyncio.Lock or portalocker-based lock on the
  persistence port: rejected for v1. Stronger semantics, but
  introduces a primitive whose cleanup, ownership, and cross-
  worker behaviour need careful design. The polling approach is
  enough for the rare case it targets.
- Event-driven wait (subscribe to a settlement event on the
  persistence layer): rejected as over-engineering. Requires a
  pub/sub abstraction that doesn't otherwise exist.
- Async-decoupled message acceptance with SSE-only responses:
  rejected because the strict-ordering model removes the UX
  motivation for it (no parallel-feel messages); the additional
  complexity isn't justified.
- No engine guard at all (rely entirely on the client): rejected
  because two-app use is plausible enough that a 500-class
  history-reconstruction failure on collision would be a poor
  experience, and the polling guard is cheap to add.

### D7. Read-time default for missing `final` field; no write-time backfill

**Decision:** The `final` field defaults to `true` when absent from
a persisted record. The persistence layer relies on the model's
default value during deserialization, so old records written before
this change load as `final=true` without any bulk write. New
messages persisted under the new code carry the field explicitly.

**Why:** A read-time default keeps old sessions resumable without
running a migration job, and avoids touching records that may be in
backups, snapshots, or other read paths. Treating prior history as
fully settled is the only safe interpretation — we cannot tell from
the existing data whether any old `SystemAction` was "in-flight" at
the moment of the cut, and there is no write needed to encode that
interpretation.

The pydantic models already define `final: bool = True` (for
`AssistantMessage`) and `final: bool = False` (for `UserMessage` and
`SystemAction`); for old records lacking the field, the `True`
default is supplied by the persistence layer's deserialization
logic, overriding the per-type default. The decision is local to
the persistence adapter and does not leak into domain code.

**Alternatives considered:**

- Write-time backfill (one-shot script setting `final=true` on
  every existing message): rejected because it requires an
  operational migration step, touches all historical records
  unnecessarily, and risks breaking sessions that are mid-load
  during the migration window.
- Best-effort backfill (e.g., infer in-flight from "trailing
  SystemAction with undecided approvals"): rejected as
  unnecessary risk and complexity for records that should simply
  be treated as settled.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Multi-device / multi-tab on the same session bypasses the client-side queue, allowing concurrent requests to the engine and re-introducing the race conditions that single-client strict ordering otherwise prevents | Mitigated by the engine-side defensive wait (D6): `/messages` and `/continue` poll for a settled trailing message before proceeding, with a `409 Conflict` response on timeout. Cross-device synchronization of client-side draft and queue state remains out of scope. |
| Client orchestration of `/grant` + `/continue` is two HTTP calls per Approve click, increasing user-perceived latency on slow links | Acceptable: the second call (`/continue`) is the one that actually generates the response; the round-trip overhead of the first call is small. Can be optimized later (e.g., HTTP/2 keepalive, request batching) without changing the data model. |
| Read-time default treats all pre-cutover messages as `final=true`, including any that were genuinely in-flight at the moment of upgrade | Acceptable. Worst case: a user who had a pending approval at cut-over loses the ability to act on it through the new UI; they can start a new cycle. Mitigation is a clear release note about completing pending approvals before upgrading. |
| Stop mutates messages instead of appending, which is an unusual pattern for an otherwise append-leaning history | Mitigated by the universal `final` flag making the mutation discipline explicit and machine-checkable: any code that writes to a `final=true` message is a bug, and the boundary is enforced at the persistence layer. |
| Removing `POST /sessions/{id}/grants` and `POST /reject_approvals` outright (no deprecation window) breaks any client running an older engine version | Acceptable: engine and apps are released as matched versions. Mixed-version deployments are not a supported configuration in v1. The new per-approval endpoints are strictly more granular and cover the same flows. |
| The client's "edit queued" pulls the text back into the input, but if the user has already typed something else, the new text would be lost | Mitigation: confirm before discarding, or merge by prepending the queued text to the current input. Decision deferred to implementation; flagged in Open Questions. |

## Migration Plan

Engine and apps are released as matched versions (no mixed-version
support in v1).

1. Land the engine change: new endpoints, `final` field on the
   domain models, persistence adapter supplies `final=true` when
   the field is absent from a stored record, Stop endpoint.
   `POST /sessions/{id}/grants` and `POST /reject_approvals` are
   removed in the same change. No bulk write to existing data.
2. Land the client change in lock-step, switching to the new
   endpoints and the strict-ordering UI.
3. Rollback: revert both sides together. Engine rollback restores
   the old endpoints; client rollback restores the old UI. The new
   `final` field persisted by the engine is tolerated by the old
   client (extra fields are ignored).

## Open Questions

- **OQ1.** "Edit queued" interaction when the input already
  contains text: confirm-and-discard, prepend-and-merge, or
  refuse-until-input-cleared? Pick one in the tasks artifact.
- **OQ2.** Trigger UX for "edit queued" — long-press the bubble,
  swipe, or a small action icon? UI detail; decide in
  implementation.
- **OQ3.** Should `/stop` return the settled state (the modified
  `SystemAction` and user message) or `204 No Content`? Returning
  the state lets the client confirm without a follow-up read,
  but adds a coupling between Stop and the message model. Lean
  toward returning state for fewer round-trips; confirm in the
  spec artifact.
- **OQ4.** Whether to keep `/sessions/{id}/continue` in its
  current shape (returns `ChatResponse`) or to align it with the
  new state-change endpoints' style (e.g., trigger and stream the
  result via SSE only). Out of scope for this change; flagged for
  a possible future API consistency pass.
