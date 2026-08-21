## Why

The interactive CLI chat REPL currently lacks visual feedback while waiting for responses and doesn't distinguish user-sent messages from system content. Users typing while a response is in flight see no indication that input is being captured, and the transcript reads as a uniform stream without clear sender separation. Adding visual spacing, an animated loading indicator, and dim markers around user messages improves clarity and responsiveness without adding color complexity.

## What Changes

- **Sent message markers**: User messages are now prefixed and suffixed with dim braille glyphs (`⢆⣀⣀` and `⠎⠉⠉`) instead of a bordered box, distinguishing them from assistant responses
- **Message text styling**: User message text is printed dim to de-emphasize against the normal-weight assistant responses
- **Natural text wrapping**: Removed hard-wrapping logic; message text respects only user's own line breaks and the terminal's soft-wrap, so messages stay readable across terminal resize events
- **Live separator line**: A short, fixed-length dim divider (10 solid + 10 dotted characters) appears between the transcript and the active prompt, marking a clear visual boundary without depending on terminal width
- **Loading spinner**: While a response is in flight, a dim animated braille spinner (8 frames, ~80ms each) + "Thinking…" label appears above the compose line
- **Immediate resize handling**: Added `SIGWINCH` listener so the live prompt (spinner, separator, input area) redraws immediately on terminal resize instead of waiting for the next keystroke
- **Text styling only**: All visual enhancements use bold/dim/underline text styles; no explicit foreground colors, ensuring readability across light and dark terminal themes
- **Ctrl+C always reaches shutdown**: Ctrl+C — idle, mid-cycle, or during a pending approval decision — now always runs the normal shutdown sequence (restoring terminal mode, running/reporting the configured session purge) instead of hard-exiting via `exit()` and skipping it. The in-flight request itself isn't cancelled, just abandoned. Always a "hard" exit: skips the purge confirmation, uses the configured default, exits with code 130
- **Purge confirmation on normal exit**: Exiting via Ctrl+D/EOF or `/exit` with a known session now asks "Purge this session on exit? [Y/n]" (default from config/flag), instead of silently applying the configured default. The outcome ("Session purged." / "Session not purged.") is now always reported, not just on purge
- **Cursor movement and mid-line editing**: The compose prompt supports Left/Right/Home/End/Delete to move the cursor and edit already-typed text on the current line, not just append/backspace at the end
- **Batched queued-message dispatch**: Messages submitted while a cycle is in flight accumulate as a real queue (previously a single slot that silently dropped earlier ones) and dispatch together as one turn when the cycle settles, rather than one round-trip per message. A queued message is marked "sent" only at dispatch time, not when queued, so the spinner never appears to include not-yet-dispatched content
- **Spinner suppressed during approval prompts and resize**: The spinner no longer appears, animates, or redraws over the approval prompt while waiting for a grant/decline decision (including on a terminal resize during that wait) — it was corrupting the prompt's display and misrepresenting "waiting on a human" as "the engine is thinking"
- **Approval prompt label is bold**: Only "Approval requested:" renders bold, not the purpose/component details that follow it
- **Clean line before shutdown output**: Ctrl+D/EOF now erases the live prompt and prints a newline before the caller's shutdown output (e.g. "Session purged."), matching what Ctrl+C already did
- **Extra blank line before the assistant's response**

## Capabilities

### New Capabilities

None — this change enhances the REPL's interactive presentation and input handling without introducing a new top-level capability.

### Modified Capabilities

- `cli-chat-repl`: The interactive REPL's visual presentation is enhanced with spacing, animations, and message markers, and its input handling gains cursor-based editing and a graceful Ctrl+C path. Core behavior (multi-line input via `\`-continuation, streaming responses, approval prompts, session management) is unchanged in its fundamentals, but both the *display* of messages and the *editing experience* while composing are improved.

## Impact

**Code affected:**
- `tools/cli/lib/input_box.dart`: Replace bordered-box rendering with dim marker lines; remove hard-wrap logic
- `tools/cli/lib/live_input.dart`: Add spinner timer, SIGWINCH listener (debounced), fixed-length separator rendering, cursor tracking/movement/editing, graceful Ctrl+C handling
- `tools/cli/lib/prompt_decorations.dart`: New — pure, unit-testable string/math helpers (separator, spinner frame text, row/column wrap math) extracted out of `LiveInput`'s I/O
- `tools/cli/lib/chat_command.dart`: `busy` now cleared before printing a response (was only cleared in `finally`, after printing) so the spinner doesn't flicker back on; EOF-break comment updated to mention Ctrl+C

**User-facing:**
- Users see their sent messages more clearly separated from assistant responses
- Users get immediate visual feedback (spinner) while waiting for a response, even while typing a queued message
- Terminal resize no longer breaks alignment of old messages (they stay as printed; new messages align correctly at the new width)
- Users can move the cursor and edit text anywhere on the current line, not just append/backspace at the end
- Ctrl+C while idle now runs the configured session purge and reports it, instead of exiting silently

**Dependencies:** No new dependencies; uses existing `dart_console` and `ProcessSignal` APIs.

**Breaking changes:** The process exit code for a Ctrl+C-triggered exit changed from `0` to `130` (the conventional SIGINT exit code) — a script checking this CLI's exit code would previously see `0` for both a Ctrl+C and a clean exit, and now sees `130` for Ctrl+C specifically. Otherwise none — the REPL's core behavior is unchanged; the rest is presentation and input-handling refinement.
