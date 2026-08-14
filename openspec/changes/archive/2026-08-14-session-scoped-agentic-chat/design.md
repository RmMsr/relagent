## Context

`agenticChatProvider` is today a single `NotifierProvider<AgenticChatNotifier, AgenticChatState>`. "Which session is displayed" is read out of `Settings.agenticSessionId` at the top of nearly every notifier method (`ref.read(settingsProvider).agenticSessionId`), and a prior bugfix pass added seven guards of the shape "re-read the active session id after an `await` and drop the response if it no longer matches" plus a listener that resets `isLoading`/`showAssistantPending`/`sessionTitle` when `agenticSessionId` changes. See `proposal.md` - Why for the motivation to remove that convention-based discipline in favor of structural isolation. See `specs/agentic-chat/spec.md` for the resulting behavior contract (Session Isolation requirement).

Navigation stays flat (`context.go('/chat')`, no `/chat/:sessionId`) per explicit decision — the displayed session lives in a small in-memory provider, not the route.

## Goals / Non-Goals

**Goals:**
- Make cross-session state bleed structurally impossible rather than guarded against.
- Preserve exact current behavior for: session persistence across app restart, and the sessions list.
- Keep memory bounded — do not let every session ever opened in a running app instance accumulate live state forever.
- Avoid unnecessary full re-fetches once a session's client-side state is already current or cheaply reconcilable, without weakening correctness against changes made by another device or another agent working the same session.
- Surface background activity (a session that changed while not displayed) in the sessions list cheaply — without requiring that session's full chat state to be materialized or fetched.

**Non-Goals:**
- Route-level session identity (`/chat/:sessionId`) — explicitly deferred, not needed for the isolation goal.
- Making non-displayed, disposed sessions keep their *full chat state* live-updating from SSE. A session that is genuinely disposed (idle, not kept alive) still only rehydrates its messages when next displayed — matching current behavior. Sessions kept alive (Decision 3) are a partial, incidental exception; see Decision 4. (The sessions *list* is a separate, deliberately lighter-weight case — see Decision 4's activity-bump addition and the new Sessions List Reflects Background Activity requirement.)
- Any engine/API change. (The underlying gap this surfaces — `continue_session`/`stop_cycle` don't emit `session.updated` — is worked around client-side, not fixed at the source; see Decision 4.)
- Persisted-settings-schema change.

## Decisions

### 1. Family provider keyed by non-null `sessionId`; a separate draft notifier owns pre-session-creation state

`agenticChatProvider` becomes `NotifierProvider.autoDispose.family<AgenticChatNotifier, AgenticChatState, String>`. The family key is a real, non-null `sessionId` — no sentinel value.

Today, before the first message of a brand-new chat is sent, there is no `sessionId` yet; `_dispatchUserMessage` sends with `sessionId: null` and only learns the real id from the response. A family provider needs a concrete key up front, so this "no session yet" state can't live in a family instance.

Alternative considered: use a magic sentinel key (e.g. `''` or `'__draft__'`) as the family arg for the pre-creation state, then have the first successful send "migrate" that instance's messages into the real `sessionId` key and dispose the sentinel one. Rejected — it reintroduces exactly the kind of manual state-copying this refactor exists to eliminate, and every consumer would need to know to treat the sentinel key specially.

Chosen approach: a small, separate `newChatDraftProvider` (plain `Notifier`, not a family) owns only the "compose the first message, optimistic bubble, in-flight flag" state before a session exists. When the create-session response returns a real `sessionId`, the app seeds `agenticChatProvider(newSessionId)` with the resulting exchange, points the displayed-session provider (Decision 2) at `newSessionId`, and resets the draft notifier to empty. The chat page watches the draft provider when the displayed session is `null` and the family instance otherwise.

### 2. Displayed session lives in its own small provider, decoupled from `Settings.agenticSessionId`

A `displayedSessionProvider` (`Notifier<String?>`) is the single source of truth for "which session is on screen right now." It is seeded from `Settings.agenticSessionId` on launch (preserving restore-last-session behavior) but subsequent changes do not write through to `Settings` on every switch — `Settings.agenticSessionId` is updated only where it already semantically means "the session to restore," i.e. when a new session is created or the user explicitly switches (same persistence trigger points as today, just no longer also serving as the live "what's on screen" signal).

`sessions_provider.dart`'s "is this the active session" list highlight reads `displayedSessionProvider` instead of `settings.agenticSessionId`.

### 3. Disposal policy: `autoDispose` with a short idle linger, `ref.keepAlive()` while a cycle is in flight

Without `autoDispose`, a family provider is effectively an unbounded cache — every session ever viewed in a running app instance would keep its full `AgenticChatState` in memory forever, which is strictly worse than today's single shared instance. With `autoDispose`, a family instance is disposed once nothing is watching it (e.g., the chat page navigated to a different session).

Two cases need different treatment:

- **In flight** (a session with an unresolved approval or a cycle still processing, spec scenario "A session with an unresolved approval is not lost when navigated away from"): `AgenticChatNotifier.build(sessionId)` calls `ref.keepAlive()` and stores the returned link whenever state transitions to `isAwaiting == true`, closing it once the cycle settles (response, error, or stop). This ties disposal-prevention exactly to "there's a real in-flight cycle the app must not silently drop," not to "was this session viewed recently."
- **Idle but recently displayed**: disposing the instant the last listener drops means rapidly flipping between two sessions (A→B→A) tears down and rebuilds A on every flip, even though nothing changed and the in-memory copy was still perfectly good. `build(sessionId)` also acquires a short-lived `keepAlive()` link unconditionally on creation, released after a fixed grace window (a few hundred milliseconds) via a timer — unless the in-flight case above extends it indefinitely first. A quick flip back within the window reuses the still-warm instance for free; a sustained switch away lets it dispose and fall back to Decision 5's reconciliation fetch on return.

### 4. SSE routes by event `sessionId`, but only touches full chat state that already exists; a session with none still gets a lightweight activity bump

`sse_provider.dart`'s `MessagesAppendedEvent` handler currently compares the event's `sessionId` to the one global active id and drops the event otherwise. It moves to resolving `agenticChatProvider(event.sessionId)` directly — but only if that instance is currently alive (`ref.exists(agenticChatProvider(event.sessionId))`). This avoids the SSE handler itself becoming a reason instances never get disposed — a plain `ref.read` to fetch-and-update would otherwise silently defeat Decision 3's memory bound by instantiating an instance for every session that receives any event.

Note this means a session kept alive by Decision 3 (in-flight, or within its idle linger) *does* receive live incremental updates while not displayed — an incidental benefit of routing by existence rather than by "is this the displayed one," not a pursued feature. A genuinely disposed session's full chat state still only catches up on next display, via Decision 5.

When no live instance exists, the event is no longer dropped outright: it's forwarded to `sessionsProvider` as a lightweight activity bump — update that session's list entry's timestamp and move it to the top — rather than a full chat-state fetch. This is deliberately cheap (no `getSessionInfo()` round-trip) and is what the new Sessions List Reflects Background Activity requirement actually needs; the timestamp used is the event's own `created_at` (every SSE event already carries one server-side per `BaseEvent.created_at` in `engine/domain/ports/events.py`, but the Dart `SseEvent` hierarchy in `sse_client.dart` currently discards it during parsing — that gets added as a field on all event types, not just `MessagesAppendedEvent`, since it's already present on the wire for all of them).

This also sidesteps a real engine-side gap without touching the engine: `continue_session()` and `stop_cycle()` (`engine/domain/services.py`) only publish `session.messages.appended`, not `session.updated` — the exact background-approval-continuation case this requirement targets — so relying on `SessionUpdatedEvent` (as `sessions_provider.dart` does today) would keep missing it. Reacting to `messages.appended` directly closes the gap client-side.

`SessionCreatedEvent`/`SessionUpdatedEvent` handlers are unaffected — they already update `sessionsProvider` via a direct `getSessionInfo()` fetch, not through `agenticChatProvider`, and continue to do the full update (title included) when they do fire.

### 5. Redisplay and app-resume reconcile via a cursor-based fetch, never an unconditional full reload

Today, and in a naive port of today's behavior, switching to a session always calls `loadHistory()` with no cursor — refetching the entire message history even when the client already holds a complete, correct copy and nothing changed. That's wasted work in the common case. The fix is not to skip fetching when an instance is already alive, though: sessions in this app are not single-client-exclusive. Another device, or another agent, can append to a session while this client wasn't watching it — whether the instance was genuinely disposed or merely alive-but-unwatched (Decision 3). SSE is a best-effort push channel for this and can miss events across a reconnect; `didChangeAppLifecycleState`'s resume handler today only reconnects SSE and trusts `lastEventId` replay, without forcing any reconciliation of the displayed session. Skipping the fetch entirely on the assumption "we already have it" would be unsafe.

Instead, both session switch and app resume (for whichever session is displayed) always fetch `afterMessageId = <last known final message id, or null>` — the same cursor-based primitive `sse_provider.dart`'s `fetchSinceCursor()` already uses for SSE-triggered refreshes. This is cheap when nothing changed (an empty diff) and fully correct when something did, regardless of source — this client, another device, another agent, or a missed SSE event — because it is a pull against server truth rather than something that depends on push delivery having worked. It also needs no special-casing for freshness: a just-built or just-recreated instance naturally has no messages yet, so its cursor is naturally `null`, which is exactly what a full load already means — the same code path degrades to a full load automatically.

This consolidates `AgenticChatNotifier`'s external fetch surface: the cursor-computation logic that today lives only inside `SseNotifier.fetchSinceCursor()` moves onto the notifier itself (e.g. a `refreshFromServer()` method), and the SSE handler, the session-switch path, and the app-resume handler all call that one entry point instead of the page separately deciding to call `loadHistory()` with no arguments.

## Risks / Trade-offs

- [Risk] The `isAwaiting`-gated keepAlive logic has an edge case where a cycle settles without the flag flipping (mirroring exactly the kind of bug this refactor removes elsewhere) → session state gets disposed mid-flow. **Mitigation**: the "survives navigating away mid-approval" spec scenario must be tested at the provider level (drive a `ProviderContainer`, drop the widget listener, assert the instance is still retrievable with its approval intact), not only asserted via a widget test that never triggers disposal in the first place.
- [Risk] `invocation_page.dart`'s existing `clearChat()` → `sendMessage()` flow assumes a single provider it can clear-then-reuse; under the draft-notifier split (Decision 1) "start fresh" means routing through the draft notifier instead. This is a real integration point, not a mechanical rename, and needs its own task-level attention.
- [Risk] Migrating ~40 existing tests in `agentic_chat_provider_test.dart` from `agenticChatProvider.notifier` to `agenticChatProvider(sessionId).notifier` is mechanical but large; a missed occurrence silently tests the wrong instance instead of failing loudly. **Mitigation**: do it as a single mechanical pass (find/replace) followed by a full-suite run, not manual per-test edits.
- [Risk] The idle linger (Decision 3) and the disposal-prevention it briefly grants overlap with the reconciliation fetch (Decision 5) in a way that's easy to get subtly wrong — e.g. triggering a reconciliation fetch on every redisplay even when the instance never actually left its linger window, doubling network calls instead of the intended zero-cost reuse. **Mitigation**: cover this explicitly in tests — redisplaying within the linger window must not trigger any fetch at all; only redisplaying a genuinely disposed instance triggers the (now cheap, cursor-based) reconciliation.
- [Trade-off] A session that is genuinely disposed (idle past its linger, no in-flight cycle) still does not receive full-chat-state live updates while not displayed — matching current behavior. Only kept-alive sessions get the incidental live-update benefit noted in Decision 4; the sessions-list activity bump (also Decision 4) applies regardless of disposal state, since it never depends on a live `agenticChatProvider` instance.
- [Risk] The sessions-list activity bump (Decision 4) is driven by per-event `created_at`, delivered over a push channel with no ordering guarantee across a reconnect. An out-of-order or replayed event could regress an already-newer displayed timestamp. **Mitigation**: apply the bump only if the incoming `created_at` is strictly newer than the timestamp already shown for that session, mirroring the same "trust the newest evidence, not delivery order" principle behind the rest of this design.

## Migration Plan

Pure client-side refactor: no server/API change, no persisted-data schema change (`Settings.agenticSessionId`'s on-disk meaning is unchanged). Ships as a single ordinary release; rollback is a normal revert. No feature flag — per project convention, this is a straight code change rather than a staged/flagged rollout.
