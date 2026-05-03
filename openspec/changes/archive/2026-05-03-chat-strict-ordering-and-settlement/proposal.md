## Why

Today the chat presents an incoherent mental model when more than one
user message is in play at the same time. The Phoenix trace
`27d80f45f403fbecfca0256c67d13143` made this concrete: a user sent
"retry" while an approval was still pending; the engine accepted both
messages; the resulting persisted history interleaved a user message
between a `SystemAction` (tool approval) and its eventual
`AssistantMessage`, breaking the invariants that
`_get_known_history_from_messages` assumes and producing a 500 error
on the next request.

The deeper issue is that the **user-facing model** is wrong. An LLM
dialog is strictly sequenced — the assistant's response to message N
depends on the content of, and decisions made in, messages 0..N-1.
The current UI lets the user act as if messages are independent (type
and send freely), and that misleading affordance is what creates the
conditions for the bug. Once the model is strictly sequenced and
rendered as such, the bug becomes structurally impossible.

This change introduces an explicit, app-enforced linear conversation
model: at most one cycle in flight at a time, at most one queued
message, and explicit settlement of every cycle.

## What Changes

### 1. Universal `final` flag on every message

- Add `final: bool` to every persisted message (`UserMessage`,
  `AssistantMessage`, `SystemAction`).
- `final=false` → in-flight; a narrow set of state fields may mutate.
- `final=true` → settled; immutable, append-only.
- The flag transitions one-way (`false → true`) exactly once per
  message.

What is mutable while `final=false` is **narrowly defined per type**:
- `UserMessage`: only the `final` flag itself. Content is immutable
  from creation.
- `SystemAction` with approvals: each `Approval.granted` (`null →
  true|false`) and the `final` flag.
- `AssistantMessage`: created `final=true`; never mutates.

### 2. Settlement events

A "cycle" is one user message plus any approval round-trips it
triggers. A cycle settles when one of these conditions holds:

- An `AssistantMessage` is appended → normal completion. The append
  flips `final=true` on every preceding in-flight message back to and
  including the user message that started the cycle.
- The user invokes Stop → the engine mutates the in-flight
  `SystemAction`(s): undecided approvals are set to `granted=false`,
  `SystemAction.final` is set to `true`, and the user message that
  started the cycle has `final` set to `true`. **No new record is
  appended.** The settled state (declined approvals, no following
  `AssistantMessage`, all messages `final`) is the marker.

### 3. App-side queue model

- The app maintains exactly one **draft** (text in the input field,
  not yet submitted) and at most one **queued** message (submitted by
  the user but not yet sent to the engine because the previous cycle
  is still in flight).
- State machine:

  | State | In-flight cycle? | Queued? | Input |
  |-------|------------------|---------|-------|
  | idle | no | no | enabled |
  | awaiting | yes | no | enabled |
  | awaiting + queued | yes | yes (1 max) | **disabled** |

- Submit while `idle` → message sent immediately, transitions to
  `awaiting`.
- Submit while `awaiting` → message is queued, transitions to
  `awaiting + queued`. Input deactivates.
- "Edit queued" affordance: removes the queued message from the chat
  list and reloads its text into the input. Returns to `awaiting`,
  input enabled.
- When a cycle settles: if there is a queued message, the app
  auto-sends it (transitioning back to `awaiting` with a new cycle in
  flight). If not, transitions to `idle`.
- The queued message is rendered **inline in the chat list** with a
  visually distinct "QUEUED" style (preserving strict chronology).

### 4. Approval widget redesign

Replace the current per-card `Skip / Approve` with:

- Per-card buttons: **Continue without** and **Approve**.
- A separate cycle-level **Stop** bar at the bottom of the approval
  group.
- Each user click is a single intent; the client orchestrates any
  necessary follow-up calls.

Wording rationale:
- **Approve** — grant this tool's permission; agent will continue.
- **Continue without** — decline this tool, but expect the assistant
  to still respond using the denial as input.
- **Stop** — settle the cycle now; the user message gets no assistant
  response.

### 5. Engine API changes

Three new state-change endpoints (no message in body):

```
POST /sessions/{id}/approvals/{approval_id}/grant
POST /sessions/{id}/approvals/{approval_id}/decline
POST /sessions/{id}/stop
```

- `/grant` and `/decline` are pure state-change endpoints. They
  record the per-approval decision and return `204 No Content` (or
  the updated approval state). They do **not** trigger the agent.
- `/stop` mutates in-flight messages as described in Section 2 and
  returns the settled state. It does **not** trigger the agent.
- `POST /sessions/{id}/continue` (existing) is retained as the
  explicit way to drive the agent's next iteration. Message output
  flows only through the dedicated message endpoints (`/messages`,
  `/continue`) and the SSE stream.

Client orchestration:
- **Approve** click → `POST /grant`. If all approvals in the trailing
  `SystemAction` are now decided, follow with `POST /continue`.
- **Continue without** click → `POST /decline`. If all decided, follow
  with `POST /continue`.
- **Stop** click → `POST /stop` (single call, no continue).

The implicit "all decided → continue" check happens **client-side**;
the engine does not auto-continue.

### 6. Engine-side defensive wait for multi-client safety

The strict-ordering model assumes a single active client per session.
For the rare case where two apps (or two tabs) operate on the same
session, the engine adds a naive guard so that a second request
cannot interleave with an in-flight cycle.

- Before processing `POST /messages`, the engine checks the trailing
  persisted message for the session. If it is `final=false`, the
  request waits for the cycle to settle by polling the persistence
  layer at a short interval (e.g., 250 ms) until the trailing
  message becomes `final=true` or a timeout is reached (e.g., 30 s).
- The wait does NOT apply to `POST /continue`, since `/continue` is
  the action that advances an in-flight cycle and would otherwise
  deadlock against itself. A race between two concurrent `/continue`
  calls from different clients is an accepted v1 risk.
- On settle, processing proceeds normally with the now-up-to-date
  history.
- On timeout, the engine returns `409 Conflict` with a body
  describing the still-in-flight cycle so the client can surface a
  clear error.

This is intentionally simple — no per-session lock, no event
subscription. Polling is acceptable because the case is rare and
the wait is short relative to typical agent run-times.

### Out of Scope (v1)

- General "interrupt cycle when no approval is pending" (Stop while
  the agent is just thinking with no approval prompt). The Stop
  pattern introduced here is the affordance we'll later reuse for
  this.
- Multi-message queue (more than one queued message at a time).
- Cross-device sync of client-side drafts and queued messages. (The
  engine guards against concurrent operations on the same session via
  the defensive wait in Section 6, but per-app draft/queue state is
  not synchronized across devices.)
- Streaming partial assistant responses.
- Editing of sent (non-queued) messages.

## Capabilities

### New Capabilities

- `message-finalization`: every message carries an explicit `final`
  flag distinguishing in-flight (mutable state) from settled
  (immutable, append-only) messages. Settlement events flip the flag
  on all preceding in-flight messages back to the cycle's user
  message.
- `client-message-queue`: the app maintains at most one queued
  message and serializes sends so that no more than one cycle is in
  flight per session at a time.
- `cycle-stop-action`: an explicit user action that settles the
  current cycle without producing an assistant response, leaving the
  declined approvals as the historical record of the decision.
- `engine-in-flight-guard`: before processing a new message or
  continuation, the engine inspects the trailing persisted message
  for the session and waits (via short-interval polling, with a
  timeout) if a previous cycle is still in flight, returning
  `409 Conflict` on timeout.

### Modified Capabilities

- `agentic-chat`: the chat page renders three message states (sent,
  queued, settled) and disables the input while a queued message
  exists.
- `approval-ui`: per-card buttons change from `Skip / Approve` to
  `Continue without / Approve`; a cycle-level `Stop` bar is added at
  the bottom of the approval group; grant and decline calls target
  the new per-approval endpoints.
- `session-continuation`: the `/continue` endpoint remains but is
  invoked by the client after collecting per-card decisions, rather
  than being part of an implicit grant+continue flow.

## Impact

- **Engine — domain models** (`engine/domain/models.py`): add `final:
  bool` to `UserMessage`, `AssistantMessage`, `SystemAction`. Default
  `false` for `UserMessage` and `SystemAction`, `true` for
  `AssistantMessage`.
- **Engine — services** (`engine/domain/services.py`): on agent
  response, flip `final=true` on the preceding in-flight chain. New
  `stop_cycle(session_id)` method that mutates the trailing in-flight
  `SystemAction`(s) and user message. New defensive
  `wait_for_settled(session_id, timeout)` helper used by
  `perform_user_input` and `continue_session` before they begin work.
- **Engine — API** (`engine/api/v1.py`): three new endpoints (grant,
  decline, stop) per Section 5; `POST /sessions/{id}/grants` and
  `POST /sessions/{id}/reject_approvals` are removed (the per-approval
  routes replace them). `GET /sessions/{id}/grants` (listing) and
  the global `/grants` routes are kept. Existing `/continue` retained.
- **Engine — history reconstruction**
  (`engine/adapters/pydantic_ai_execution/queries.py`): the existing
  cut-off logic in `_get_known_history_from_messages` becomes
  reliable because the strict-ordering model prevents the
  interleaved-user-message pattern that broke it. Minor adjustments
  to recognize `final` and to treat a stopped cycle correctly.
- **Engine — persistence**: no bulk write migration. The persistence
  adapter supplies `final=true` when the field is absent from a
  stored record on read, so pre-cutover messages load as settled
  history without touching existing data.
- **Flutter app — chat provider**
  (`apps/lib/providers/agentic_chat_provider.dart`): implement the
  three-state machine, draft/queue handling, edit-queued affordance,
  auto-send-on-settle.
- **Flutter app — approval card**
  (`apps/lib/agentic/approval_card.dart`,
  `apps/lib/agentic/widgets.dart`): replace `Skip/Approve` with
  `Continue without/Approve`; add the cycle-level `Stop` bar;
  orchestrate the `/grant` or `/decline` + `/continue` sequence per
  click.
- **Flutter app — chat list**
  (`apps/lib/pages/agentic_chat_page.dart` and message bubble
  widgets): render `QUEUED` style for queued messages; disable input
  while queued exists.
- **Tests**: end-to-end tests for the strict-ordering flow including
  the original trace scenario (a second message during an in-flight
  cycle should now be queued client-side and never reach the engine
  before the first cycle settles); engine tests for the `final` flag
  transitions and the stop endpoint; UI tests for the new approval
  widget and the queued-message rendering.
- **Migration / backwards compatibility**: engine and apps are
  released as matched versions. Mixed-version deployments are not a
  supported configuration in v1 — the deprecated POST endpoints are
  removed in this change rather than kept around.
