# Changelog

All notable changes to Relagent are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The engine and the apps ship with identical version. Keep both at the same
release for best compatibility.

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
