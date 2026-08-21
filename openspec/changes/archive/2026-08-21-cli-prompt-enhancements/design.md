## Context

The interactive CLI REPL (`tools/cli/lib/live_input.dart`) implements a hand-rolled input system that manages a single erase/redraw cycle for the live prompt — this is already safe for keystroke-by-keystroke redraws and for interleaving with output from concurrent HTTP requests. The existing architecture tracks `_renderedRows` and `_trailingRows` to erase only what it drew before redrawing, keeping the scrollback intact.

The sent-message box is rendered once via `renderInputBoxLines()` (in `input_box.dart`) and printed as permanent history.

## Goals / Non-Goals

**Goals:**
- Visual distinction of user-sent messages through dim markers, not bordered boxes
- Provide animated loading feedback while responses are in flight
- Mark a clear boundary (separator line) between immutable transcript and live prompt
- Immediate redraw on terminal resize for the live region only (separator, spinner, input)
- Use only text styles (dim, bold, underline), no explicit colors
- Preserve native terminal scrollback and copy-paste

**Non-Goals:**
- Full TUI rewrite with alt-screen buffer (curses-style)
- Reflowing or repainting historic messages on resize (only new messages use new width)
- Right-aligning or padding user messages
- Adding color to the CLI
- Changing the core REPL behavior (multi-line input, streaming responses, approval prompts)

## Decisions

### 1. Sent Message Markers Instead of Bordered Box

**Decision**: Replace the bordered box (`┌─┐│└─┘`) with dim braille markers (`⢆⣀⣀` above, `⠎⠉⠉` below).

**Rationale**: 
- The bordered box has a fixed total width (baked at print time), so messages sent at different terminal widths appear visibly different-sized in the same scrollback.
- Markers are fixed-length glyphs with no width-spanning, so they stay consistent across resize.
- Dim styling (text weight, not color) de-emphasizes without fighting the user's terminal theme.

**Alternatives considered**:
- Keep box, make it dim: Still has the width-bake problem.
- Right-align boxes: Would need padding logic, still has width dependency.
- No visual distinction: Lost user-vs-system clarity.

### 2. Natural Text Wrapping (No Hard-Wrap)

**Decision**: Remove `renderInputBoxLines()`'s manual wrapping loop; print text as-is and let the terminal's soft-wrap handle overly long lines.

**Rationale**:
- Hard-wrapping inserts `\n` at fixed column boundaries, baking them into the character stream.
- Soft-wrap (computed by the terminal, not the app) is recomputed live on resize — this is why `cat` reflows correctly on resize without the app doing anything.
- Removing the hard-wrap mechanism solves the resize-reflow problem for historic messages: they just stay as printed, and new messages use the new width.

**Alternatives considered**:
- Keep hard-wrap, reflow on resize by reprinting history: Loses native scrollback and copy-paste.
- Context soft-wrap with a max line length: Adds complexity; soft-wrap alone is simpler.

### 3. Separator Line: Fixed-Length, Not Full-Width

**Decision**: A short, fixed-length divider (`separatorLine` in `prompt_decorations.dart`: 10 solid `─` + 10 dotted `┄` characters, dim), printed as part of the live-redrawn region.

**Original approach and why it changed**: The first implementation used a *full-width* dash line, recomputed against `console.windowWidth` on every redraw. In practice this proved too fragile: `_erase()` walks the cursor up using row counts cached from the *previous* draw, but many terminal emulators reflow already-drawn content on resize, desyncing those cached counts from what's actually on screen. Several rounds of mitigation (abandon-and-restart on wrap, scoping that to only when necessary, debouncing SIGWINCH, tracking and sweeping up orphaned rows) reduced the problem but didn't fully eliminate it, and each mitigation added real complexity for a purely decorative element.

The fixed-length redesign sidesteps the root cause instead of continuing to patch symptoms: a short constant string never depends on the terminal's current width, so there is nothing for a resize to invalidate — no width to recompute, no row count that can go stale. This mirrors the same insight already applied to the sent-message markers (`⢆⣀⣀` / `⠎⠉⠉`), which never had this problem for the same reason.

**Rationale**:
- Fixed-length content can't be desynced by terminal-side reflow, because it never had a width dependency to reflow.
- Still marks a visual boundary between "settled" transcript and "active" prompt, just more compactly.
- Removes the need for `_composeMayHaveWrapped`/`_orphanRows`/resize-debounce machinery *for the separator specifically* — that machinery remains relevant for wrapped compose text, which is a genuinely width-dependent case.

**Alternatives considered**:
- Full-width dash line (original): Simple in isolation, but the resize-erasure correctness problem it created was worse than the visual benefit of spanning the full width.
- Blank line only: Less visual separation, was considered and rejected earlier in favor of a visible divider.
- Separator as permanent history: Would have the same width-bake-at-print-time problem as the old bordered box.

### 4. Spinner as Row in Live Prompt

**Decision**: Fold the spinner into the existing `_redraw()` cycle as a row above the separator (and therefore above the compose lines too) when `busy == true` — the separator marks where the purely-interactive input area begins, and the spinner is status about system activity, not user input, so it belongs on the transcript side of that boundary.

**Rationale**:
- The existing `LiveInput` already has a single-owner erase/redraw cycle that's safe for concurrent output.
- Adding the spinner as one more row avoids spawning a second independent erase/redraw system (which risks cursor races).
- `busy` setter starts/stops a `Timer.periodic(80ms)` that advances the frame and calls `_redraw()`.
- `hideForPrint()` / `showAfterPrint()` already route through `_erase()` / `_redraw()`, so intermediate notifications and the final response interleave correctly with no special-casing.

**Spinner frames** (dim braille, 8-frame cycle):
```
⠋ Thinking…
⠙ Thinking…
⠹ Thinking…
⠸ Thinking…
⢰ Thinking…
⢠ Thinking…
⡀ Thinking…
⣄ Thinking…
```

**Alternatives considered**:
- Separate spinner UI outside the input system: Would need independent cursor management; risky with concurrent output.
- Escape-sequence-based animation: Doesn't work while the user is actively typing (conflicts with input rendering).

### 5. SIGWINCH Handler for Immediate Resize Redraw

**Decision**: Add a `ProcessSignal.sigwinch.watch()` listener (on POSIX systems) that calls `_redraw()` immediately.

**Rationale**:
- `console.windowWidth` already queries `stdout.terminalColumns` fresh on every call (not cached), so `_redraw()` is always correct.
- Immediate redraw on resize (rather than waiting for the next keystroke) makes the prompt responsive.
- SIGWINCH is available on Linux/macOS; Windows doesn't use it, but `dart_console` handles that internally.

**Alternatives considered**:
- Poll on a timer: Cheaper signals-wise, but adds latency.
- No resize handling: Live prompt only updates on next keystroke (current behavior).

### 6. Text Styles Only (No Explicit Colors)

**Decision**: Use `dim`, `bold`, `italic`, `underline` text styles only; no `ConsoleColor` or extended palette.

**Rationale**:
- Text styles layer on top of the terminal's color scheme without fighting it.
- An explicit color like `ConsoleColor.red` can land on an illegible mapping in some themes (e.g., red on dark red).
- Dim is safe on permanent content (markers) and acceptable on ephemeral content (spinner).

**Alternatives considered**:
- Use colors with theme detection: Would need terminal capability detection and fallback logic.
- Monochrome with no styling: Less visual feedback than dim provides.

### 7. Cursor Editing Scoped to the Current Line Only

**Decision**: Cursor movement/insert/delete operate on `_cursorCol`, an offset into the *current* (last) line of the buffer, found via `_buffer.lastIndexOf('\n')`. Earlier `\`-continued lines are not revisited — no Up/Down navigation across them.

**Rationale**:
- Once a line is committed via `\`-continuation, it's already been drawn as part of `_renderedRows` (fully-committed, newline-terminated rows). Making it editable again would mean re-erasing and redrawing content that today's `_erase()`/`_redraw()` model treats as settled, a much bigger change.
- Scoping to one line keeps the row/column math (`rowColFor`) tractable: it only has to reason about where an offset lands within a *single* line's wrap, not stitch together wrap boundaries across multiple lines with different prefixes.
- Matches what was actually requested (cursor movement and insert into existing text on the line being typed), without speculatively adding history/multi-line navigation that wasn't asked for.

**Alternatives considered**:
- Full-buffer cursor (any line reachable via Up/Down): More capable, but requires reworking `_renderedRows` to be mutable/re-editable, not just append-only — significantly larger change.

**Mechanism**: `_redraw()` writes the full current line as before (simplest way to keep the existing wrap-tracking and orphan/resize logic unchanged), then — only if the cursor isn't at the natural end — walks it back using `rowColFor` to compute the target row/column vs. where writing naturally left it, via `cursorUp`/`cursorLeft`/`cursorRight`. `_erase()` reverses that offset first (`cursorDown` by the same amount), since it otherwise assumes the cursor starts at the trailing block's natural bottom-right end.

**Escape sequence parsing**: The prior swallow logic assumed every escape sequence was exactly 3 bytes (`ESC [ <letter>`), which is wrong for Delete's numeric CSI form `ESC [ 3 ~` (and would desync the byte stream on it). Replaced with `_readEscapeKey()`, which reads a `[`/`O` selector, then either a known letter (arrow/Home/End) or a numeric sequence terminated by any non-digit. Still consumes the correct number of bytes even during an approval prompt (where the *result* is discarded rather than applied), so the stream never desyncs regardless of what's currently active.

### 8. Ctrl+C Hands Off to the Same Shutdown Path as Ctrl+D

**Decision**: When idle (a `_lineCompleter` is pending), Ctrl+C completes it with `null` — the same signal Ctrl+D/EOF sends — instead of calling `dart:io`'s `exit()` directly.

**Rationale**:
- `exit()` terminates the process immediately, without unwinding back through `ChatCommand.run()` — skipping both the `finally` block that restores terminal echo/line mode and the purge-on-exit logic below the main loop. The configured session purge silently never ran on Ctrl+C.
- Routing through the existing `nextMessage() -> null -> break` path means Ctrl+C gets the exact same graceful shutdown Ctrl+D already had, with no new shutdown logic to write or keep in sync.

**Scope limit, later lifted**: mid-cycle (a request in flight, no pending `_lineCompleter` to hand off to) originally still called `exit()` immediately, on the reasoning that gracefully cancelling an in-flight HTTP call was a larger change not asked for. It turned out the actual ask was narrower than full cancellation — see Decision 12, which covers this case without needing request-cancellation plumbing.

**Alternatives considered**:
- Cancel the in-flight request too: Would fully unify Ctrl+C/Ctrl+D behavior at the network level, but requires request cancellation plumbing that doesn't exist yet — still deferred, since Decision 12 achieves the actually-needed outcome (reaching shutdown) without it.

### 9. Queued Messages: Mark "Sent" at Dispatch, Not at Queue Time

**Decision**: `_queuedMessages` is a real `List<String>` (FIFO), and a message is only printed with sent markers (`_printSent`) when `_dispatchQueuedMessages()` actually pops and dispatches it — not when the user first submits it while busy.

**The bug this fixes**: The original queueing implementation printed a message as "sent" (permanent transcript) the moment it was submitted, even while queued. Since the spinner lives in the ephemeral region redrawn *below* whatever's most recently printed, each newly-queued message pushed the spinner further down — visually making it look like the spinner (and thus the in-flight request) already included that message, when it was actually just waiting locally, not yet sent to the engine. Also uncovered a correctness bug in the same code path: the old single-slot `_queuedReady` silently overwrote (dropped) an earlier queued message if a second one was submitted before the first got dispatched.

**Rationale**:
- A message visually becomes "sent" (dim markers, permanent) at exactly the moment it's true — when it's actually dispatched — so the spinner can never appear to include something that hasn't happened yet.
- A real list means messages genuinely pile up (as intended) instead of the last one silently clobbering earlier ones.
- Batching all currently-queued messages into one turn (joined with `\n`) when the cycle settles avoids one round-trip per message, was explicitly requested, and reads naturally as one combined message on both the transcript and the engine side (same `\n`-joining `renderInputBoxLines` already does for multi-line composed messages).

**Alternatives considered**:
- Keep printing at queue time, but move the spinner to a "pinned" row via absolute cursor addressing so it doesn't drift: Would require animating a spinner mid-scrollback while new content prints below it — significantly more complex, and still couldn't solve where the eventual *response* prints (it necessarily appends at the then-current bottom of an append-only terminal, so true chronological reinsertion isn't achievable regardless).
- Dispatch each queued message as its own separate cycle in order (no batching): Simpler, but means one round-trip per queued message — the explicit ask was to combine them.

### 10. Spinner Suppressed During Approval Prompts

**Decision**: The spinner's `Timer.periodic` tick no-ops entirely while `_approvalCompleter != null`.

**The bug this fixes**: An approval prompt calls `hideForPrint()` (erasing the live region) before asking its grant/decline question, and only redraws the live region once answered. But the spinner's timer keeps firing on its own 80ms schedule regardless — the very next tick called `_redraw()`, which reprinted the spinner/separator/prompt directly on top of (glued to the end of) the approval question, corrupting its display.

**Rationale**:
- Beyond the rendering bug, showing "Thinking…" while blocked on a human decision is conceptually wrong — the engine isn't processing anything at that moment, the user is.
- No race: setting `_approvalCompleter` and the `hideForPrint()`/print calls that precede it all run synchronously in the same event-loop turn (no `await` in between), so a pending timer tick cannot interleave in the gap.

**Alternatives considered**:
- Cancel and restart the spinner timer around the approval wait: Equivalent outcome, more moving parts (would need to remember to resume it afterward) for no real benefit over a cheap guard in the tick itself.

**Second occurrence found and fixed the same way**: `_handleResize()` had the identical gap — a terminal resize during a pending approval also called `_redraw()` unconditionally, corrupting the prompt the same way. Same guard (`_approvalCompleter != null || _yesNoCompleter != null`) added there too, so nothing here redraws until the prompt is answered, regardless of what triggers a redraw attempt in the meantime.

### 11. Ctrl+D/EOF Erases and Newlines Before Shutdown Output

**Decision**: The EOF case (`0x04`, empty buffer) now calls `_erase()` + `stdout.writeln()` before completing `_lineCompleter` with `null`, matching what Ctrl+C already did.

**The bug this fixes**: EOF previously did neither, so the live prompt (`> `) was still visible on screen with no trailing newline when the caller's shutdown code ran — a message printed right after (e.g. "Session purged.") landed glued to the end of it instead of on its own line.

### 12. Mid-Cycle Ctrl+C: Abandon the Wait, Not the Request

**Decision**: `LiveInput.waitForInterrupt()` exposes a `Future<void>` that resolves whenever Ctrl+C fires while a cycle is in flight (including during a pending approval). `chat_command.dart` races `runCycle()` against it via `Future.any`, throwing a private `_CtrlCInterrupt` if the interrupt wins, caught alongside the cycle's other outcomes to set `hardExit = true` and `break` — falling into the same shutdown/purge sequence idle Ctrl+C already used.

**Why this doesn't need request cancellation**: Decision 8 deferred fixing this because *fully* unifying Ctrl+C behavior seemed to require cancelling the in-flight HTTP call. But the actual requirement — reported directly — was narrower: reach the purge sequence, not necessarily stop the network request instantly. Racing the wait (not the request) delivers that: the caller stops *waiting* on `runCycle()` and moves on immediately, while the abandoned request either completes and is ignored or gets torn down implicitly when the process exits shortly after. No cancellation plumbing needed in `runCycle`/`cycle_runner.dart`.

**Why a fresh `Completer` each time, not a single reusable one**: A `Completer` can only be completed once. Recreating it (in `_signalMidCycleInterrupt`, right when the previous one fires) after every trigger means a *second* Ctrl+C during a later cycle can still signal, without the caller needing to know to re-subscribe — `waitForInterrupt()` always returns a still-pending future for whatever the *current* cycle is.

**Approval-prompt gap found while wiring this up**: `_readLoop`'s approval-completer branch only recognized 'g'/'c' and silently discarded every other byte, including Ctrl+C (0x03) — so Ctrl+C during a pending approval did nothing at all, not even the old `exit()`. Since an approval wait is still "mid-cycle" from the caller's perspective, this now routes to the same interrupt signal (via the shared `_signalMidCycleInterrupt` helper), abandoning the approval along with the request that asked for it.

**Alternatives considered**:
- True request cancellation (e.g. a `CancelToken` threaded through `runCycle`): The more complete fix, but deferred — not what was needed to satisfy the actual report, and a larger surface to test correctly (would need to verify the HTTP client and the engine-side session state both handle a mid-request cancel cleanly).
- Only fix the plain mid-cycle case, leave the approval-prompt gap as a separate follow-up: Rejected once found, since it's the same root cause (an interrupt signal chat_command.dart can react to) and the fix is a few lines given `_signalMidCycleInterrupt` already existed.

### 13. Purge Confirmation on Normal Exit, Skipped on Hard Exit

**Decision**: A normal exit (Ctrl+D/EOF or `/exit`) with a known session now asks `Purge this session on exit? [Y/n]` (default label reflecting the configured value), via a new `LiveInput.readYesNoKey()`. A hard exit (Ctrl+C, either variant from Decision 12) skips this and uses the configured default directly — mirroring how it already skipped nothing *but* the confirmation for the idle case before this existed.

**Why the confirmation has to run before the `finally` that restores terminal mode**: `readYesNoKey()` needs `LiveInput`'s raw single-key reader, which depends on the terminal still being in the raw/no-echo mode held for the whole session. The confirmation call was placed at the end of the existing `try` block (after the main loop, before its `finally`), not after the `try/finally` — restoring terminal mode first would silently break the raw read.

**Why `readYesNoKey()` doesn't redraw the live prompt afterward (unlike `readApprovalKey()`)**: Its only caller runs right before the process exits. Redrawing an empty prompt there would just leave stray output ahead of "Session purged." / "Session not purged." — the same class of bug Decision 11 fixed for Ctrl+D, reintroduced by a redraw that made sense for `readApprovalKey()`'s use case (resuming composing) but not this one.

**Why the outcome is always reported, not only on purge**: A hard exit silently applying a "don't purge" default previously printed nothing at all — no confirmation a decision was even made. Reporting both outcomes closes that gap without needing to explain *why* (matching the existing "Session purged." message's level of detail).

**Alternatives considered**:
- Always use the configured default silently, no confirmation ever: Simpler, but was the original (reported) behavior — a normal exit is exactly the case where the user has a moment to decide, so asking is low-cost and higher-fidelity than committing to a config-time default.
- Prompt on hard exit too: Rejected — Ctrl+C already means "get me out now," and delaying that on a fresh interactive prompt undermines the point of a hard exit.

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| **Dim contrast on high-contrast light themes** | Dim is ephemeral on spinners and a stylistic choice on permanent markers — borderline low-contrast is acceptable for these use cases. If real user feedback shows this is unreadable, we can add fallback to `bold` on light terminals. |
| **SIGWINCH not handled on Windows** | `dart_console` abstracts this; Windows systems won't receive SIGWINCH but will still redraw on the next keystroke (no breakage, just delayed). |
| **Historic message alignment drifts after resize** | Expected and documented. Users typing a new message after resize see it correctly aligned; old messages above it may be misaligned. This is standard behavior in any append-only scrolling CLI (e.g., tail, less, Claude Code itself). |
| **Terminal font rendering of braille glyphs** | Braille glyphs are in the Unicode standard and supported by all modern terminals; fallback risk is minimal. User can always check font support before sending messages. |
| **Cursor row/column math (`rowColFor`) disagrees with a given terminal's actual wrap behavior** | Covered by direct unit tests for the deferred-wrap edge cases (exact-row-boundary, multi-row offsets). Confined to a single line (see Decision 7), which limits how wrong it can go — worst case is a mispositioned cursor on that one line, not corrupted history. |
| **Abandoned mid-cycle request keeps running in the background briefly after Ctrl+C** | Not cancelled at the network level (Decision 12) — harmless since the process exits shortly after via the normal shutdown sequence, which implicitly tears down any lingering connections. |
| **Exit code for a Ctrl+C-triggered exit changed from 0 to 130** | Intentional (Decision 12/13) and follows the standard 128+SIGINT convention; called out explicitly as a breaking change in the proposal since a script checking this CLI's exit code would previously always see 0. |

## Migration Plan

**Deployment**:
1. Replace `renderInputBoxLines()` in `input_box.dart` to return `[markerBegin, ...textLines, '', markerEnd]` (no hard-wrap).
2. Add spinner timer and SIGWINCH listener to `LiveInput`.
3. Update `_redraw()` to include separator line and spinner row (when active).
4. Update `busy` setter to start/stop the spinner timer.
5. No changes to `chat_command.dart` (already interleaves correctly).
6. Remove old test coverage of the bordered box; add new tests for markers and spinner.

**Rollback**: If needed, revert the above changes and restore the original `renderInputBoxLines()` and `_redraw()` logic. No data or session state changes, so rollback is straightforward.

## Open Questions

None — the design covers all required decisions. Spinner animation speed (80ms per frame) can be tuned post-launch based on user feedback, but does not require design changes.
