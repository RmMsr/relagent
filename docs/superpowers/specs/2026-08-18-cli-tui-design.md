# CLI Chat Interface — Design

## Summary

Add a standalone terminal client for the agentic engine with three modes: an
interactive REPL chat, a non-interactive single-turn command for
scripting/automation, and a config wizard to set the connection up. Built in
Dart, reusing the protocol logic that already exists in the Flutter app
rather than reimplementing it.

## Motivation

The engine (`engine/`, Python/FastAPI) exposes a REST + SSE chat API. Today
the only client is the Flutter app (`apps/`), which has its own hand-rolled
session/message/SSE handling in `apps/lib/agentic/`. There's no way to drive
a chat session from a terminal or a script. This adds that, without
duplicating the protocol implementation.

## Non-goals (v1)

- Session persistence/resumption across CLI invocations (`--session-id`).
  Every run — REPL launch or single-turn call — starts a fresh session.
- Cross-platform secret storage (macOS Keychain, Windows Credential Manager).
  v1 is Linux-only for token storage.
- Full-screen/alternate-screen TUI (split panes, fixed regions). The REPL
  uses normal scrollback plus a redrawn input area, not a dashboard layout.
- `--json` structured output for single-turn mode. Plain text only.

## Architecture

Two new packages; no behavioral change to the existing Flutter app.

### `dart_packages/agentic_client` (new, pure Dart)

Extracted from `apps/lib/agentic/{models.dart, sse_client.dart, services.dart,
health_check.dart, self_test_service.dart}` plus two files those depend on,
`apps/lib/chat/auth_detection.dart` and `apps/lib/utils/logger.dart`.
Contains the session/message/approval models, the HTTP+SSE engine client,
`ChatService`, and `EngineHealthCheckService` (used by the CLI's `config`
connection test). This is the package both `apps/` and the new CLI depend
on, mirroring the existing `dart_packages/sherpa_voice` pattern.

Three Flutter-only concerns get separated out during the move, since this
package must build without the Flutter SDK:

- `models.dart` currently gives `SensitivityLevel` a `Color` field
  (`package:flutter/material.dart`). The enum/data itself moves to
  `agentic_client`; the `Color` mapping stays behind as a small extension in
  `apps/lib/agentic/`, applied at the UI layer.
- `settings.dart`'s default engine URL depends on `kIsWeb`
  (`package:flutter/foundation.dart`). `agentic_client` uses a plain
  `http://localhost:8000` constant — the CLI is never a web target, so the
  web-specific branch isn't relevant to it, and `apps/` keeps its own
  web-aware default.
- `utils/logger.dart` imports `package:flutter/foundation.dart` (for
  `kDebugMode`). `agentic_client` gets its own minimal logger (a plain
  `print`-based debug hook), since it can't depend on Flutter.

`apps/lib/agentic/{widgets.dart, approval_card.dart, sensitivity_widgets.dart}`
are pure Flutter UI and are not touched. `apps/lib/providers/
agentic_chat_provider.dart` (the Riverpod state notifier — queuing,
`isAwaiting`/`inputEnabled`) also stays in `apps/`, now importing models from
`agentic_client` instead of the local copy.

### `tools/cli` (new)

Pattern-matches the existing `tools/voice_catalog` (standalone Dart
executable, `args`-based). Depends on `agentic_client`, `args`,
`dart_console`, `cli_repl`, `freedesktop_secret`, and `ini` (settings.ini
read/write).

- `bin/relagent_cli.dart` — `args` `CommandRunner` with three subcommands:
  `chat` (REPL), `ask` (single-turn), and `config` (setup wizard).
- `lib/config.dart` — resolves engine URL and auth token, and reads/writes
  `settings.ini`.
- `lib/config_wizard.dart` — the `config` command.
- `lib/repl.dart` — the REPL loop: `cli_repl` for line input/history,
  `dart_console` for the growing input box and inline approval prompts.
- `lib/single_turn.dart` — the `ask` command.

## Configuration

Follows the same convention `engine/settings.py` already uses (see
`run/settings-template.ini`): an ini file under
`~/.local/share/org.venkado.<app-id>/settings.ini`, `[section]`/`key =
value` format, with `SECTION_KEY` (uppercased) as the matching env var
override. For relagent-cli, that's `~/.local/share/
org.venkado.relagent-cli/settings.ini`, `[engine]` section, `url` key.

- **Engine URL**: `--engine-url` flag, else `ENGINE_URL` env var, else
  `[engine] url` in `settings.ini`, else `http://localhost:8000`. Not
  sensitive — stored in plain text, human-editable, and is exactly what the
  `config` wizard reads as "current value" and writes back.
- **Auth token**: `--token` flag, else `ENGINE_TOKEN` env var, else looked
  up from the Linux Secret Service (GNOME Keyring / KWallet) via the
  `freedesktop_secret` package, keyed by an attribute identifying this CLI.
  `freedesktop_secret` talks to `org.freedesktop.secrets` over D-Bus directly
  (via the pure-Dart `dbus` package) — no native/FFI dependency, so it works
  in a plain `dart_console` CLI the way it couldn't through
  `flutter_secure_storage` (which requires Flutter's plugin/platform-channel
  machinery). If no D-Bus session is available (e.g. a container with no
  login session), this lookup fails gracefully and falls through to "no
  token," with a one-time warning on stderr — it does not abort config
  resolution.

  Note this is a deliberate departure from the engine's own convention: the
  engine stores its `secret_access_key` in plain-text `settings.ini` too
  (see `[server]` in the template). The CLI's token goes to the keyring
  instead, matching the security posture the Flutter app already gets from
  `flutter_secure_storage`, since unlike the engine's server-side secret,
  this token sits on a developer's own workstation alongside their session
  keyring.

## Config wizard (`config`) — data flow

1. Load current `settings.ini` (if present) and check whether a token is
   already stored in the keyring (existence check only — the value itself
   is never read back or displayed).
2. Ask two questions, in order, each showing the current value (or "not
   set") as the default:
   - Engine URL — blank input keeps the current value.
   - Auth token — blank input keeps whatever's currently in the keyring
     (or stays unset); a non-blank answer overwrites the keyring entry.
     Input is masked while typing.
3. Write the (possibly unchanged) engine URL to `settings.ini`. Write the
   token to the keyring only if the user entered a new one — never
   rewritten if they left it blank.
4. Run the connection test: `EngineHealthCheckService.checkStatus()`
   against the just-configured URL/token (the same client the Flutter app
   uses for its own connection check). Print a one-line success/failure
   summary, mirroring `EngineHealthResult`'s existing status categories
   (`success`, `authRequired`, `authFailed`, `connectionFailed`, `timeout`,
   `invalidEndpoint`). A failed test does not roll back the write — the
   values are already saved; the wizard just reports what it found so the
   user can re-run `config` to fix it.

## REPL (`chat`) — data flow

1. Resolve config, construct a `ChatService`.
2. On the first input, create a new session.
3. Loop: read a line (or multiple lines) via the expanding input box →
   `POST /messages` → open the SSE stream → print assistant tokens as they
   arrive in the normal scrollback.
4. On a pending approval: pause streaming, prompt inline with the same two
   choices as the app's `approval_card.dart` — `Grant` / `Continue without`
   — call the corresponding grant/decline endpoint, then `POST
   /sessions/{id}/continue`, then resume streaming until the cycle settles
   (`final=true`). Return to the input box.
5. The REPL never sends a new message before the current cycle settles, so
   `409 session_in_flight` is structurally unreachable and isn't handled as
   a distinct case.

### Input box

Not an alternate-screen TUI. Old output stays in normal terminal scrollback
and is never redrawn. Only the input area — a few lines at the cursor — is
live-redrawn by `dart_console` as the user types, growing as input wraps to
multiple lines (comparable to Claude Code's own prompt or `gum`'s textarea).
The buffer→lines redraw logic is a pure function, independent of terminal
I/O, so it's unit-testable without a real terminal.

## Single-turn (`ask`) — data flow

1. Resolve config. Read the prompt from a positional argument if given,
   otherwise from stdin.
2. Create a fresh session → `POST /messages` → open the SSE stream.
3. On any pending approval: auto-decline it (same "Continue without"
   semantics as the REPL's decline path — this is an existing, already-used
   pattern in the app, not a new default invented for automation) →
   `POST /continue` → keep going until the cycle settles.
4. Print only the final assistant message text to stdout. Exit 0.
5. On any HTTP/connection error, or a stream that ends without settling:
   one-line message to stderr, exit non-zero. No retries — a caller that
   wants retry behavior wraps the CLI itself.

## Error handling (cross-cutting)

- Engine unreachable (connection refused, DNS failure, timeout): one-line
  message on stderr naming the resolved engine URL, exit non-zero.
- Keyring unavailable: treated as "no token found," not a crash (see
  Configuration above).
- Malformed/unexpected SSE payload: abort the current turn — non-zero exit
  in single-turn mode, an in-REPL error line that returns to the prompt in
  REPL mode. Never silently dropped.

## Testing

- `agentic_client`: the protocol-level test cases currently embedded in
  `apps/test/agentic/agentic_chat_provider_test.dart` (message/approval
  immutability, `copyWith` behavior) move to `dart_packages/agentic_client/
  test/`, using `package:http/testing.dart`'s `MockClient` — pure `dart
  test`, no Flutter test runner, no server.
- `apps/`: `agentic_chat_provider_test.dart` shrinks to only the
  Riverpod-specific behavior that stays in `apps/lib/providers/` (queuing,
  `isAwaiting`/`inputEnabled`), now importing types from `agentic_client`.
- `tools/cli` config resolution: unit tests for the flag → env →
  settings.ini/keyring → default precedence, with the keyring lookup
  injected as an interface so tests don't require a real D-Bus session, and
  `settings.ini` reads/writes pointed at a temp directory.
- `tools/cli` config wizard: unit tests for the "blank keeps current value"
  behavior for both the URL (settings.ini) and the token (keyring), using
  the same injected fakes.
- `tools/cli` input box: unit tests on the buffer→lines redraw function in
  isolation from real terminal I/O.
- Integration smoke test: run `ask` against the engine's existing demo mode
  (`uv run python -m engine.api.demo`) to exercise a real HTTP+SSE
  round-trip, including the `search `-triggered approval flow already built
  into demo mode for exactly this purpose. Extend this to also run `config`
  against demo mode, verifying the connection test reports success.

## Open questions for the implementation plan

None outstanding — all major decisions (package layout, config/token
resolution, TUI style, approval handling per mode, session scope, I/O
contract) were settled during design.
