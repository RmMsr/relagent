## Context

The main Settings page (`apps/lib/pages/settings_page.dart`, routed at `/settings`) and the Voice Models screen (`ModelCatalogBrowser` in `apps/lib/widgets/model_management_section.dart`, pushed at `/voice-models` on top of Settings) share one editing flow: Voice Models is always reached from Settings, and Flutter keeps a pushed route's ancestors mounted (obscured, not disposed) underneath it. Credentials (passwords, API keys) are not part of the `Settings` model — they live in secure storage via `CredentialsManager`, orchestrated by Settings-page-local `TextEditingController`s, never shared with Voice Models directly.

## Goals / Non-Goals

**Goals:**
- Selection/toggle fields (model picks, backend switch, continuous voice, background-listening duration, TTS speed/speaker) apply immediately, with no staging and no Save step.
- Free-text Connection fields and credentials still require an explicit commit, since autosaving mid-keystroke is wasteful and autosaving a half-typed secret is harmful.
- A single Apply action, present on both screens, commits whatever's staged and jumps to Chat.
- Apply never silently ships an untested credential/URL change.
- Apply is a true single tap in the common case (nothing staged).
- Voice Models' back navigation is always instant; only Settings' own back navigation needs to guard against losing staged text/credential edits.

**Non-Goals:**
- Not reworking `CredentialsManager`/secure storage.
- Not lifting raw credential text into shared provider state — the verification gate only needs a trust boolean, not the secret values.
- Not wiring a "reset to app defaults" entry point — orphaned in an earlier round, out of scope here.

## Decisions

**`pendingSettingsProvider`** (`NotifierProvider.autoDispose<PendingSettingsNotifier, Settings>`) holds a draft `Settings`, seeded via `build() => ref.watch(settingsProvider)`. In use, only four fields are ever written into the draft (`simpleChatBaseUrl`, `simpleChatModel`, `primeMessage`, `engineBaseUrl`) — every other field is written straight to `settingsProvider`, so the draft never diverges from settings for those fields and no separate "is this staged" tracking is needed for them. The provider is kept alive for the whole flow by being `ref.watch`-ed in `SettingsPage.build()`; since Settings stays mounted under Voice Models, that single watch covers both screens.

**`credentialsPassProvider`** (`NotifierProvider.autoDispose<CredentialsPassNotifier, bool>`) is a trust flag, default `true`. `invalidate()` is called from every credential/URL/backend-relevant edit site (chat and engine URL fields, chat and engine model/username/password/API-key controllers, backend switch, basic-auth toggles, clear-credentials actions) — but not from prime message or other fields that don't affect the health-check request. `markVerified(bool)` is called after the Test Connection buttons and after Apply's own live check. Like `pendingSettingsProvider`, it's kept alive by an unconditional `ref.watch(credentialsPassProvider)` in `SettingsPage.build()` — without this, the provider (never otherwise watched, only `ref.read`) disposes and silently resets to `true` between an invalidating edit and the next Apply tap, defeating the gate entirely.

**Apply's logic** (identical on both screens except for the "not verified" branch): if `credentialsPassProvider` is `true`, commit whatever's staged and navigate to Chat immediately — no health check, no interruption, even when nothing at all was staged. If `false`: on Settings, commit and run a live health check there (using the freshest local controller values), showing a "close anyway?" prompt only if it fails; from Voice Models, which has no access to the credential fields to check them, show `showUnverifiedCredentialsDialog` (Review Settings / Close Anyway) before doing anything.

**"Review Settings" always lands on the Connection tab.** Voice Models' back navigation and Apply's "review" path can't reach Settings' `TabController` directly (they're siblings in the navigator, not parent/child in the widget tree). `settingsTabRequestProvider` (same autoDispose-plus-keep-alive-watch shape as `credentialsPassProvider`) carries a one-shot `int?` request; Voice Models sets it to `0` before popping, and Settings — now using an explicit `TabController` (`TickerProviderStateMixin`, not `SingleTickerProviderStateMixin`, since the controller can in principle be recreated if `tabs.length` changes at runtime) instead of `DefaultTabController` — applies and clears the request via `ref.listen` in `build()`.

**Autocomplete-backed fields (chat URL, chat model, engine URL) attach their change-listener once per controller instance, and suppress it during a programmatic resync.** Each field is wrapped in a custom `_AutocompleteWithFocusLoss`, whose `fieldViewBuilder` runs on every rebuild of the Settings page — including rebuilds triggered by something as unrelated as a model pick on Voice Models (which changes `settingsProvider`, which Settings also watches). The underlying `TextEditingController` persists across rebuilds (owned by `RawAutocomplete`'s own state), so re-registering a listener on every `fieldViewBuilder` call would leak duplicate listeners; `_SettingsPageState` tracks each field's controller identity and only attaches once. Separately, a post-frame callback resyncs that controller's text from the draft whenever it drifts (e.g. the field starts empty on first build and must be seeded) — that assignment fires the same listener used for genuine typing, so a boolean flag (set immediately around the assignment) tells the listener to skip its `updateDraft`/`invalidate` work during a resync. Without both fixes together, a resync — not a real edit — could spuriously invalidate `credentialsPassProvider`.

**Discard dialog is 2-way, not 3-way.** `smartBack`'s confirmation (Cancel / Leave Anyway) only fires on Settings' own back arrow, since that's the only pop that actually leaves the flow and disposes the draft — popping Voice Models back to Settings never loses anything, so it's an unconditional `context.pop()`.

## Risks / Trade-offs

- **Voice Models' Apply discards `commitPendingSettings`'s failure signal** (unlike Settings' Apply, which shows a failure banner on a persistence error) — an accepted asymmetry, not fixed, since the only fields Voice Models can commit are the same four staged text fields and the failure mode is a rare `SharedPreferences` write error.
- **No end-to-end test covers Apply's credential-ordering/verification interaction** — exercising it requires a widget-test harness spanning both screens plus mocked health-check services, judged disproportionate effort; the underlying pieces (`credentialsPassProvider`, `commitPendingSettings`'s engine-URL-before-credentials ordering) are unit- and review-verified individually.
- **`SettingsNotifier.resetToDefaults()` is now an orphaned public method** (its only caller, a "reset to app defaults" UI entry point, was removed) — left in place as dead-but-harmless API, not cleaned up.

## Migration Plan

None — behavior-only. No changes to persisted `Settings` shape or credential storage.

## Open Questions

None outstanding.
