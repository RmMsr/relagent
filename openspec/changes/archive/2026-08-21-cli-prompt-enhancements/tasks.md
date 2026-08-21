## 1. Input Box Marker Rendering

- [x] 1.1 Modify `renderInputBoxLines()` to return dim braille markers instead of a bordered box
  - Remove the manual text wrapping loop (`while (remaining.length > innerWidth)`)
  - Change return value from `[top, ...body, bottom]` to `[markerBegin, ...textLines, '', markerEnd]`
  - Set `markerBegin = '⢆⣀⣀'` and `markerEnd = '⠎⠉⠉'`
  - Call `console.setTextStyle(dim: true)` before printing markers and text in `_printSent()`
- [x] 1.2 Verify unit tests for `renderInputBoxLines()` pass with new marker output
  - Update test assertions to expect markers instead of box borders
  - Add tests for multi-line message markers (verify markers appear above/below)
  - Test that no hard-wrapping occurs on long lines

## 2. Spinner Implementation

- [x] 2.1 Add spinner state to `LiveInput` class
  - Add `Timer? _spinnerTimer` field
  - Add `int _spinnerFrame` field (0–7)
  - Add spinner frame strings as a class constant (8 braille frames)
- [x] 2.2 Implement spinner animation logic
  - Create private method `_startSpinner()` to initialize `_spinnerTimer` with `Timer.periodic(Duration(milliseconds: 80))`
  - Timer increments `_spinnerFrame` (mod 8) and calls `_redraw()` each tick
  - Create private method `_stopSpinner()` to cancel the timer and reset frame to 0
- [x] 2.3 Modify `busy` setter to control spinner
  - When `busy` is set to `true`, call `_startSpinner()`
  - When `busy` is set to `false`, call `_stopSpinner()` and call `_redraw()` once to remove the spinner row
- [x] 2.4 Add spinner row rendering to `_redraw()`
  - Check if `busy && _spinnerTimer != null` to decide whether to render the spinner
  - If rendering, prepend a single line `"${_spinnerFrames[_spinnerFrame]} Thinking…"` (dim) to the output before the compose lines

## 3. Separator Line and Resize Handling

- [x] 3.1 Add separator line to `_redraw()`
  - After erasing in `_redraw()`, compute separator string: `'─' * (console.windowWidth - 1)`
  - Style it dim via `console.setTextStyle(faint: true)` (dart_console's name for dim)
  - Print separator line followed by newline before drawing compose lines
- [x] 3.2 Add SIGWINCH listener for immediate resize redraw
  - In `start()`, add `ProcessSignal.sigwinch.watch().listen((_) => _redraw())`
  - This redraws the live region immediately when the terminal is resized
  - Handle the case where `sigwinch` is not available (Windows — graceful fallback, no error)
- [x] 3.3 Verify separator and spinner interleave with intermediate notifications
  - Confirm `hideForPrint()` and `showAfterPrint()` still work with spinner active
  - **Found and fixed a bug**: `chat_command.dart` set `busy = false` only in `finally`, after `showAfterPrint()` had already redrawn with the spinner still considered active — causing a one-frame flicker. Moved `busy = false` to just before `hideForPrint()` in each success/error branch.

## 4. Testing

- [x] 4.1 Update unit tests in `input_box_test.dart`
  - Test `renderInputBoxLines()` output with markers and dim styling
  - Test that text wrapping logic is removed (no hard-wrap at column boundary)
  - Test edge cases: empty message, very long single line, multi-line message
- [x] 4.2 Add unit tests for the pure decoration logic
  - `LiveInput` has no injectable stdin/console seam, so its `_redraw()`/spinner internals
    can't be unit-tested directly without a larger refactor (out of scope here).
    Extracted the pure string-formatting into `lib/prompt_decorations.dart`
    (`renderSeparatorLine`, `renderSpinnerLine`, `spinnerFrames`) — same pattern as
    `renderInputBoxLines` — and added `test/prompt_decorations_test.dart` covering
    separator width (including zero/negative clamping) and spinner frame cycling/wraparound.
- [ ] 4.3 Integration test: real terminal chat session — **in progress, manual verification**
  - `LiveInput` is only constructed when `stdin.hasTerminal` is true and reads raw stdin
    bytes directly with no injectable seam, so this can't be exercised through a
    non-interactive/piped Bash command. Requires a human running `relagent chat` in a
    real terminal. Bugs found and fixed so far during this pass:
    - Marker rendering had an unwanted blank line before the closing marker — removed.
    - Separator was 1 char short of the terminal width (stale `-1` from the old box
      calc) — fixed.
    - Resize didn't recover cleanly when a line had wrapped to multiple rows before
      the resize (terminal-side reflow desyncs our cached row counts) — resize now
      abandons the old prompt area with a fresh line instead of erasing in place.
    - That abandon path was firing on *every* resize, even when nothing wrapped
      (the common case) — scoped it to only trigger when a compose line actually
      spanned multiple rows; otherwise a normal erase-and-redraw runs (safe and
      leaves nothing behind).
    - A resize *drag* still fired many SIGWINCH events while wrapped, each
      abandoning independently and piling up separator+prompt duplicates in
      scrollback — added 100ms debouncing so a whole drag collapses into one
      response, plus opportunistic cleanup: abandoned rows are tracked and swept
      up by the next erase that runs from a trustworthy (non-wrapped) state.
    - Debounce + cleanup reduced but didn't fully eliminate the piling-up —
      the underlying fragility (recomputing a full-width separator against
      `windowWidth` and re-erasing it correctly across resize) proved to be a
      deeper problem than it looked. Redesigned the separator to sidestep it
      entirely: replaced the full-width dash line with a short fixed-length
      divider (`separatorLine` in `prompt_decorations.dart`: 10 solid `─` + 10
      dotted `┄` characters), which never depends on terminal width and so has
      nothing for a resize to desync. See design.md §3 for the full writeup.
      The debounce/orphan-cleanup machinery stays in place for wrapped compose
      text, which is a genuinely width-dependent case.
    - Checklist:
    - [x] Send a user message, verify `⢆⣀⣀`/`⠎⠉⠉` markers appear and text is dim
    - [ ] While a response is in flight, type a queued message and verify the spinner
      animates above it and the queued text stays visible
    - [ ] Verify the spinner stops and is erased before the response text is printed
      (no flicker — this was the bug fixed in 3.3)
    - [x] Resize the terminal mid-session and verify the separator/spinner/input
      redraw immediately at the new width, and new messages sent after the resize
      align correctly (old messages above may look unchanged, which is expected)

## 5. Documentation and Cleanup

- [x] 5.1 Remove or update old docs referencing bordered-box rendering
  - Updated code comments in `input_box.dart` and `live_input.dart` to describe
    marker-based rendering instead of the old box
- [x] 5.2 Verify no regressions in other CLI commands
  - `dart analyze`: no issues
  - `dart test`: 35 passing, 2 skipped (demo engine unavailable, by design)
  - `relagent --help`: lists `ask`, `chat`, `config` correctly

## 6. Exit Flow: Purge Confirmation and Ctrl+C Reaching Shutdown

Found through further manual testing of the approval/queueing/exit flow.

- [x] 6.1 Purge confirmation on normal exit
  - Normal exit (Ctrl+D/EOF, `/exit`) with a known session now asks "Purge
    this session on exit? [Y/n]" (default from `--purge-session`/config),
    via new `LiveInput.readYesNoKey()`. Hard exit (Ctrl+C) skips it and uses
    the default directly, matching non-interactive behavior.
  - Runs before the `finally` that restores terminal mode, since the raw
    single-key reader needs it still active.
  - Always reports the outcome now ("Session purged." / "Session not
    purged."), not only when a purge happens — a hard exit applying a
    "don't purge" default previously printed nothing at all.
- [x] 6.2 Ctrl+C mid-cycle (and during a pending approval) now reaches shutdown
  - Previously called `exit(130)` directly from `LiveInput`, bypassing
    `ChatCommand.run()` and the purge sequence entirely.
  - `LiveInput.waitForInterrupt()` resolves on a mid-cycle Ctrl+C;
    `chat_command.dart` races it against `runCycle()` via `Future.any`,
    catches a thrown `_CtrlCInterrupt`, and falls through to the same
    shutdown path idle Ctrl+C uses (hard exit: no confirmation, configured
    default, exit code 130).
  - Found along the way: Ctrl+C was silently swallowed entirely during a
    pending approval prompt (only 'g'/'c' were recognized). Now routes to
    the same interrupt signal, abandoning the approval too.
  - Exit code is now 130 (not always 0) whenever a Ctrl+C caused the exit —
    called out as a breaking change in the proposal.
- [x] 6.3 Fixed a second occurrence of the approval-prompt-corruption bug
  - `_handleResize()` had no guard against redrawing during a pending
    approval — resizing the terminal while waiting on grant/decline also
    corrupted its display, same root cause as the spinner timer bug fixed
    earlier in this change. Same guard added.
- [x] 6.4 Cosmetic: bold only the "Approval requested:" label (not the
  purpose/component details), extra blank line before the assistant's
  response text
- [x] 6.5 Verify no regressions
  - `dart analyze`: no issues; `dart test`: 40 passing throughout this round

## 6. Ctrl+C Graceful Shutdown

- [x] 6.1 Route idle Ctrl+C through the same path as Ctrl+D/EOF
  - Found via manual testing: Ctrl+C called `exit(130)` directly, skipping
    `ChatCommand.run()`'s `finally` (terminal restore) and purge-on-exit logic
    entirely — the configured session purge silently never ran
  - When `_lineCompleter != null` (idle), complete it with `null` instead of
    exiting directly; mid-cycle (no pending completer) still exits immediately
    as before, since the in-flight request isn't cancellable from here
  - Updated `nextMessage()`'s doc comment and the `input == null` comment in
    `chat_command.dart` to reflect the second null-producing case

## 7. Cursor Movement and Mid-Line Editing

- [x] 7.1 Add cursor tracking scoped to the current (last) line
  - `_cursorCol`: offset within the buffer's last line, found via
    `_buffer.lastIndexOf('\n')`
  - Insert/Backspace/Delete/Enter all read and update it instead of always
    operating on the end of the buffer
- [x] 7.2 Replace the fixed-length escape-sequence swallow with a real parser
  - The old logic assumed every sequence was exactly 3 bytes, which is wrong
    for Delete's numeric CSI form `ESC [ 3 ~` (would desync the byte stream)
  - `_readEscapeKey()` reads `[`/`O`, then a known letter (arrow/Home/End) or
    a numeric sequence up to its terminator; still consumes the right number
    of bytes during an approval prompt even though the result is discarded
    there (matches the old always-swallow behavior for that case)
- [x] 7.3 Reposition the cursor after redraw when it isn't at the line's end
  - Extracted `rowColFor()` (pure, in `prompt_decorations.dart`) to compute
    which row/column an offset lands on after wrapping, including the
    terminal's "deferred wrap" behavior at an exact row boundary
  - `_redraw()` writes the full line as before, then walks the cursor back
    via `cursorUp`/`cursorLeft`/`cursorRight` if it isn't at the natural end
  - `_erase()` reverses that offset first (`cursorDown`), since it otherwise
    assumes the cursor starts at the trailing block's natural bottom-right end
- [x] 7.4 Add unit tests for `rowColFor`
  - Covers offset 0, mid-row offsets, the exact-row-boundary deferred-wrap
    case, one-past-a-full-row, a multi-row offset, and non-positive width
- [x] 7.5 Verify no regressions
  - `dart analyze`: no issues; `dart test`: 40 passing (demo engine was
    reachable this run, so 0 skipped)
