## Why

The session sensitivity level is unreliable in two scenarios: (1) loading an existing session always resets the indicator to the default (Personal) because the history response never carried the persisted level; (2) when a user adjusts sensitivity before sending the first message, the engine has no way to know — the session doesn't exist yet, so the corrective `PUT /sensitivity` fires only after the first cycle has already been processed at the wrong level.

## What Changes

- `MessagesResponse` gains a `sensitivity_level` field, populated from the loaded `ChatContext`
- `loadHistory()` applies the returned sensitivity to app state (both full-load and incremental paths)
- Flutter `getMessageHistory` parses and returns the sensitivity level alongside messages
- `ChatRequest` gains an optional `sensitivity_level` field; the engine applies it before processing when starting a new session
- Flutter includes the current sensitivity level in `POST /messages` when no session ID exists yet

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `sensitivity-indicator`: add requirements — sensitivity level is restored from history on session load, and is applied correctly on the first cycle of a new session

## Impact

- Engine: `domain/models.py` (`MessagesResponse`, `ChatRequest`), `domain/services.py` (`get_messages`, `chat`)
- Flutter: `agentic/services.dart` (`getMessageHistory`, `sendAgenticMessage`), `providers/agentic_chat_provider.dart` (`loadHistory`, `_dispatchUserMessage`)
- No API breaking changes — additive fields on existing request/response models
