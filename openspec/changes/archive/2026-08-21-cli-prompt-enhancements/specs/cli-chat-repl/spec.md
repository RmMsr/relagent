## ADDED Requirements

### Requirement: Sent messages are visually distinguished from responses
The REPL SHALL display user-sent messages with braille marker glyphs above and below the message text to visually distinguish them from assistant responses, without using a bordered box.

#### Scenario: User message appears with markers
- **WHEN** the user submits a message
- **THEN** a dim line of `⢆⣀⣀` appears above the message text
- **AND** the message text is displayed in dim styling
- **AND** a dim line of `⠎⠉⠉` appears below the message text

### Requirement: Separator line marks boundary between transcript and prompt
The REPL SHALL display a short, fixed-length dim divider between the immutable chat transcript and the live input/spinner region, independent of terminal width.

#### Scenario: Separator appears above the prompt
- **WHEN** the REPL is idle and waiting for user input
- **THEN** a fixed-length dim divider (10 solid characters followed by 10 dotted characters) appears immediately above the compose prompt

#### Scenario: Separator is unaffected by terminal resize
- **WHEN** the terminal width changes while the REPL is running
- **THEN** the separator's appearance does not change, since it does not depend on terminal width

### Requirement: Loading indicator animates while response is in flight
The REPL SHALL display an animated braille spinner and "Thinking…" label above the input area while waiting for the engine's response.

#### Scenario: Spinner starts when message is sent
- **WHEN** a message is submitted and the REPL is awaiting a response
- **THEN** a dim animated braille spinner frame appears above the separator line with the label "Thinking…" — the separator marks where the purely-interactive input area begins, so status like the spinner stays above it

#### Scenario: Spinner continues while user types queued messages
- **WHEN** the user types additional text while the previous response is still in flight
- **THEN** the spinner continues to animate above the queued text

#### Scenario: Spinner stops when response arrives
- **WHEN** the engine's response is received and begins streaming
- **THEN** the spinner stops animating and is erased before the response is printed

### Requirement: Live prompt redraws immediately on terminal resize
The REPL SHALL redraw the live input area (compose lines, spinner) at the new terminal width shortly after a resize instead of waiting for the next keystroke. The separator's own content does not depend on width (see the separator requirement above) and needs no recomputation, but remains part of the redrawn region.

#### Scenario: Prompt redraws on terminal resize
- **WHEN** the terminal is resized while the REPL is active
- **THEN** the live prompt region (spinner if active, input area, with the fixed-length separator above it) is redrawn to fit the new width within roughly 100ms of the resize settling

#### Scenario: Resized messages stay readable
- **WHEN** a user-sent message was printed at the previous terminal width and the terminal is then resized
- **THEN** the message text, markers, and subsequent messages remain readable (no attempt to reflow historic messages; only new messages use the new width)

### Requirement: Message text respects only user line breaks
The REPL SHALL NOT hard-wrap user message text at a fixed column width; instead, message text is printed as-is and the terminal's soft-wrap handles line breaks.

#### Scenario: Long line wraps naturally
- **WHEN** a user types a line longer than the terminal width
- **THEN** the line is not manually broken with inserted `\n` characters; the terminal's soft-wrap displays it across multiple visual lines
- **AND** when the terminal is resized, the visual wrapping is recomputed by the terminal without the app doing anything

#### Scenario: Multi-line input preserves user line breaks
- **WHEN** a user types multiple lines (using `\` continuation)
- **THEN** only the user's explicit `\n` line breaks are preserved; no additional breaks are inserted by the REPL

### Requirement: Cursor movement and mid-line editing while composing
The REPL SHALL let the user move the cursor within the current (last, still-being-typed) line and insert, backspace, or delete text at that position, not only append or remove characters from the end.

#### Scenario: Left/Right move the cursor within the current line
- **WHEN** the user presses the Left or Right arrow key while composing
- **THEN** the cursor moves one character back or forward within the current line, clamped to the line's start and end

#### Scenario: Home/End jump to the line's start or end
- **WHEN** the user presses Home or End while composing
- **THEN** the cursor moves to the start or end of the current line respectively

#### Scenario: Typing inserts at the cursor, not just at the end
- **WHEN** the cursor is positioned before the end of the current line and the user types a character
- **THEN** the character is inserted at the cursor position, the rest of the line shifts right, and the cursor advances by one

#### Scenario: Backspace and Delete remove relative to the cursor
- **WHEN** the user presses Backspace with the cursor not at the start of the line
- **THEN** the character immediately before the cursor is removed and the cursor moves back one position
- **WHEN** the user presses Delete with the cursor not at the end of the line
- **THEN** the character at the cursor position is removed and the cursor stays in place

#### Scenario: Editing does not cross into earlier committed lines
- **WHEN** the buffer contains earlier `\`-continued lines above the current one
- **THEN** cursor movement and editing only affect the current (last) line; earlier lines are not reachable via these keys

### Requirement: Ctrl+C always reaches the shutdown/purge sequence
The REPL SHALL run its normal shutdown sequence (restoring terminal state, running/reporting the configured session purge) on Ctrl+C regardless of whether it is pressed while idle or while a cycle is in flight (including during a pending approval decision), rather than exiting the process immediately without it. An in-flight request is not gracefully cancelled — the REPL abandons waiting on it, not the request itself — but the shutdown sequence still runs. Ctrl+C is always a "hard" exit: it skips the exit-time purge confirmation and uses the configured default, and exits with code 130.

#### Scenario: Ctrl+C while idle triggers shutdown
- **WHEN** the user presses Ctrl+C while the REPL is idle, waiting for the next message
- **THEN** the REPL shuts down through the same path used for Ctrl+D/EOF, including restoring terminal mode and running/reporting the configured session purge, using the configured default without prompting
- **AND** the process exits with code 130

#### Scenario: Ctrl+C mid-cycle also triggers shutdown
- **WHEN** the user presses Ctrl+C while a response is in flight
- **THEN** the REPL abandons waiting on that response and proceeds to the same shutdown sequence, using the configured default without prompting
- **AND** the process exits with code 130

#### Scenario: Ctrl+C during a pending approval also triggers shutdown
- **WHEN** the user presses Ctrl+C while an approval grant/decline decision is pending
- **THEN** the REPL abandons the pending approval and the request that requested it, and proceeds to the same shutdown sequence

#### Scenario: Ctrl+D/EOF leaves the cursor on a fresh line before shutdown output
- **WHEN** the user triggers Ctrl+D/EOF and the REPL prints shutdown output (such as a session purge result)
- **THEN** that output starts on its own line, not appended to the end of the live prompt

### Requirement: Purge confirmation on a normal exit
The REPL SHALL ask whether to purge the session when exiting normally (Ctrl+D/EOF or `/exit`) with a known session, defaulting to the configured `--purge-session` flag or "always purge" setting if the user accepts the default (pressing Enter). A hard exit (Ctrl+C) SHALL skip this confirmation and use the configured default directly. The REPL SHALL report the outcome either way ("Session purged." or "Session not purged."), not only when a purge happens.

#### Scenario: Normal exit with a known session asks for confirmation
- **WHEN** the user exits via Ctrl+D/EOF or `/exit` and a session is known
- **THEN** the REPL asks "Purge this session on exit?" with the configured default shown (e.g. `[Y/n]` or `[y/N]`)
- **AND** pressing Enter accepts that default; 'y'/'n' overrides it for this exit only

#### Scenario: Hard exit skips the confirmation
- **WHEN** the user exits via Ctrl+C (idle or mid-cycle)
- **THEN** the REPL does not ask for confirmation and uses the configured default directly

#### Scenario: The outcome is always reported
- **WHEN** the REPL exits with a known session
- **THEN** it prints "Session purged." if it purged, or "Session not purged." if it did not — never neither

### Requirement: Messages queued while busy dispatch as one turn
The REPL SHALL let multiple messages submitted while a cycle is in flight accumulate in order and, once the cycle settles, dispatch all of them together as a single turn rather than one round-trip per message. A queued message is marked "sent" (permanent transcript, dim markers) only when it is actually dispatched, not at the moment it is queued.

#### Scenario: A single queued message dispatches once the cycle settles
- **WHEN** the user submits one message while a cycle is in flight
- **THEN** it is shown in the live region in plain (not dim, not-yet-sent) style until the in-flight cycle settles
- **AND** once the cycle settles, it is marked sent and dispatched as the next turn

#### Scenario: Multiple queued messages combine into one turn
- **WHEN** the user submits more than one message while a cycle is in flight
- **THEN** all of them remain queued, each visible in the live region, until the in-flight cycle settles
- **AND** once it settles, they are joined with newlines, marked sent as a single combined block, and dispatched together as one turn

#### Scenario: No message is silently dropped when several are queued
- **WHEN** a second message is submitted while an earlier one is still queued (not yet dispatched)
- **THEN** both are retained and eventually dispatched; neither is discarded

### Requirement: The spinner does not appear while an approval decision is pending
The REPL SHALL NOT show or animate the loading spinner while waiting for the user's grant/decline decision on a tool-call approval, since the engine is not actively processing during that wait.

#### Scenario: Spinner is suppressed during an approval prompt
- **WHEN** the engine reports a pending approval and the REPL is showing the grant/decline prompt
- **THEN** the spinner does not appear or animate, and does not redraw over the approval prompt text

#### Scenario: Spinner resumes after the approval is answered
- **WHEN** the user answers the approval prompt and the cycle continues processing
- **THEN** the spinner resumes appearing and animating as normal
