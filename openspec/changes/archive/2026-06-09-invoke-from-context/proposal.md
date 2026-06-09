## Why

Users frequently want the assistant to act on text they are reading or writing in another app (or elsewhere in Relagent) — "explain this", "find alternative phrases", "verify this". Today they must switch to Relagent, start a chat, and manually copy-paste the text and type the request. Letting the assistant be invoked directly from the platform's text-selection / share flow removes that friction and makes the assistant useful in any context.

## What Changes

- Register Relagent as a target for the platform's "selected text" entry points. On Android this is the text-selection context menu (`ACTION_PROCESS_TEXT`) and the share sheet (`ACTION_SEND` for `text/plain`).
- When invoked externally, the app opens (or comes to front) on a dedicated invocation screen that is pre-filled with the received text.
- The invocation screen lets the user add a free-text instruction (universal, no presets in this iteration) and send.
- Sending starts a **new** chat session whose first message combines the instruction and the selected text, then routes to the chat page showing the response.
- Results stay inside Relagent — there is no round-trip of the result back to the originating app.
- Other platforms (iOS / Linux / Web) are not blocked: where the framework already surfaces the same selected-text or share input, the shared invocation flow handles it. No platform-specific effort beyond Android is in scope for this iteration.

Out of scope (good later additions): user-defined instruction presets, returning the result to the source app, in-app text-selection action.

## Capabilities

### New Capabilities

- `context-invocation`: Receiving selected/shared text from an external (or platform) entry point, presenting an invocation screen to add a free-text instruction, and dispatching it as the first message of a new assistant session.

### Modified Capabilities

<!-- None: the new session is started through existing chat/session behavior; routing adds a new entry point rather than changing existing chat or routing requirements. -->

## Impact

- **Android**: `apps/android/app/src/main/AndroidManifest.xml` — add incoming `intent-filter`s for `ACTION_PROCESS_TEXT` and `ACTION_SEND` (`text/plain`) to `MainActivity`.
- **Routing**: `apps/lib/router/app_router.dart` — add an invocation route.
- **New UI**: an invocation screen under `apps/lib/pages/`.
- **Chat/session**: reuse existing new-session start (first message with null session id) in `apps/lib/providers/agentic_chat_provider.dart`; no change to the continuation/approval flow.
- **Dependencies**: a Flutter plugin to receive incoming intents (e.g. `receive_sharing_intent` / `app_links`) is likely required; `ProcessText` selection input may be available via the Flutter engine. Exact mechanism is a design decision.
