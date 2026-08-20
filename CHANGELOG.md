# Changelog

All notable changes to Relagent are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The engine and the apps ship with identical version. Keep both at the same
release for best compatibility. When only one part changes, the other receives
a no-change version bump to stay in sync.

## 0.1.28 — Reproducible builds

### Internal

- Fixed F-Droid reproducible-build verification (pinned build paths that were leaking into compiled binaries). No user-facing changes in this release.

## 0.1.27 — Native mic routing and instant-save settings

### Added

- **Native Android mic routing.** A single MicRouter now owns audio routing end to end, replacing three uncoordinated writers of routing state. Recording surfaces show a badge for the active input device, and long-pressing the record button lets you override the automatic Bluetooth-first choice.
- **Settings Instant-save.** Model picks, backend switch, continuous voice, listening duration, and TTS speed/speaker now apply immediately. Free-text connection fields and credentials stay staged behind a single Apply action that runs a live health check before committing.

### Changed

- Approval cards now lead with the plain-language purpose summary, demoting the technical type/component detail to a line below.

### Fixed

- Duplicated ASR text no longer appears after switching input devices.
- Bluetooth mic routing now requires Android 12+; the old, unreliable legacy SCO path was removed.

### Internal

- Reproducible Android build fixes for F-Droid CI (pub-cache path pinning).

## 0.1.26 — Dark mode, share-sheet invocation, bundled offline inference

### Added

- **Bundled offline inference.** Relagent can now run fully offline out of the box: the engine can embed a local llama.cpp model server instead of requiring an external inference provider, with friendly retryable errors if it's still warming up.
- **Invoke from anywhere.** Share text into Relagent from any app, or select text and choose "Ask Relagent", to start a new session with that context.
- **Import speech models from local storage**, instead of only downloading them.
- **"Continue without" button** on stuck approval cycles, declining all pending approvals and continuing in one step.
- Session sensitivity level now persists and carries over to new sessions.
- Tool-call errors show Retry and Cancel side by side.

### Changed

- Full dark-mode-aware theming across chat, settings, and voice controls, replacing hardcoded colors with theme-aware ones throughout the app.

### Fixed

- Chat input no longer overflows the screen when typing long messages.
- Chat background and various dark-mode color inconsistencies.
- Web search tool now falls back across multiple providers (Mojeek, DuckDuckGo, Startpage, Brave) instead of failing outright when one is rate-limited or blocked.
- Engine compatibility with newer pydantic_ai/OpenAI SDK releases.

### Internal

- CI build caching and reliability improvements; dependency updates.

## 0.1.24 — Wide-display chat layout

### Changed

- Chat messages are now capped at 800px and centered on wide displays for better readability; the input bar stays full-width.

### Internal

- Dependency updates.

## 0.1.23 — Strict-ordering chat

### Upgrade notes

- **Breaking API change.** `POST /sessions/{id}/grants` and `POST /sessions/{id}/reject_approvals` are replaced by per-approval routes: `POST /sessions/{id}/approvals/{approval_id}/grant` and `POST /sessions/{id}/approvals/{approval_id}/decline`.
- **Complete pending approvals before upgrading.** Unsettled approvals at upgrade time remain readable but resolve better in the new UI.

### Added

- **Queued messages.** Type a message while the engine is busy and it queues automatically, dispatching once the current cycle finishes.
- **Stop control on approvals.** A "Stop and ask something else" button lets you settle an awaiting approval cycle without invoking the agent.
- **Continue button for stuck cycles.** Re-issue a failed continuation directly from the approval group.
- **`POST /sessions/{id}/stop` endpoint.** Settles the in-flight cycle by declining all undecided approvals.

### Changed

- **Strict message ordering.** Interactions now enforce at most one cycle in flight per session, with every message carrying a `final` flag.
- **"Skip" renamed to "Continue without."** Approval cards use the clearer label.
- **Smart retry.** The retry button on error messages now correctly re-issues `/continue` instead of re-posting the user message.

### Internal

- Minor improvements to comments, tests, and dependencies.
