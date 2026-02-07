# Change: Backend Selection with Separate Chat Pages

## Why

Users should see just "the chat" without needing to know about internal backend differences. The simple chat (OpenAI-compatible) is nearly feature-complete and stable. The agentic chat (Relagent Engine) is the main focus and will receive many more features. Keeping them as separate pages prevents agentic development from risking regressions in the stable simple chat.

## What Changes

- Add backend type selection in settings (OpenAI-compatible vs Relagent Engine)
- Router shows the appropriate chat page based on selected backend
- Keep both base URLs in settings so users can switch back and forth
- Both chat pages remain separate, each focused on their backend
- No changes to existing chat page implementations

## Impact

- Affected specs: `user-settings` (modified)
- Affected code:
  - `lib/models/settings.dart` - Add `ChatBackendType` enum and `selectedBackend` field
  - `lib/providers/settings_provider.dart` - Add backend selection persistence
  - `lib/pages/settings_page.dart` - Add backend selection UI (radio buttons)
  - `lib/router/app_router.dart` - Route `/` to correct page based on backend setting
