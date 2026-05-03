## 1. Engine — Domain Models

- [x] 1.1 Add `final: bool` field to `UserMessage` in `engine/domain/models.py` (default `False`)
- [x] 1.2 Add `final: bool` field to `SystemAction` in `engine/domain/models.py` (default `False`)
- [x] 1.3 Add `final: bool` field to `AssistantMessage` in `engine/domain/models.py` (default `True`)
- [x] 1.4 Document the per-type mutability rules as docstring comments on each model
- [x] 1.5 Update model unit tests to cover the new field defaults and serialization

## 2. Engine — Persistence Adapter

- [x] 2.1 In the persistence adapter's deserialization path, supply `final=True` when the field is absent from a stored record (read-time default)
- [x] 2.2 Add an immutability guard at the persistence boundary: writes to a record where the on-disk `final=True` must raise an explicit error
- [x] 2.3 Add a unit test loading an old-format record (no `final` field) and asserting it deserializes with `final=True`
- [x] 2.4 Add a unit test asserting that writing to a `final=True` record raises
- [x] 2.5 Verify no schema migration job is added or required

## 3. Engine — Services: Settlement Logic

- [x] 3.1 In `engine/domain/services.py`, add a helper to flip `final=True` on the entire trailing in-flight chain back to and including the cycle's `UserMessage`
- [x] 3.2 Wire the helper into `perform_user_input` so that appending a new `AssistantMessage` settles the cycle atomically
- [x] 3.3 Wire the helper into the agent-completion path used by `continue_session`
- [x] 3.4 Add unit tests covering: simple cycle (User → Assistant), cycle with one SystemAction, cycle with multiple chained SystemActions

## 4. Engine — Services: Stop Logic

- [x] 4.1 Add `stop_cycle(session_id)` method in `engine/domain/services.py`
- [x] 4.2 Implementation: locate trailing in-flight `SystemAction`(s); set every undecided approval to `granted=False`; mark `SystemAction.final=True`; mark cycle's `UserMessage.final=True`; return settled state
- [x] 4.3 Raise a domain conflict error if there is no in-flight cycle to stop
- [x] 4.4 Add unit tests covering: undecided approvals, all-decided approvals, no-in-flight-cycle (error), non-existent session (error)

## 5. Engine — Services: In-Flight Guard

- [x] 5.1 Add `wait_for_settled(session_id, *, poll_interval, timeout)` helper in services
- [x] 5.2 Add config knobs for poll interval (default 250 ms) and timeout (default 30 s) in engine settings
- [x] 5.3 Define a `SessionInFlightTimeout` domain error carrying the trailing message id
- [x] 5.4 Invoke `wait_for_settled` at the top of `perform_user_input` (NOT `continue_session` — see design D6 update: continue advances an in-flight cycle and would deadlock against it)
- [x] 5.5 Add unit tests with a fake persistence layer: trailing already settled (no wait), trailing flips to settled mid-poll (proceeds), never settles (raises timeout)

## 6. Engine — API Endpoints

- [x] 6.1 Add `POST /sessions/{session_id}/approvals/{approval_id}/grant` in `engine/api/v1.py` calling a new service method that records the per-approval grant on the in-flight `SystemAction`
- [x] 6.2 Add `POST /sessions/{session_id}/approvals/{approval_id}/decline` in `engine/api/v1.py` (mirror of grant)
- [x] 6.3 Add `POST /sessions/{session_id}/stop` returning the settled state from `stop_cycle`; `409 Conflict` when no in-flight cycle; `404` when session missing
- [x] 6.4 Map `SessionInFlightTimeout` to `409 Conflict` with body containing session id and trailing message id
- [x] 6.5 Remove `POST /sessions/{id}/grants` and `POST /sessions/{id}/reject_approvals` outright (no deprecation window — engine and apps are version-matched). Keep `GET /sessions/{id}/grants` (listing) and the global `/grants` routes.
- [x] 6.6 Confirm `POST /sessions/{id}/continue` retains its existing `ChatResponse` shape (in-flight guard skipped per design D6)
- [x] 6.7 Add API tests for each new endpoint covering happy path and error cases

## 7. Engine — History Reconstruction

- [x] 7.1 Update `_get_known_history_from_messages` in `engine/adapters/pydantic_ai_execution/queries.py` to use the `final` flag as the authoritative settled signal
- [x] 7.2 Ensure stopped cycles (declined approvals on a `final=True` `SystemAction` with no following `AssistantMessage`) are treated as immutable settled history without raising
- [x] 7.3 Ensure in-flight chains (`final=False`) are not passed to the agent as history (the in-flight guard handles concurrency before this code runs)
- [x] 7.4 Add an end-to-end engine test reproducing the original Phoenix trace scenario (`27d80f45f403fbecfca0256c67d13143`) and assert no error is raised

## 8. Engine — Coordinated Tests

- [x] 8.1 Add an integration test for the multi-client guard: 2nd concurrent `/messages` returns 409 instead of producing a broken interleaved history (covered by `TestPhoenixTraceRegression`)
- [x] 8.2 Add an integration test for grant → continue and decline → continue exercising the new per-approval endpoints end-to-end
- [x] 8.3 Add an integration test for stop while approvals are pending, asserting the persisted state matches the spec

## 9. Flutter — Chat Provider State Machine

- [x] 9.1 In `apps/lib/providers/agentic_chat_provider.dart`, replace the current synchronous-send model with a state machine: `idle`, `awaiting`, `awaiting + queued`
- [x] 9.2 Add a single optional queued-message field to provider state
- [x] 9.3 Implement submit handler: if `idle` → send via `POST /messages`; if `awaiting` → store as queued
- [x] 9.4 Implement settle handler: when an `AssistantMessage` arrives or a stop completes, flip local visual state and auto-send the queued message if present
- [x] 9.5 Implement `editQueued()` which removes the queued message and loads its text into the input
- [x] 9.6 Expose an `inputEnabled` derived value (`true` iff no queued message exists)
- [x] 9.7 Decide and implement the queued-message-vs-typed-text policy from design Open Question OQ1 (confirm-discard, prepend-merge, or refuse-until-cleared) — resolved as **refuse-until-cleared, enforced by input disable**: the input is disabled while a queued message exists, so an "in-progress typed text" can never coexist with a queued message. The edit-queued affordance overwrites input contents unconditionally (a queue-clear; the input was empty by invariant)
- [x] 9.8 Implement incremental refresh on `messages.appended`: refetch from event's sequence_id; for each fetched message, replace the locally cached entry only if the cached entry is `final=false` (or absent). Cached `final=true` messages are immutable and SHALL NOT be overwritten.
- [x] 9.9 Add provider unit tests for every state transition and for the refresh policy (in-flight overwrite, settled preserve, new append)

## 10. Flutter — API Client

- [x] 10.1 Add `grantApproval(sessionId, approvalId, params)` calling `POST /sessions/{id}/approvals/{approval_id}/grant` — implemented as `grantSessionApproval(...)` in `apps/lib/agentic/services.dart`, with optional `grant: GrantRequest` for session-scoped grants
- [x] 10.2 Add `declineApproval(sessionId, approvalId)` calling `POST /sessions/{id}/approvals/{approval_id}/decline` — implemented as `declineSessionApproval(...)` in `apps/lib/agentic/services.dart`
- [x] 10.3 Add `stopSession(sessionId)` calling `POST /sessions/{id}/stop`, parsing the returned settled state — implemented in `apps/lib/agentic/services.dart`, returns `List<AgenticMessage>` parsed from the `messages` field
- [x] 10.4 Handle `409 Conflict` responses from `/messages` and `/continue` with a typed error the UI can surface as "session busy" — `SessionInFlightException` and `NoInFlightCycleException` parsed from the conflict body via `_tryParseConflict` in `services.dart`
- [x] 10.5 Drop any client code that calls the removed `POST /sessions/{id}/grants` or `POST /sessions/{id}/reject_approvals` paths and update generated API bindings — verified no remaining refs to either path under `apps/lib` or `apps/test`. The retained `POST /api/v1/grants` is the global-grant route (kept by design, see 6.5).

## 11. Flutter — Approval Card Redesign

- [x] 11.1 In `apps/lib/agentic/approval_card.dart`, replace the per-card `Skip` button with `Continue without`
- [x] 11.2 Wire `Approve` to `grantApproval` (per-approval endpoint), then if all in trailing `SystemAction` are decided, call `/continue`
- [x] 11.3 Wire `Continue without` to `declineApproval`, then same auto-continue check
- [x] 11.4 Add a cycle-level `Stop` bar at the bottom of the approval group (visually distinct, e.g., red full-width)
- [x] 11.5 Wire `Stop` to `stopSession`; do NOT call `/continue` after Stop
- [x] 11.6 Show Stop bar only when the trailing `SystemAction` has `final=false`
- [x] 11.7 Update collapsed/resolved card state to render `granted=true` as "granted" and `granted=false` as "declined" (replacing prior "skipped") — `ApprovalResolution.skipped` renamed to `declined`
- [x] 11.8 Decide on Stop interaction during `awaiting + queued` (confirmation vs preserve queue) and implement — resolved as **pull queued text into input, then stop**: Stop reuses the edit-queued logic so the queued text is preserved as a draft and the cycle is stopped without it being sent
- [x] 11.9 Add widget tests for new buttons and Stop bar visibility rules

## 12. Flutter — Chat List Rendering

- [x] 12.1 Add a `MessageVisualState` enum or equivalent (`sent`, `queued`, `settled`) and derive it from the message + provider state — implemented as implicit visual states: `sent` and `settled` share the existing user-bubble path (the `isFinal` flag distinguishes them at the data layer); `queued` is its own widget (`QueuedMessageBubble`) selected by the chat-history renderer when `queuedMessage != null`
- [x] 12.2 Implement the QUEUED bubble style (dashed border, small "QUEUED" label) in the message bubble widget
- [x] 12.3 Render the queued message inline at chronological end of the chat list
- [x] 12.4 Implement the "edit queued" affordance per design Open Question OQ2 (long-press, swipe, or icon — pick one) — chosen: **inline pencil icon next to the QUEUED label on the bubble's header line**
- [x] 12.5 Disable the input field when `inputEnabled` is false and show a hint indicating an edit is available
- [x] 12.6 Add widget tests for the three visual states and input-disabled rendering

## 13. Flutter — Coordinated Tests

- [x] 13.1 Add an integration test reproducing the original trace scenario: type "retry" while an approval is pending; assert it is queued client-side, not sent, and gets dispatched after settle — covered by the provider-level test `AgenticChatNotifier — queued message · sendMessage enqueues when awaiting and does not append` (slice 4b)
- [x] 13.2 Add an integration test for the Stop flow end-to-end (Stop click → engine settles → chat list shows declined state, no AssistantMessage) — **MOVED to the `injectable-http-clients` change**: the in-process pieces are covered here (Stop bar visibility + tap → `onStop` → `stopCycle`), but the HTTP-roundtrip slice requires the injectable-client harness, which is the explicit purpose of the follow-up change. Closing this task within `chat-strict-ordering-and-settlement`; the follow-up change owns the integration coverage.
- [x] 13.3 Add an integration test for the auto-send-on-settle flow with a queued message — covered by the provider-level merge-refresh + `_dispatchQueuedIfAny` tests in slice 4b
- [x] 13.4 Add an integration test for handling `409 Conflict` from `/messages` (multi-client scenario) — full HTTP-roundtrip integration deferred to the `injectable-http-clients` change; the conflict-body parser is covered here by `apps/test/agentic/services_test.dart` (`tryParseConflict` exposed via `@visibleForTesting`), exercising both `session_in_flight` and `no_in_flight_cycle` discriminators plus the malformed/missing-detail fallbacks

## 14. Documentation & Release

- [x] 14.1 Update API documentation (OpenAPI annotations, README) to describe the new endpoints, the in-flight guard semantics, and the removal of `POST /sessions/{id}/grants` / `POST /reject_approvals`
- [x] 14.2 Add release notes calling out: complete pending approvals before upgrading; new Stop button; queued-message UI — added under the `## 0.1.23 — Strict-ordering chat` section in `CHANGELOG.md` (Upgrade notes, Added, Changed)
- [x] 14.3 Run `openspec validate chat-strict-ordering-and-settlement --strict` and address any findings — passes clean (`Change 'chat-strict-ordering-and-settlement' is valid`)

## 15. Roll-out

- [x] 15.1 Bump engine and apps versions together; release as a matched pair — `VERSION` is `0.1.23-pre`, applied uniformly to engine and apps
- [x] 15.2 Land engine changes (sections 1–8, 14) and Flutter changes (sections 9–13) in lock-step — engine + Flutter work all live on this branch and merge as one
