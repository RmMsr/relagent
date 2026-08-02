## 1. Shared infrastructure

- [x] 1.1 `credentialsPassProvider` (`apps/lib/providers/credentials_pass_provider.dart`): autoDispose bool, `invalidate()`/`markVerified(bool)`, default `true`
- [x] 1.2 `settingsTabRequestProvider` (`apps/lib/providers/settings_tab_request_provider.dart`): autoDispose one-shot tab-index request
- [x] 1.3 `SettingsApplyBar` (`apps/lib/widgets/settings_apply_bar.dart`): single-button bottom bar shared by both screens
- [x] 1.4 `settings_navigation.dart`: `commitPendingSettings` (engine URL + the four staged text fields only), `smartBack` (2-way discard confirmation), `showUnverifiedCredentialsDialog`

## 2. Voice Models screen

- [x] 2.1 Model selection writes directly to `settingsProvider` (`updateSelectedAsrModelId`/`updateSelectedTtsModelId`), not a staged draft
- [x] 2.2 Back arrow and Escape are a plain, unguarded `context.pop()`
- [x] 2.3 Apply: commit-and-close when `credentialsPassProvider` is trusted; otherwise show the unverified-connection dialog, requesting the Connection tab and popping on "Review Settings," or committing and closing on "Close Anyway"

## 3. Settings page

- [x] 3.1 Backend switch, continuous-voice toggle, background-listening duration, TTS speed/speaker write directly to `settingsProvider`
- [x] 3.2 Chat/engine URL, chat model, prime message stay staged via `pendingSettingsProvider`; credential controllers invalidate `credentialsPassProvider` on edit (URL/backend/credential fields only, not prime message)
- [x] 3.3 Apply: commits credentials and the staged draft (preserving engine-URL-before-engine-credentials write ordering), then applies the verification gate — skip the live check when already trusted, otherwise run it and interrupt only on failure
- [x] 3.4 Back arrow guards on staged text/credential changes via `smartBack`
- [x] 3.5 Explicit `TabController` (`TickerProviderStateMixin`) replacing `DefaultTabController`, driven externally via `settingsTabRequestProvider`

## 4. Verification

- [x] 4.1 `flutter analyze` clean on all touched files
- [x] 4.2 Full test suite passing (326 tests, 1 pre-existing skip)
- [x] 4.3 Each implementation task reviewed against live source by a task-scoped code reviewer; a whole-branch review additionally caught and fixed a Critical bug (`credentialsPassProvider` never kept alive, silently resetting) before merge-readiness
- [x] 4.4 Manual testing surfaced two further bugs after the whole-branch review — spurious verification loss from an Autocomplete-field listener/resync interaction, and "Review Settings" not landing on the Connection tab — both root-caused and fixed
- [ ] 4.5 Full interactive click-through on a running device — not achievable in the available sandboxed environment (no browser automation extension, no working Android emulator, no input-simulation on the Linux desktop target); manual testing by the user on a real device surfaced the two bugs fixed in 4.4, and is recommended to continue before this change is fully trusted
