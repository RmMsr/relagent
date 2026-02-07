# Change: Add Agentic Chat Page

## Why

The current simple chat connects directly to any OpenAI-compatible API. The new agentic chat page will be the frontend for the Relagent engine, providing persistence on the server side and enabling future agentic capabilities (tool use, memory, MCP integration).

## What Changes

- Add new **Agentic Chat Page** as the default app page
- Add **Engine URL** and **Basic Authentication** settings for engine connection
- Persist `session_id` locally to maintain conversation context across app restarts
- Fetch message history from engine API on app load
- Clear chat resets both messages and `session_id`
- Reuse existing voice input/output and UI patterns from simple chat

## Impact

- Affected specs: `agentic-chat` (new), `user-settings` (modified)
- Affected code:
  - `lib/pages/agentic_chat_page.dart` (new)
  - `lib/providers/agentic_chat_provider.dart` (new)
  - `lib/models/settings.dart`
  - `lib/providers/settings_provider.dart`
  - `lib/router/app_router.dart`
  - `lib/pages/settings_page.dart`
