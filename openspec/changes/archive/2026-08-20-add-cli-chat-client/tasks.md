## 1. Extract `dart_packages/agentic_client`

- [x] 1.1 Create the `dart_packages/agentic_client` package skeleton
      (`pubspec.yaml`, `analysis_options.yaml`), matching the
      `dart_packages/sherpa_voice` conventions
- [x] 1.2 Move `apps/lib/agentic/models.dart` into the package; extract
      `SensitivityLevel`'s `Color` field into a UI-side extension that
      stays in `apps/lib/agentic/`
- [x] 1.3 Move `apps/lib/agentic/sse_client.dart` and `services.dart`
      (`ChatService`) into the package
- [x] 1.4 Move `apps/lib/agentic/health_check.dart` and
      `apps/lib/chat/auth_detection.dart` into the package
- [x] 1.5 Move `apps/lib/agentic/self_test_service.dart` into the package
- [x] 1.6 Replace the package's use of `apps/lib/utils/logger.dart`
      (Flutter-only) with a minimal package-local logger
- [x] 1.7 Replace the `kIsWeb`-based default engine URL
      (`apps/lib/models/settings.dart`) with a plain constant in the
      package; keep `apps/`'s web-aware default local to `apps/`
- [x] 1.8 Update `apps/pubspec.yaml` to a path dependency on
      `agentic_client`; update `apps/lib` imports that referenced the
      moved files
- [x] 1.9 Move the protocol-level cases (message/approval immutability,
      `copyWith`) out of
      `apps/test/agentic/agentic_chat_provider_test.dart` into
      `dart_packages/agentic_client/test/`, keeping only the
      Riverpod-specific cases in `apps/`
- [x] 1.10 Run `apps/`'s full test suite and fix any breakage introduced
      by the extraction

## 2. `tools/cli` scaffold

- [x] 2.1 Create the `tools/cli` package skeleton (`pubspec.yaml` with
      `args`, `dart_console`, `cli_repl`, `freedesktop_secret`, `ini`, and
      a path dependency on `agentic_client`; `executables:` entry),
      matching `tools/voice_catalog` conventions
- [x] 2.2 Implement `bin/relagent_cli.dart`: an `args` `CommandRunner`
      wiring the three subcommands (`config`, `ask`, `chat`) with shared
      `--engine-url`/`--token` flags

## 3. Configuration and the `config` wizard (`cli-config`)

- [x] 3.1 Implement `settings.ini` read/write for `[engine] url`, at
      `~/.local/share/org.venkado.relagent-cli/settings.ini`, tolerating a
      missing/invalid file by falling back to the default
- [x] 3.2 Implement token storage/lookup via `freedesktop_secret`, with
      graceful fallback to "no token" when the Secret Service/D-Bus is
      unavailable
- [x] 3.3 Implement the flag → env var → persisted value → default
      resolution precedence for both the engine URL and the token
- [x] 3.4 Implement the `config` command: two questions (URL, token) with
      the current value shown as the default, blank input keeps the
      current value, token input is masked, and a previously stored token
      is never re-displayed
- [x] 3.5 Wire the wizard's connection test using the extracted
      `EngineHealthCheckService`, printing a one-line success/failure
      summary; saved values are not rolled back on a failed test
- [x] 3.6 Unit tests for the resolution precedence and the
      blank-keeps-current wizard behavior, using an injected fake keyring
      and a temp settings directory

## 4. Single-turn command (`cli-single-turn`)

- [x] 4.1 Implement prompt input: positional argument, falling back to
      stdin when absent
- [x] 4.2 Implement session creation, `POST /messages`, and SSE stream
      consumption for a single-turn run
- [x] 4.3 Implement automatic decline of pending approvals followed by
      `continue`, repeated until the cycle settles
- [x] 4.4 Implement stdout output limited to the final assistant message
      text on success
- [x] 4.5 Implement exit codes (0 on success) and stderr error reporting
      for connection/protocol failures
- [x] 4.6 Tests, including an integration smoke test against the engine's
      demo mode (`uv run python -m engine.api.demo`), covering the
      `search `-triggered approval path

## 5. REPL command (`cli-chat-repl`)

- [x] 5.1 Implement the expanding multi-line input box's buffer→lines
      redraw logic as a pure, terminal-independent function
- [x] 5.2 Wire `cli_repl` (line input/history) and `dart_console`
      (redrawing only the input region, not the whole screen)
- [x] 5.3 Implement session creation on first input and sequential-turn
      enforcement (no new message accepted before the previous cycle
      settles)
- [x] 5.4 Implement streamed assistant token display into normal terminal
      scrollback
- [x] 5.5 Implement the interactive approval prompt (grant /
      continue-without), mirroring `approval_card.dart`'s semantics
- [x] 5.6 Unit tests for the input-box redraw function in isolation from
      real terminal I/O

## 6. Verification

- [x] 6.1 Run `openspec validate --strict` for this change and resolve any
      issues
- [x] 6.2 Manually exercise `config` → `ask` → `chat` end-to-end against
      the engine's demo mode
