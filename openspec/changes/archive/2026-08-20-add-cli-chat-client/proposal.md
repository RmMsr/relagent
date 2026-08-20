## Why

The engine (`engine/`) exposes a REST + SSE chat API, but the only client
today is the Flutter app. There's no way to drive a chat session, or script
one, from a terminal — every interaction requires launching the full app.

## What Changes

- Extract the protocol logic currently embedded in `apps/lib/agentic/`
  (session/message/approval models, the HTTP+SSE engine client,
  `ChatService`, `EngineHealthCheckService`) into a new pure-Dart package,
  `dart_packages/agentic_client`, consumed by both `apps/` and the new CLI.
  No behavior change for the Flutter app — this is a relocation, not a
  rewrite.
- Add a new standalone terminal client at `tools/cli` (pattern-matches the
  existing `tools/voice_catalog`) with three subcommands:
  - `chat` — interactive REPL: scrolling transcript, a live-redrawn
    expanding input box (not a full alternate-screen TUI), inline
    grant/decline prompts for tool-call approvals.
  - `ask` — non-interactive single-turn command for automation: prompt via
    positional argument or stdin, final assistant reply on stdout, pending
    approvals auto-declined, non-zero exit on failure.
  - `config` — setup wizard: asks for engine URL and auth token, blank
    input keeps the current value, runs a connection test at the end.
- Engine URL is persisted in `~/.local/share/org.venkado.relagent-cli/
  settings.ini`, mirroring the ini-based convention `engine/settings.py`
  already uses for the engine itself. The auth token is stored in the Linux
  Secret Service (GNOME Keyring / KWallet) via the `freedesktop_secret`
  package instead, matching the security posture the Flutter app gets from
  `flutter_secure_storage`.

## Capabilities

### New Capabilities
- `cli-chat-repl`: the interactive REPL — session lifecycle, streamed
  message display, the expanding input box, and inline approval handling.
- `cli-single-turn`: the non-interactive `ask` command — input/output
  contract, automatic approval decline, exit codes.
- `cli-config`: connection configuration — settings.ini + keyring
  resolution precedence, the `config` wizard's blank-keeps-current
  behavior, and the wizard's connection test.

### Modified Capabilities
(none — the `agentic_client` extraction relocates existing implementation
without changing any spec-level behavior of the Flutter app; `agentic-chat`
and `api-health-check` requirements are unaffected)

## Impact

- New package `dart_packages/agentic_client` (pure Dart); `apps/pubspec.yaml`
  gains a path dependency on it, replacing the local copies in
  `apps/lib/agentic/{models,sse_client,services,health_check,
  self_test_service}.dart` and `apps/lib/chat/auth_detection.dart`.
- `apps/test/agentic/agentic_chat_provider_test.dart` splits: protocol-level
  cases (message/approval immutability, `copyWith`) move to
  `dart_packages/agentic_client/test/`; only Riverpod-specific cases stay in
  `apps/`.
- New package `tools/cli`, depending on `agentic_client`, `args`,
  `dart_console`, `cli_repl`, `freedesktop_secret` (and transitively
  `dbus`), and `ini`.
- No engine (`engine/`) changes — the CLI is a new client of the existing
  `/api/v1` REST + SSE surface.
- Linux-only for v1 (the token-storage mechanism is Secret Service/D-Bus
  specific); no macOS/Windows support in this change.
