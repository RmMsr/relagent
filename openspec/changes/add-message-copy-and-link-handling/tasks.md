## 1. Shared message actions widget

- [x] 1.1 Create `apps/lib/widgets/message_markdown_actions.dart` with `copyMessageText(BuildContext, String)`, `linkTapHandler(BuildContext)`, and the `MessageCopyButton` widget as described in design.md
- [x] 1.2 Implement `copyMessageText`: `Clipboard.setData(ClipboardData(text: ...))` plus a `SnackBar` confirmation
- [x] 1.3 Implement `linkTapHandler`: `AlertDialog` showing the destination URL with Cancel/Open actions; on confirm, guard with `canLaunchUrl` and call `launchUrl`; on failure or unsupported URL, show a `SnackBar` ("Couldn't open link") instead of failing silently
- [x] 1.4 Implement `MessageCopyButton`: borderless 18px icon button matching the app's other unbordered secondary actions (see task group 5 for the styling revision)

## 2. Wire into simple chat (`apps/lib/chat/widgets.dart`)

- [x] 2.1 Pass `onLinkTap: linkTapHandler(context)` to the user-message `GptMarkdown` call (~line 509)
- [x] 2.2 Pass `onLinkTap: linkTapHandler(context)` to the single-paragraph assistant `GptMarkdown` fallback (~line 581) and the per-paragraph loop (~line 602)
- [x] 2.3 Add `MessageCopyButton` next to the existing retry button for user messages
- [x] 2.4 Add `MessageCopyButton` next to the existing TTS button for assistant messages

## 3. Wire into agentic chat (`apps/lib/agentic/widgets.dart`)

- [x] 3.1 Pass `onLinkTap: linkTapHandler(context)` to the assistant `GptMarkdown` fallback (~line 616) and the per-paragraph loop (~line 637)
- [x] 3.2 Add `MessageCopyButton` into `_MessageActionsRow` alongside the speaker button and stats toggle (assistant messages)
- [x] 3.3 Add `MessageCopyButton` next to agentic user message bubbles (plain `Text`, no markdown/link handling needed)

## 4. Verification

- [x] 4.1 Manually verify: copying a multi-paragraph assistant message preserves paragraph breaks when pasted elsewhere
- [x] 4.2 Manually verify: tapping a link shows the confirmation dialog with the correct destination URL, Cancel leaves the app unchanged, and Open launches the link
- [x] 4.3 Manually verify: an unlaunchable URL (e.g. malformed scheme) shows the "couldn't open" feedback rather than doing nothing
- [x] 4.4 Run `fvm flutter analyze` and fix any warnings introduced by the new code

## 5. Post-review fixes

- [x] 5.1 Restyle `MessageCopyButton` from an outlined button to a borderless icon button matching the stats-toggle pattern
- [x] 5.2 Reposition the copy button to second in each action row (after retry/TTS/speaker, before stats)
- [x] 5.3 Add `<queries>` entries for `ACTION_VIEW` with `https`/`http`/`mailto`/`tel` schemes to `apps/android/app/src/main/AndroidManifest.xml` — on-device testing found links always failed with "Couldn't open link" because Android 11+ package-visibility restrictions blocked `canLaunchUrl` without an explicit manifest declaration
