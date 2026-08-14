## Why

`agenticChatProvider` is a single global Riverpod `Notifier`, and "the currently displayed session" is an implicit pointer (`Settings.agenticSessionId`) that many unrelated call sites read. Because state is shared across all sessions, every async operation (send, continue, stop, grant, incremental refresh) has to manually re-check whether its session is still the active one before touching state, or a stale response bleeds into whatever session the user has since switched to. A prior bugfix pass added seven such hand-written guards plus a listener that resets transient UI flags on session change — that class of bug is now patched, but the architecture still requires every future async call site to remember the same discipline by hand. Scoping chat state per session removes the failure mode structurally instead of relying on convention.

## What Changes

- Convert `agenticChatProvider` from a singleton `NotifierProvider` to `NotifierProvider.family<AgenticChatNotifier, AgenticChatState, String>` keyed by `sessionId`, so each session's messages, loading flags, and title live in their own isolated instance.
- Introduce a small, non-persisted "displayed session" provider representing which session is currently shown in the UI. `Settings.agenticSessionId` keeps its existing job — remembering the last session to restore on next launch — but live session switching no longer flows through it.
- Update the four consumers that currently read the singleton (`agentic_chat_page.dart`, `sessions_page.dart`, `sensitivity_widgets.dart`, `invocation_page.dart`) to resolve the displayed session and address the family instance for it.
- Update `sse_provider.dart` to route incoming events by the event's own `sessionId` to the matching family instance instead of comparing against one global "active" pointer and dropping everything else. Full chat state for non-displayed, non-kept-alive sessions is unchanged (still not live-updated, matching today) — this is a routing mechanism change, not a new "background sessions stay live" feature.
- When a `messages.appended` event arrives for a session with no live chat-state instance, update that session's entry in the sessions list (last-activity timestamp, reordered to the top) instead of dropping the event outright — a lightweight signal, not a fetch of the session's full history. This closes a real gap: the engine's `/continue` and stop-cycle flows (exactly how a background approval gets resolved) don't emit `session.updated`, only `messages.appended`, so today the sessions list never reflects that activity for a session you haven't reopened.
- Define a disposal policy for family instances: keep a session's state alive via `ref.keepAlive()` while it has an in-flight cycle (`state.isAwaiting`), release once the cycle settles or the disposal linger period expires — so navigating away mid-approval-flow doesn't discard or interrupt it.
- Remove the seven manual "is this session still active" guards and the transient-state-reset listener added by the prior bugfix — they become structurally unnecessary once a stale session's response can no longer reach another session's state.
- **Out of scope**: no route-level session identity (no `/chat/:sessionId`). Navigation stays a flat `/chat`; the displayed-session provider is the source of truth for "which session," per explicit decision that route separation isn't needed here.

## Capabilities

### New Capabilities
(none — this reorganizes how existing behavior is implemented; no new user-facing capability is introduced)

### Modified Capabilities
- `agentic-chat`: add a **Session Isolation** requirement formalizing the guarantee that switching the displayed session cannot leak another session's messages, pending approvals, loading indicators, or title, and that a response to a request issued for a previously-displayed session must not be applied after the user has switched away. This behavior already exists (delivered as bugfixes in the prior session); this change makes it a documented, structurally-enforced requirement instead of an implicit, guard-by-guard convention.
- `agentic-chat`: add a **Sessions List Reflects Background Activity** requirement — a session that isn't currently displayed still surfaces new activity (updated timestamp, reordered to the top of the sessions list) instead of appearing untouched until reopened.

## Impact

- **Core**: `lib/providers/agentic_chat_provider.dart` — family conversion, keepAlive/disposal policy, removal of the now-redundant staleness guards.
- **Routing/state source**: new small provider for "displayed session id"; `lib/models/settings.dart` / `lib/providers/settings_provider.dart` unchanged in meaning (still persists last-session-to-restore).
- **Consumers**: `lib/pages/agentic_chat_page.dart`, `lib/pages/sessions_page.dart`, `lib/agentic/sensitivity_widgets.dart`, `lib/pages/invocation_page.dart` — resolve displayed session and address the family instance.
- **Event routing**: `lib/providers/sse_provider.dart` — route by event sessionId instead of active-session comparison; on a `messages.appended` event for a session with no live instance, forward a lightweight activity bump to `sessionsProvider` instead of dropping it. `lib/agentic/sse_client.dart` — parse the event envelope's existing `created_at` field (currently discarded), needed as the activity timestamp for that bump.
- **Peripheral**: `lib/providers/sessions_provider.dart` — reads "which session is active" (for highlighting in the session list) from the new displayed-session provider instead of `Settings.agenticSessionId`; gains a lightweight "bump this session's activity" update path alongside the existing full `updateSession()`.
- **Tests**: `apps/test/agentic/agentic_chat_provider_test.dart` — every test's provider-access pattern changes (`agenticChatProvider.notifier` → `agenticChatProvider(sessionId).notifier`); `apps/test/providers/message_event_dedup_test.dart` — subclass-override wiring needs rework for the family provider.
- **No engine/API changes.** No persisted-settings schema change (`agenticSessionId` field keeps its current meaning).
