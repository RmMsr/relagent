## Context

`apps/lib/chat/widgets.dart` and `apps/lib/agentic/widgets.dart` both render chat messages with `GptMarkdown` (from the `gpt_markdown` package) and both split assistant messages into one `GptMarkdown` widget per paragraph (`_buildMessageBody`, using `splitRawParagraphs` from `apps/lib/tts/text_chunker.dart`) so the currently-speaking paragraph can be highlighted during TTS playback. Neither file passes `onLinkTap` to `GptMarkdown`, so `ATagMd`'s `config.onLinkTap?.call(url, linkText)` is always a no-op. `url_launcher` (^6.3.2) is already a pubspec dependency but currently unused. Shared, cross-feature widgets already live in `apps/lib/widgets/` (see `tts_chunk_controls.dart`, `version_info_widget.dart`). See `proposal.md` for the full motivation.

## Goals / Non-Goals

**Goals:**
- One shared implementation of the copy action and the link-confirmation flow, used identically by both chat surfaces.
- No change to the existing per-paragraph widget splitting or TTS highlighting behavior — the copy action reads from `message.text` directly, independent of how the message happens to be split for rendering.

**Non-Goals:**
- Not touching native `SelectableRegion` drag-to-select copy behavior — left exactly as it is today.
- Not adding rich-text/HTML clipboard output (no `super_clipboard`) — the copy action writes plain markdown source text only.
- Not restricting which URL schemes can be launched — any scheme `url_launcher` can handle is allowed through once the user confirms.

## Decisions

**Shared helper location**: new file `apps/lib/widgets/message_markdown_actions.dart`, following the existing convention of shared widgets living in `apps/lib/widgets/`. It exports:
- `Future<void> copyMessageText(BuildContext context, String text)` — writes `text` to the clipboard via `Clipboard.setData(ClipboardData(text: text))` and shows a brief `SnackBar` confirmation ("Copied to clipboard"). Called with the message's raw `message.text`, not any rendered/derived string, so paragraph breaks are always preserved verbatim.
- `void Function(String url, String title) linkTapHandler(BuildContext context)` — returns a closure suitable for `GptMarkdown.onLinkTap` that shows an `AlertDialog` with the destination URL and Cancel/Open actions; on confirm, calls `url_launcher`'s `launchUrl`, wrapped in a check so a launch failure surfaces a `SnackBar` ("Couldn't open link") instead of failing silently.
- A small `MessageCopyButton` widget (18px icon, borderless, `VisualDensity.compact`) matching the app's other unbordered secondary actions (e.g. the stats toggle in the agentic actions row) rather than the outlined retry/TTS buttons — the border read as unnecessary chrome for a low-emphasis action. Positioned second in each action row (after retry/TTS/speaker, before stats), not first.

Alternative considered: put the copy/link logic directly in each file (duplicated). Rejected — the two files already share `splitRawParagraphs` from `text_chunker.dart` for the same reason (keeping paragraph semantics identical across surfaces); duplicating the copy/link logic would let the two surfaces drift.

**Wiring into chat/widgets.dart**: pass `onLinkTap: linkTapHandler(context)` to all three `GptMarkdown` call sites (user bubble, single-paragraph assistant fallback, per-paragraph assistant loop). Add `MessageCopyButton` next to the existing retry button row for user messages, and next to the existing TTS button for assistant messages.

**Wiring into agentic/widgets.dart**: pass `onLinkTap: linkTapHandler(context)` to both `GptMarkdown` call sites (assistant fallback and per-paragraph loop). Add `MessageCopyButton` into the existing `_MessageActionsRow` (assistant messages only, alongside the speaker button and stats toggle). Agentic user messages render as plain `Text` (no markdown, no links) — add a `MessageCopyButton` next to them directly since there's no existing action row to extend.

**Confirmation dialog applies uniformly**: same `onLinkTap` handler used for every call site regardless of message role (user vs. assistant, chat vs. agentic) — confirmed with the user as the simplest option that avoids inconsistent link behavior depending on who "sent" the message.

**Android manifest `<queries>` entries**: `apps/android/app/src/main/AndroidManifest.xml` only declared package-visibility for `PROCESS_TEXT`. Since Android 11 (API 30), `url_launcher`'s `canLaunchUrl`/`launchUrl` return false for any scheme without a matching `<queries>` entry, regardless of whether a handling app is actually installed — this was caught on-device (the confirm dialog appeared, but every link failed with "Couldn't open link"). Added `ACTION_VIEW` query entries for `https`, `http`, `mailto`, and `tel`, matching `url_launcher`'s own documented guidance, to cover the schemes chat content realistically contains.

## Risks / Trade-offs

- [Confirmation dialog adds friction even for obviously-safe links] → Accepted trade-off: since link text can be LLM-generated and doesn't have to match the actual URL, showing the destination before navigating is a deliberate security measure, not an oversight.
- [`launchUrl` behavior and supported schemes vary by platform (mobile vs. web)] → Guard with `canLaunchUrl` before attempting to launch, and surface a `SnackBar` on failure per the spec's "Destination cannot be opened" scenario, rather than assuming success.
- [Adding a visible copy icon to every message increases visual density] → Reuse the existing compact icon-button styling already present for TTS/retry actions so it doesn't read as a new UI element, just an additional action in the same family.

## Migration Plan

Pure additive UI change — no data migration, no feature flag needed. Rollback is a straight revert of the widget changes and the new shared file.
