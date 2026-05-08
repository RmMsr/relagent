## Context

The engine returns `sensitivity_level` in `ChatResponse` and can return `SystemAction` messages containing `approvals` (list of `Approval` objects) and `notification` (string). The app currently silently drops `SystemAction` messages — the `AgenticMessage.fromJson` maps the `system` role to `assistant`, loses the approvals, and the sensitivity level from responses is never stored. The engine already exposes REST endpoints for setting sensitivity (`PUT /session/{id}/sensitivity`), creating grants (`POST /session/{id}/grants`, `POST /grants`), but the app never calls them.

The existing message model (`AgenticMessage`) uses a flat structure with `AgenticRole { user, assistant, error }`. Messages are grouped by role in the UI via `_MessageGroup` and rendered by `_AgenticMessageBubble`. The chat provider (`AgenticChatNotifier`) manages messages as a flat `List<AgenticMessage>` and handles send/load flows. The SSE provider handles real-time updates and triggers incremental history loads.

## Goals / Non-Goals

**Goals:**
- Display the session sensitivity level on the chat page with color-coded visual feedback
- Allow users to change the sensitivity level for the current session
- Render `SystemAction` messages inline in the chat history (notifications as notes, approvals as actionable cards)
- Provide three resolution paths for approvals: adjust sensitivity, deny, grant (with scope + expiry)
- After any resolution action (sensitivity change, deny, grant), trigger a new agent run and remove/disable the stale approval UI
- Guide users toward adjusting sensitivity when the approval's level differs from the session level

**Non-Goals:**
- Engine-side deny handling (engine TODO — the app sends the deny intent, but the engine may not fully handle it yet)
- Managing global grants outside the approval flow (a dedicated grants management page)
- Persisting approval resolution state locally (the engine is the source of truth — resolved approvals won't appear in future history loads)
- Streaming/partial responses — the existing request/response model is unchanged

## Decisions

### D1: Extend `AgenticMessage` with a `system` role rather than introducing a separate message type

The current model uses a flat `AgenticMessage` with role-based rendering. Introducing a parallel type hierarchy (e.g., sealed class with `UserMessage | AssistantMessage | SystemMessage`) would require changing every call site that handles messages — the provider, the grouping logic, the history widget, TTS integration, and the SSE handler.

Instead, add `AgenticRole.system` and extend `AgenticMessage` with optional fields: `approvals` (list of approval data), `notification` (string), and `sensitivityLevel` (the approval's requested level). The `fromJson` parser recognizes `role: "system"` and populates these fields. Non-system messages leave them null.

**Alternative considered:** Sealed class hierarchy (`ChatItem` with subtypes). Cleaner type safety but high migration cost across the widget tree, provider, and grouping logic. Not justified for this change.

### D2: Sensitivity indicator as a `Stack` overlay on the chat page body

The indicator needs to float over the chat content and be always visible. A `Positioned` widget inside a `Stack` wrapping the chat body achieves this without modifying the `ListView` or `Column` layout. The indicator sits in the top-right corner as a small colored circle/chip, near the app bar actions where status information is expected. Tapping opens a bottom sheet with the level picker.

**Alternative considered:** AppBar action button. Blends with other actions and loses the persistent color-coded feedback. A floating element above the content provides constant visual context without occupying toolbar space.

### D3: Color mapping for sensitivity levels

Map the 5 engine levels to a fixed color scale:
- `OpenInformation` (1): Green (`Colors.green`)
- `Specific` (2): Teal/cyan (`Colors.teal`)
- `Personal` (3): Amber/orange (`Colors.orange`)
- `Confidential` (4): Deep orange (`Colors.deepOrange`)
- `Internal` (5): Red (`Colors.red`)

These colors work on both light and dark themes and follow the intuitive green-to-red severity gradient. Defined as a static mapping, not theme-dependent.

### D4: Approval card with grant/skip per approval, then a collective "Continue"

A `SystemAction` with N approvals renders as a group of approval cards followed by a "Continue" action area. Each individual approval card contains:
- **Header**: Approval purpose and component name, with the approval's sensitivity level shown as a colored badge
- **Sensitivity mismatch banner** (conditional): When the approval's sensitivity exceeds the session's current level, a prominent banner suggests adjusting the session sensitivity first. This includes a "Change to [level]" button.
- **Actions per card**: "Grant" and "Skip" (not "Deny" — the language is intentionally softer since skipping is not destructive, it just means the engine will work without that capability)
- **Grant options** (expandable): When "Grant" is tapped, an expansion reveals scope (session/global toggle) and expiry picker (chip selection from the predefined set). Confirming the grant fires `POST /session/{id}/grants` immediately and marks the card as granted.
- **Skip**: Marks the card as skipped (no API call — deny is the absence of a grant)

Below the approval cards, a **"Continue" button** becomes enabled once every approval has been addressed (granted or skipped). Pressing it calls `POST /session/{id}/continue` and shows the "Thinking..." state. If at least one approval was skipped, the button label could indicate this (e.g., "Continue without [component]" or "Continue with partial permissions").

After continuation, the entire approval group transitions to a resolved visual state (non-interactive, shows what was granted/skipped).

### D5: Separate state mutation from agent continuation

Grants and sensitivity changes are async state mutations. Agent continuation is a distinct, explicit action. There is no deny endpoint — deny is implicit: the user simply doesn't grant an approval, then continues.

**Three distinct operations:**
1. **Grant** (`POST /session/{id}/grants`) — fire-and-forget, returns simple status. The app can call this multiple times, once per approved approval.
2. **Sensitivity change** (`PUT /session/{id}/sensitivity`) — fire-and-forget, returns simple status. Can happen at any time during the approval resolution phase.
3. **Continue** (new: `POST /session/{id}/continue`) — triggers an agent run with whatever permission state currently exists, returns `ChatResponse`. This is also the engine's general recovery mechanism (e.g., resuming after errors).

**Multi-approval flow in the app:**
1. Engine returns a `SystemAction` with N approvals
2. The user resolves each approval individually: grant (with scope + expiry) or leave ungranted
3. The user may also adjust sensitivity during this phase
4. Once all approvals are resolved (or the user decides to proceed), the user triggers "Continue"
5. The app calls `POST /session/{id}/continue`, shows "Thinking...", receives a `ChatResponse`
6. Ungranted approvals = the engine enters a recovery path, working without the denied capabilities

**Deny is not an explicit action** — it's the absence of a grant. The UI shows each approval as grantable or skippable. The "Continue" button becomes active once the user has addressed all approvals (granted or explicitly skipped). If at least one approval is skipped, the continue implicitly forces the engine into recovery.

**Why no deny endpoint:** A deny doesn't add state — it's the lack of a grant. The engine doesn't need to store "this was denied" — it just needs to run and discover that the required grant is missing. This keeps the model clean and avoids a separate deny concept that doesn't fit well.

**The continue endpoint serves multiple purposes beyond approvals:**
- Resuming after approval resolution
- Recovering from engine errors
- Re-running after sensitivity changes (even outside the approval flow)
- Any future case where the session state changed and the agent should re-evaluate

### D6: Track sensitivity level in `AgenticChatState`

The provider state gains a `sensitivityLevel` field (enum mirroring the engine's 5 levels, defaulting to `Personal`). It's updated from:
1. `ChatResponse.sensitivity_level` after every `sendMessage` or `triggerAgentContinuation`
2. Explicitly when the user changes it via the sensitivity picker (optimistic update + API call)
3. On history load, from the initial context state (requires a new API call or deriving from the response)

The `sendAgenticMessage` service function is updated to parse and return the `sensitivity_level` from the response alongside the message.

### D7: Stale approval handling — disable on resolution, remove on re-run response

When the user takes any resolution action on an approval card:
1. The card immediately transitions to a "resolved" visual state (grayed out, shows the action taken)
2. The re-run is triggered
3. When the re-run response arrives (new assistant message or new SystemAction), the flow continues normally

If the user adjusts sensitivity (not from an approval card, but from the floating indicator), any pending approval cards in the current message list become stale. The provider marks all unresolved approval messages as "stale" when sensitivity changes, and the UI shows them as disabled with a note like "Sensitivity changed — approvals invalidated".

### D8: Approval model in Dart mirrors the engine's Approval/Grant structures

Rather than inventing a separate app-side model, the Dart types mirror the engine's Pydantic models:
- `SensitivityLevel` enum with 5 values matching the engine
- `ApprovalType` enum (`none`, `data/out`)
- `ApprovalData` class with fields: `id`, `type`, `component`, `purpose`, `allowedParameters`, `sensitivity`, `granted`, `expiresAt`, `note`
- `GrantRequest` class for building the `POST` body: `approvalType`, `component`, `allowedParameters`, `maxSensitivity`, `expiresAt`

These are defined in `models.dart` alongside the existing types.

## Risks / Trade-offs

**[Risk] Engine continuation endpoint does not exist yet** → `POST /session/{id}/continue` needs to be added to the engine. The grant and sensitivity endpoints remain as-is (simple status responses). The app should gracefully handle a missing continue endpoint during the transition (e.g., show an error rather than silently failing).

**[Risk] Approval cards rendered from history may be stale** → When loading history, `SystemAction` messages with approvals that have `granted: true` should render as already-resolved. The app should not show action buttons for approvals that were already granted in a previous session.

**[Risk] Sensitivity change + re-run race condition** → The `PUT /sensitivity` call and the subsequent `POST /messages` are sequential. If the sensitivity update fails, the re-run should not be triggered. The provider chains these calls and handles errors between them.

**[Risk] Color accessibility** → The green-to-red scale may be difficult for colorblind users. Mitigated by also showing the level name as text alongside the color indicator, not relying on color alone.

**[Trade-off] Flat model extension vs. type hierarchy** → Adding optional fields to `AgenticMessage` is less type-safe than a sealed hierarchy, but avoids a large refactor. The `system` role is rare enough that the null-field overhead is minimal.

**[Trade-off] No local persistence of grant state** → The app doesn't cache which grants have been created. If the user force-closes during a grant flow, the grant exists server-side but the app won't know. The next history load will show the resolved state from the engine.
