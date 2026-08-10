## Why

Chat and agentic messages render markdown via `GptMarkdown`, but two things are broken: copying an assistant reply loses paragraph breaks (assistant messages are split into one `GptMarkdown` widget per paragraph for TTS highlighting, so native text selection can't reliably reconstruct blank-line structure across separate widgets), and links render styled but do nothing on tap (`onLinkTap` is never wired up, despite `url_launcher` already being a dependency). Since link text in assistant messages is LLM-generated and may not match the actual URL, links also need a trust boundary before leaving the app.

## What Changes

- Add a per-message copy action that copies the raw message text (unrendered markdown source) directly to the clipboard, for any message rendered with `GptMarkdown` in both the simple chat and agentic chat views.
- Wire `onLinkTap` on every `GptMarkdown` call site with a single shared handler that shows a confirmation dialog displaying the destination URL, then launches it via `url_launcher` on confirm. Any scheme `url_launcher` supports is allowed through.
- Native drag-to-select text copying is left as-is; only the new explicit copy action is guaranteed to preserve paragraph structure.

## Capabilities

### New Capabilities
- `message-actions`: copy-to-clipboard and link-tap-confirmation behavior for markdown-rendered chat messages, shared across the simple chat and agentic chat surfaces.

### Modified Capabilities
(none — `chat-history` and `agentic-chat` gain new UI affordances but their existing requirements are unchanged)

## Impact

- `apps/lib/chat/widgets.dart`: user and assistant message bubbles (`GptMarkdown` at lines ~509, ~581, ~602) gain a copy button and `onLinkTap`.
- `apps/lib/agentic/widgets.dart`: assistant message bubbles (`GptMarkdown` at lines ~616, ~637) gain a copy button and `onLinkTap`; `_MessageActionsRow` gains a copy button. Agentic user messages are plain `Text` (no markdown) and only need the copy button.
- New shared widget/helper for the link-confirmation dialog and copy action, used by both files.
- No new dependencies — `url_launcher` (^6.3.2) is already in `apps/pubspec.yaml`.
