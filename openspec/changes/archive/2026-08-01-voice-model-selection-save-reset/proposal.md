## Why

Selecting a model, switching the chat backend, or flipping a toggle are single, low-risk actions — requiring an explicit Save step before they take effect adds friction without protecting anything. Free-text fields (URLs, prime message) and credentials are different: typing is inherently multi-step, and auto-saving a half-typed secret would be harmful. This change makes selection/toggle fields apply instantly everywhere in the Settings flow, and replaces a two-button Save/Reset pair with a single Apply action that commits whatever's still staged (URLs, credentials) and closes the whole flow in one tap — gated by a connection-verification check so an untested credential/URL change is never shipped silently.

(A separate, unrelated bug — imported models being silently deselected on restart because a stale-selection validator only checked catalog/downloaded models, not the imported-models registry — was fixed earlier and is not part of this change; see `apps/lib/providers/settings_provider.dart`'s `_validateModelSelections`.)

## What Changes

- Selecting a model on the Voice Models screen (`/voice-models`) applies immediately — tapping a card writes straight to persisted settings, same as the chat backend switch, continuous-voice toggle, background-listening duration, and TTS speed/speaker on the main Settings page.
- Chat/engine base URL, chat model name, prime message, and credentials (passwords/API keys) remain staged behind an explicit commit.
- Both the Settings page and the Voice Models screen expose a single Apply action ("save and close"): it commits whatever's staged anywhere in the flow and jumps straight to Chat.
- Apply is gated by connection verification: if the currently-active connection settings haven't been verified since they last changed, Apply either runs a live check right there (on Settings, which has the credential fields) or sends the user back to the Connection tab with a confirmation prompt (from Voice Models, which can't run that check itself).
- Settings' back arrow warns before discarding staged text/credential changes (a simple Cancel / Leave Anyway choice). Voice Models' back arrow is always an instant, unguarded pop — nothing is ever lost by it, since Settings and its staged draft stay mounted underneath.
- Download and Delete actions on model cards are unaffected — they act immediately regardless, since they mutate what's on disk rather than which model is selected.
- The import action's icon changed from `Icons.upload_file` to `Icons.file_open`, since the action opens a local file picker rather than uploading anywhere (cosmetic, bundled with this change since it touches the same screen).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `model-catalog`: model selection on the catalog browser is instant; the browser gains a shared Apply action gated by connection verification.
- `user-settings`: selection/toggle fields on the Settings page (backend, continuous voice, background-listening duration, TTS speed/speaker) apply instantly; the page gains a single Apply action, a connection-verification gate, and a discard-confirmation on back navigation.

## Impact

- **apps/lib/providers/pending_settings_provider.dart** — shared, auto-disposing draft of `Settings`, scoped in use to the four staged free-text fields (chat base URL, chat model, prime message, engine base URL); everything else reads/writes `settingsProvider` directly.
- **apps/lib/providers/credentials_pass_provider.dart** — shared trust flag gating Apply: `invalidate()` on any credential/URL/backend-relevant edit, `markVerified(bool)` after a health check.
- **apps/lib/providers/settings_tab_request_provider.dart** — one-shot signal letting Voice Models request the Settings page land on the Connection tab when sending the user back to resolve unverified credentials.
- **apps/lib/widgets/settings_apply_bar.dart** — single-button bottom bar shared by both screens.
- **apps/lib/utils/settings_navigation.dart** — shared `commitPendingSettings`, `smartBack` (discard-confirmation), `showUnverifiedCredentialsDialog`.
- **apps/lib/widgets/model_management_section.dart** — model cards write directly to `settingsProvider`; the browser's AppBar back arrow is a plain pop; bottom bar is the shared Apply action.
- **apps/lib/pages/settings_page.dart** — selection/toggle fields write directly to `settingsProvider`; Apply commits staged text/credentials and applies the verification gate; back arrow is guarded; uses an explicit `TabController` (not `DefaultTabController`) so it can be driven externally by `settingsTabRequestProvider`.
- No new pub dependencies required.
