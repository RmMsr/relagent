## Context

The engine's chat protocol (`engine/README.md`) is REST + SSE: `POST
/messages`, `POST /sessions/{id}/continue`, per-approval `grant`/`decline`
endpoints, and `POST /sessions/{id}/stop`. The only existing implementation
of this protocol is in `apps/lib/agentic/` (Flutter app), which is mostly
pure Dart already but is entangled with a few Flutter-only concerns (see
Decisions). `tools/voice_catalog` establishes the existing precedent for a
standalone Dart CLI in this repo (`args`-based, `executables:` entry in
`pubspec.yaml`), and `engine/settings.py` establishes the existing
convention for ini-based local configuration
(`~/.local/share/org.venkado.<app-id>/settings.ini`).

## Goals / Non-Goals

**Goals:**
- Reuse the engine protocol implementation rather than reimplementing it.
- Keep the REPL's terminal handling simple: scrollback + a redrawn input
  region, not a full-screen TUI.
- Give the CLI a security posture for its auth token comparable to what
  the Flutter app gets from `flutter_secure_storage`.

**Non-Goals:**
- Cross-platform token storage (macOS/Windows). This design is Linux/D-Bus
  specific for secure storage.
- Preserving `apps/lib/agentic/`'s exact file boundaries during extraction
  — files may be reorganized within the new package as long as behavior is
  unchanged.

## Decisions

**Extract shared protocol logic into a new package, `dart_packages/
agentic_client`, rather than duplicating it in the CLI or making the CLI a
Flutter target.**
Alternatives considered: (a) hand-roll a minimal independent HTTP/SSE
client inside the CLI — faster to start, but the protocol (session
lifecycle, approval grant/decline, in-flight settlement) is intricate
enough that a second implementation would drift from the app's; (b) build
the CLI as a Flutter command-line target reusing `apps/lib/agentic/`
directly — avoids duplication, but pulls the Flutter engine into a
terminal tool and Flutter's runtime doesn't cooperate well with raw
terminal control (`dart_console` needs direct stdin/stdout access). Chose
extraction: one implementation, consumed by both, matching the existing
`dart_packages/sherpa_voice` pattern.

Two Flutter-only concerns move with a small adaptation rather than as-is:
`SensitivityLevel`'s `Color` field (`models.dart`) stays behind as a UI
extension in `apps/`, and the `kIsWeb`-based default URL (`settings.dart`)
becomes a plain constant in the new package (the CLI is never a web
target). `utils/logger.dart` (imports `flutter/foundation.dart`) is
replaced with a minimal `print`-based logger local to the new package.

**Package layout: `dart_packages/agentic_client` + `tools/cli`, not
everything under `apps/`.**
Matches the repo's existing split between shared packages
(`dart_packages/`) and standalone tools (`tools/voice_catalog`). Keeps the
CLI buildable with just the Dart SDK, no Flutter toolchain required.

**REPL terminal style: scrolling transcript + a live-redrawn input region,
not an alternate-screen split-pane TUI.**
Alternative considered: a full alternate-screen layout (fixed chat pane +
fixed input bar, like `htop`/`vim`) — closer to a dashboard, but
substantially more code (owns the whole screen: scroll-region math, resize
handling, terminal-state restore on exit/crash) for a chat REPL that
doesn't need split views. The chosen approach still uses `dart_console`'s
raw terminal control, just scoped to the input region rather than the
whole screen.

**Approval handling: REPL prompts interactively; single-turn auto-declines
(mirrors the app's existing "Continue without" / per-approval decline,
`apps/lib/agentic/approval_card.dart`).**
Alternatives considered for single-turn specifically: always auto-*grant*
(risk: a script could silently execute a sensitive tool call with no
confirmation) and always fail closed with no way to complete the run
(defeats the purpose of unattended automation touching tools). Auto-decline
was chosen because it's not a new behavior invented for this change — it's
the same "continue without" path the app already offers a human, just
applied automatically since there's no human to ask.

**Engine URL persisted in `settings.ini`; auth token in the Linux Secret
Service via `freedesktop_secret`, not in `settings.ini`.**
`freedesktop_secret` and the related `dbus_secrets` package both wrap
`org.freedesktop.secrets` over the pure-Dart `dbus` package — no native/FFI
dependency, so unlike `flutter_secure_storage` (which requires Flutter's
plugin/platform-channel machinery), it works in a bare Dart CLI.
`freedesktop_secret` was chosen over `dbus_secrets` for being the more
recently maintained of the two. This is a deliberate departure from the
engine's own convention, which stores its `secret_access_key` in plain-text
`settings.ini` (`run/settings-template.ini`) — that secret protects a
server-side endpoint, whereas the CLI's token sits on a developer
workstation next to their own session keyring, where OS-level secure
storage is available and appropriate.
Alternative considered: env-var/flag only, no persistence — simplest and
fully portable, but reopens the need to re-supply the token every session,
which is exactly what the `config` wizard exists to avoid.

**No `--session-id` / session resumption in v1.**
Every REPL launch and every single-turn call starts fresh. Chained
multi-turn automation, if ever needed, means staying in the REPL rather
than scripting repeated single-turn calls against one session — deferred
rather than designed for speculatively.

## Risks / Trade-offs

- [Linux-only token storage] → No macOS/Windows secure storage in this
  change. Mitigation: `--token`/`ENGINE_TOKEN` env var always works as a
  fallback on any platform; the keyring path degrades to "no token" rather
  than failing outright when unavailable (e.g. no D-Bus session).
- [Shared-package extraction touches code the production Flutter app
  depends on] → Regression risk in `apps/`. Mitigation: existing
  protocol-level tests move with the code into the new package's test
  suite rather than being dropped, and `apps/`'s full test suite runs
  before/after the extraction as an explicit checkpoint.
- [Single-turn mode silently declines approvals] → An automated caller
  might not realize a tool call was skipped, so the reply may be weaker
  than an interactive run's. Mitigation: this is a deliberate, documented
  default matching existing app behavior, not an oversight — no additional
  flag is introduced in v1 to change it.
- [`settings.ini` is plain text and hand-editable] → A malformed edit could
  break config resolution. Mitigation: matches `engine/settings.py`'s own
  tolerant behavior — a missing/invalid section falls back to the default
  rather than crashing.

## Migration Plan

Purely additive; no engine changes, no changes to `apps/`'s external
behavior.

1. Create `dart_packages/agentic_client`, move the protocol code and its
   tests into it, update `apps/pubspec.yaml` to a path dependency. Run
   `apps/`'s full test suite as a checkpoint before proceeding.
2. Scaffold `tools/cli`. Implement `config` first (the other two commands
   depend on it for connection resolution), then `ask`, then `chat`.
3. Rollback, if needed at any point: nothing outside the two new packages
   and the one `apps/pubspec.yaml` dependency line changes, so reverting
   is a matter of dropping those.

## Open Questions

None outstanding — all decisions above were resolved during design
review rather than deferred.
