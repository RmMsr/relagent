## Context

Relagent is a Flutter app (Android/iOS/Linux/Web) using Riverpod and `go_router`. Today the only way to start a chat is to open the app and type. The chat/session machinery already supports starting a fresh session: `AgenticChatNotifier.clearChat()` clears the active session id so the next message opens a new session, and `sendMessage(text)` dispatches it. The provider is a global `NotifierProvider`, so it can be driven from any route.

Startup flow: `/` shows `SplashPage`, which after a short delay routes to `/chat`. Android `MainActivity` is `launchMode="singleTop"`. The manifest currently only declares a `<queries>` block for `ACTION_PROCESS_TEXT` (so Relagent can call *other* text processors); it does not yet *receive* any selected-text or share intent.

This change adds an external entry point: selected/shared text from the platform arrives, the user adds a free-text instruction on a dedicated screen, and sending opens a new session pre-filled with instruction + quoted text.

## Goals / Non-Goals

**Goals:**
- Receive `text/plain` from the Android share sheet (`ACTION_SEND`) and from the text-selection context menu (`ACTION_PROCESS_TEXT`).
- Show an invocation screen pre-filled with the received text quoted, instruction area on top, cursor at the start.
- On send, always start a **new** session and route to the chat page — identical behavior whether the app was cold-started or already running.
- Keep the reception mechanism extensible toward images/files in a later iteration.

**Non-Goals:**
- User-defined instruction presets.
- Returning the result to the originating app (no round-trip).
- Receiving images/files now (only the plugin choice must not preclude it).
- iOS/Linux/Web native wiring beyond what the framework provides for free; iOS share-extension setup is explicitly deferred.

## Decisions

### Reception: `receive_sharing_intent` for share, platform channel for PROCESS_TEXT

Use `receive_sharing_intent` for the `ACTION_SEND` (`text/plain`) path. It exposes both the initial (cold-start) intent and a stream of subsequent (warm) intents, and — decisively for the next iteration — it natively supports shared **images, videos, and files** via `ACTION_SEND`/`ACTION_SEND_MULTIPLE`. `app_links` was rejected: it only handles URI deep links and cannot receive shared media.

`receive_sharing_intent` does **not** handle `ACTION_PROCESS_TEXT` (the text-selection context-menu entry, which is the most natural trigger for "explain this" / "rephrase this"). Add a thin platform channel in `MainActivity` that reads `Intent.EXTRA_PROCESS_TEXT` on launch/`onNewIntent` and forwards it to Dart. Both paths feed the same in-app pending-invocation holder, so downstream flow is identical.

Alternative considered — drop PROCESS_TEXT for v1 and rely on the share sheet only: rejected because PROCESS_TEXT is the primary affordance for the stated use cases; the platform channel is small.

### Pending-invocation holder decouples reception from routing

A Riverpod provider holds the incoming text as a pending invocation. Reception (plugin + channel) writes to it; routing reads it. This cleanly handles startup ordering:
- **Cold start**: the initial intent is captured during init; `SplashPage`, after its existing init/delay, routes to the invocation screen when a pending invocation exists, otherwise to `/chat` as today.
- **Warm start**: the warm intent (stream / channel callback) sets the holder and navigates to the invocation screen directly.

This avoids passing intent data through `go_router` `extra` across an async startup boundary and keeps a single code path for both timings.

### Always start a new session

The invocation screen's Send action calls `clearChat()` (resets session id + messages) then `sendMessage(composed)` then `context.go('/chat')`. Because session start is just "send with a null session id", cold and warm behave identically — a warm share while mid-conversation starts a fresh session rather than appending. This matches the user's mental model: one invocation = one new session.

### Message composition: instruction on top, quoted text below, cursor at start

The invocation screen's text field is initialized to a leading blank region followed by the selected text rendered as a Markdown blockquote (`> ` per line). The cursor is placed at offset 0 so the user types the instruction immediately. The entire field content becomes the first message; an empty instruction is allowed (the assistant simply receives the quoted text).

Alternative considered — separate "instruction" and "text" fields: rejected for v1 to keep the screen simple and the composed message a single editable buffer.

### New invocation route

Add a route (e.g. `/invoke`) rendering the invocation screen. Reuses the existing global chat provider for dispatch; no change to chat, session-continuation, or approval requirements.

## Risks / Trade-offs

- **Blockquote mangles code/Markdown selections** → Accept for v1; richer formatting and presets are deferred follow-ups.
- **Engine not configured / unreachable on cold start** → Send goes through the normal chat path, so failures surface as the usual chat error state; no special handling beyond that in v1.
- **`receive_sharing_intent` + `go_router` navigation timing** (navigating before a navigator exists) → Route only after init completes via the splash gate (cold) and guarded navigation for warm intents.
- **PROCESS_TEXT platform channel is bespoke** → Keep it minimal (read extra, forward string); isolated to `MainActivity` and one Dart channel.
- **iOS/Linux/Web parity** → Android-only native wiring this iteration; the shared Dart flow (holder → invocation screen → new session) is platform-agnostic, so other platforms can be enabled later without reworking it.

## Migration Plan

Additive feature, no data migration. New manifest intent-filters, one plugin dependency, one platform channel, one route + screen, one holder provider. Rollback = revert the change; existing launch/chat behavior is untouched when no invocation intent is present.

## Open Questions

- Should Send require a non-empty instruction, or is sending the quoted text alone acceptable? (Current default: allow empty.)
- Exact blockquote rendering for multi-paragraph / pre-formatted selections — confirm during implementation.
