import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_console/dart_console.dart';

import 'input_box.dart';
import 'prompt_decorations.dart';

/// Drives the REPL's live-updating input prompt directly from raw stdin
/// bytes, running continuously for the whole chat session — not re-created
/// per turn — so keystrokes typed while a cycle is in flight are captured
/// and shown immediately (forming a visible queue) instead of being
/// silently buffered until the next prompt.
///
/// While composing, input stays behind the "> " prompt — a `\`-continued
/// message spans plain, unmarked lines (first prefixed "> ", the rest
/// "  "): the content is still mutable, so it isn't rendered as a finished
/// artifact. Once submitted, the message is immutable, and is echoed once
/// with dim braille markers (see [input_box.dart]) to mark it as a settled
/// part of the transcript.
///
/// Deliberately hand-rolled rather than built on `cli_repl`: reading raw
/// bytes while a cycle is in flight requires stdin's async `Stream`
/// interface (a blocking synchronous read, like `cli_repl` uses, would
/// stall the event loop and the in-flight HTTP call with it), and mixing
/// sync and async reads of the same `Stdin` is unsafe.
class LiveInput {
  final Console console;
  final StreamQueue<int> _bytes;

  String _buffer = '';

  /// Cursor position within the *current* (last, still-mutable) line of
  /// [_buffer] — i.e. an offset into `_buffer.substring(_lastLineStart)`,
  /// not into the whole buffer. Editing (arrow keys, Home/End, insert,
  /// Backspace, Delete) is scoped to this one line; earlier `\`-continued
  /// lines are already committed to the drawn transcript above it and
  /// aren't revisited.
  int _cursorCol = 0;

  /// Rows the cursor was moved up from the trailing block's natural
  /// bottom-right end during the last redraw, to reflect [_cursorCol]
  /// sitting before the end of a wrapped line. Reversed at the start of
  /// [_erase], which otherwise assumes the cursor starts at that natural
  /// end position.
  int _trailingCursorRowsUp = 0;

  /// Terminal rows occupied by fully committed (newline-terminated) lines
  /// above the cursor's current row — accounting for lines that wrap at
  /// the terminal width, not just literal `\n` count.
  int _renderedRows = 0;

  /// Terminal rows the trailing, not-yet-newline-terminated line
  /// currently occupies (the cursor sits at the end of the last of
  /// these), so typing continues right after it rather than committing to
  /// a blank row below. Always >= 1 once anything has been drawn.
  int _trailingRows = 0;

  /// Whether any compose line spanned more than one row in the most
  /// recent draw — see [_handleResize] for why this changes how a resize
  /// is handled.
  bool _composeMayHaveWrapped = false;

  /// Rows abandoned by [_handleResize] (see its doc comment) that haven't
  /// been cleaned up yet. Erased opportunistically by [_erase] the next
  /// time it runs from a state where row tracking is trustworthy again,
  /// so a resize doesn't leave permanent debris in the scrollback.
  int _orphanRows = 0;

  /// Debounces bursty SIGWINCH delivery (a resize *drag* fires one event
  /// per column, not one for the whole gesture) so a single drag produces
  /// at most one resize response instead of dozens.
  Timer? _resizeDebounce;

  /// Set by the caller around each `runCycle` call. Only affects what
  /// Enter does — sequential turn enforcement still applies.
  bool _busy = false;

  Completer<String?>? _lineCompleter;

  /// Messages submitted while a cycle is in flight, in submission order,
  /// not yet dispatched. Shown in the live region (plain, unmarked style
  /// — not yet "sent") until the current cycle settles, at which point
  /// [nextMessage] pops all of them, joins them with `\n`, and dispatches
  /// them as a single turn rather than one round-trip per message.
  final List<String> _queuedMessages = [];

  Completer<int>? _approvalCompleter;

  Completer<int>? _yesNoCompleter;

  /// Whether the REPL is exiting because of Ctrl+C (a "hard" exit) rather
  /// than Ctrl+D/EOF or `/exit` (a "normal" one). The caller checks this
  /// after [nextMessage] returns `null` to decide whether to prompt for
  /// a purge-on-exit confirmation or just use the configured default —
  /// see [readYesNoKey].
  bool exitedViaCtrlC = false;

  /// Completed (and immediately replaced with a fresh one) whenever
  /// Ctrl+C is pressed while a cycle is in flight — see
  /// [waitForInterrupt]. Always non-null so a caller can start racing it
  /// before Ctrl+C happens, not just after.
  Completer<void> _interruptCompleter = Completer<void>();

  /// Resolves the next time Ctrl+C is pressed while a cycle is in
  /// flight. A caller awaiting an in-flight request can race this
  /// against it (e.g. via `Future.any`) to abandon the wait and proceed
  /// straight to shutdown, instead of hard-killing the process outright
  /// — which is what happened before this existed, and skipped any
  /// shutdown/purge logic entirely.
  Future<void> waitForInterrupt() => _interruptCompleter.future;

  /// Marks the REPL as exiting via Ctrl+C and fires [waitForInterrupt],
  /// swapping in a fresh completer first so a second mid-cycle Ctrl+C
  /// (if the caller doesn't exit immediately) can signal again.
  void _signalMidCycleInterrupt() {
    exitedViaCtrlC = true;
    final previous = _interruptCompleter;
    _interruptCompleter = Completer<void>();
    previous.complete();
  }

  /// Timer for spinner animation while response is in flight.
  Timer? _spinnerTimer;

  /// Current frame index in the spinner animation, see [spinnerFrames].
  int _spinnerFrame = 0;

  LiveInput(this.console)
      : _bytes = StreamQueue<int>(stdin.expand((chunk) => chunk));

  /// Index in [_buffer] where the current (last) line starts — right
  /// after the last `\n`, or 0 if the buffer has no committed lines yet.
  int get _lastLineStart {
    final idx = _buffer.lastIndexOf('\n');
    return idx == -1 ? 0 : idx + 1;
  }

  /// The current (last, still-mutable) line's text.
  String get _lastLine => _buffer.substring(_lastLineStart);

  /// Whether a cycle is in flight. Setting this starts/stops the loading
  /// spinner shown above the compose line, in addition to gating what
  /// Enter does (sequential turn enforcement).
  bool get busy => _busy;
  set busy(bool value) {
    if (_busy == value) return;
    _busy = value;
    if (_busy) {
      _startSpinner();
    } else {
      _stopSpinner();
    }
  }

  void _startSpinner() {
    _spinnerFrame = 0;
    _spinnerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      // An approval or yes/no prompt owns the screen for the duration of
      // readApprovalKey()/readYesNoKey() — both call hideForPrint()
      // before asking their question and only redraw the live region
      // once answered. The spinner also implies "the engine is actively
      // working," which isn't true while blocked on a human decision.
      // Skip the tick entirely rather than redraw on top of the prompt.
      if (_approvalCompleter != null || _yesNoCompleter != null) return;
      _spinnerFrame = (_spinnerFrame + 1) % spinnerFrames.length;
      _redraw();
    });
    _redraw();
  }

  void _stopSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = null;
    _redraw();
  }

  /// Starts the background read loop. Call once per session.
  ///
  /// Also listens for terminal resize (SIGWINCH, POSIX only — absent on
  /// Windows, where the prompt simply waits for the next keystroke to
  /// pick up the new width) so the live region redraws at the new width
  /// immediately rather than only on the next keystroke.
  void start() {
    unawaited(_readLoop());
    if (!Platform.isWindows) {
      try {
        ProcessSignal.sigwinch.watch().listen((_) {
          _resizeDebounce?.cancel();
          _resizeDebounce = Timer(
            const Duration(milliseconds: 100),
            _handleResize,
          );
        });
      } on SignalException {
        // No SIGWINCH support in this environment; fall through untouched.
      }
    }
  }

  /// Handles a terminal resize (after debouncing settles).
  ///
  /// `_erase()` walks the cursor up using `_renderedRows`/`_trailingRows`,
  /// which were computed against the *old* width. Many terminal emulators
  /// reflow already-drawn content on resize (e.g. a line that wrapped to 2
  /// rows at a narrow width un-wraps to 1 row once widened) — when that
  /// happens, those cached counts no longer match what's actually on
  /// screen, and erasing by that stale count would move the cursor to the
  /// wrong row and corrupt the display instead of cleanly clearing it.
  ///
  /// That risk only exists when some line actually spanned more than one
  /// row at the old width — the separator and spinner rows are always
  /// exactly one row by construction, so the only way it can happen is a
  /// long compose line. When nothing wrapped, the cached counts are still
  /// accurate (nothing for the terminal to have reflowed), so a normal
  /// erase-and-redraw is exactly as safe as any other redraw and is
  /// preferred — it doesn't leave a duplicate behind. Only when a compose
  /// line may have wrapped do we abandon the old prompt area (leaving it
  /// as `_orphanRows` for [_erase] to clean up later, once row tracking
  /// is trustworthy again) and start counting fresh from a new line,
  /// trading temporary debris for guaranteed-correct cursor tracking.
  void _handleResize() {
    // Same reasoning as the spinner tick guard: an approval/yes-no
    // prompt owns the screen (hideForPrint() already erased the live
    // region, and it stays hidden until answered), so there's nothing
    // here to resize. Redrawing now would land right on top of the
    // pending question instead. The prompt's own post-answer redraw
    // will pick up the current width whenever it happens.
    if (_approvalCompleter != null || _yesNoCompleter != null) return;

    if (!_composeMayHaveWrapped) {
      _redraw();
      return;
    }
    _orphanRows += _renderedRows + _trailingRows;
    _renderedRows = 0;
    _trailingRows = 0;
    console.write('\n');
    _redraw();
  }

  /// Draws the initial empty prompt. Call once, right after [start].
  void showInitialPrompt() => _redraw();

  /// Waits for the next message to send: any messages already queued
  /// while the previous cycle was in flight, joined and dispatched as one
  /// turn, if any — otherwise the next one the user submits. Returns
  /// `null` on Ctrl+D (EOF) with an empty buffer, or on Ctrl+C while idle
  /// — both signal the caller to shut down gracefully rather than
  /// hard-exiting the process.
  Future<String?> nextMessage() async {
    if (_queuedMessages.isNotEmpty) {
      return _dispatchQueuedMessages();
    }
    final completer = Completer<String?>();
    _lineCompleter = completer;
    return completer.future;
  }

  /// Waits for a single-key grant/decline answer ('g' or 'c'); any other
  /// key is ignored. Hides the input prompt for the duration (it may be
  /// mid-way through a queued message) and redraws it afterward.
  Future<String> readApprovalKey() async {
    final completer = Completer<int>();
    _approvalCompleter = completer;
    final byte = await completer.future;
    final char = String.fromCharCode(byte);
    stdout.writeln(char);
    _redraw();
    return char;
  }

  /// Waits for a yes/no answer ('y'/'n', case-insensitive) or Enter to
  /// accept [defaultValue]; any other key is ignored. Unlike
  /// [readApprovalKey], this does *not* redraw the live prompt
  /// afterward — its only caller today asks this right before the
  /// process exits, where redrawing an empty prompt would just leave
  /// stray output ahead of whatever prints next.
  Future<bool> readYesNoKey({required bool defaultValue}) async {
    final completer = Completer<int>();
    _yesNoCompleter = completer;
    final byte = await completer.future;
    final bool result;
    if (byte == 0x0d || byte == 0x0a) {
      result = defaultValue;
      stdout.writeln(defaultValue ? 'y' : 'n');
    } else {
      result = String.fromCharCode(byte).toLowerCase() == 'y';
      stdout.writeln(String.fromCharCode(byte));
    }
    return result;
  }

  /// Erases the live prompt before printing other output (a notification,
  /// the assistant's reply, an error) so it doesn't get interleaved with,
  /// or left stranded above, freshly printed transcript lines.
  void hideForPrint() => _erase();

  /// Redraws the prompt after printing other output, so composing (or a
  /// still-forming queued message) resumes visibly beneath it.
  void showAfterPrint() => _redraw();

  Future<void> _readLoop() async {
    while (await _bytes.hasNext) {
      final byte = await _bytes.next;

      if (byte == 0x1b) {
        // Always parse the full sequence (never a fixed byte count — a
        // numeric CSI sequence like Delete's `ESC [ 3 ~` is longer than
        // an arrow key's `ESC [ D`) so the byte stream stays in sync
        // regardless of what's currently active. Only *apply* the result
        // outside an approval prompt: hideForPrint() has already erased
        // the compose prompt for the duration, and would otherwise get
        // redrawn on top of the approval text.
        final key = await _readEscapeKey();
        if (_approvalCompleter == null && _yesNoCompleter == null) {
          _applyEscapeKey(key);
        }
        continue;
      }

      final approvalCompleter = _approvalCompleter;
      if (approvalCompleter != null) {
        if (byte == 0x03) {
          // Ctrl+C during an approval prompt is still mid-cycle (the
          // engine is waiting on this decision) — signal the same
          // interrupt as pressing it anywhere else mid-cycle, so the
          // caller can abandon the wait (including this pending
          // approval) rather than Ctrl+C being silently swallowed here.
          _approvalCompleter = null;
          _erase();
          stdout.writeln();
          _signalMidCycleInterrupt();
          continue;
        }
        final char = String.fromCharCode(byte).toLowerCase();
        if (char == 'g' || char == 'c') {
          _approvalCompleter = null;
          approvalCompleter.complete(byte);
        }
        continue;
      }

      final yesNoCompleter = _yesNoCompleter;
      if (yesNoCompleter != null) {
        if (byte == 0x0d || byte == 0x0a) {
          _yesNoCompleter = null;
          yesNoCompleter.complete(byte);
        } else {
          final char = String.fromCharCode(byte).toLowerCase();
          if (char == 'y' || char == 'n') {
            _yesNoCompleter = null;
            yesNoCompleter.complete(byte);
          }
        }
        continue;
      }

      _handleComposeByte(byte);
    }
  }

  void _handleComposeByte(int byte) {
    switch (byte) {
      case 0x03: // Ctrl+C
        _erase();
        stdout.writeln();
        if (_lineCompleter != null) {
          // Idle, waiting for the next message: hand off to the same
          // path Ctrl+D/EOF uses below, so the caller's normal shutdown
          // (restoring the terminal, reporting/running the configured
          // session purge) runs instead of being skipped by an immediate
          // process exit. exitedViaCtrlC lets the caller tell this apart
          // from a normal Ctrl+D/`/exit`, since Ctrl+C is a "hard" exit
          // that skips any exit-time confirmation prompts.
          exitedViaCtrlC = true;
          _lineCompleter?.complete(null);
          _lineCompleter = null;
        } else {
          // Mid-cycle: nothing here can gracefully cancel the in-flight
          // HTTP call, but the caller can still abandon *waiting* on it
          // and proceed to shutdown — see waitForInterrupt().
          _signalMidCycleInterrupt();
        }
      case 0x04: // Ctrl+D / EOF
        if (_buffer.isEmpty) {
          // Leave the cursor on a fresh line — the live prompt is still
          // visible on screen at this point, and whatever the caller
          // prints next as it shuts down (e.g. "Session purged.") would
          // otherwise land glued right after the "> " prompt.
          _erase();
          stdout.writeln();
          _lineCompleter?.complete(null);
          _lineCompleter = null;
        }
      case 0x7f: // Backspace
      case 0x08:
        if (_cursorCol > 0) {
          final idx = _lastLineStart + _cursorCol - 1;
          _buffer = _buffer.substring(0, idx) + _buffer.substring(idx + 1);
          _cursorCol--;
          _redraw();
        }
      case 0x0d: // Enter
      case 0x0a:
        _submitOrContinue();
      default:
        if (byte >= 0x20 && byte < 0x7f) {
          final idx = _lastLineStart + _cursorCol;
          _buffer = _buffer.substring(0, idx) +
              String.fromCharCode(byte) +
              _buffer.substring(idx);
          _cursorCol++;
          _redraw();
        }
    }
  }

  /// Parses one escape sequence from the byte stream and returns the key
  /// it represents (`null` for anything unrecognized). Always consumes
  /// exactly the sequence's bytes — sequences vary in length (an arrow
  /// key is `ESC [ <letter>`, but Delete is the longer numeric CSI form
  /// `ESC [ 3 ~`), so a fixed byte count would desync the stream.
  Future<String?> _readEscapeKey() async {
    if (!await _bytes.hasNext) return null;
    final b1 = await _bytes.next;
    if (b1 != 0x5b && b1 != 0x4f) return null; // not '[' or 'O'

    if (!await _bytes.hasNext) return null;
    final b2 = await _bytes.next;

    switch (b2) {
      case 0x43:
        return 'right';
      case 0x44:
        return 'left';
      case 0x48:
        return 'home';
      case 0x46:
        return 'end';
    }

    if (b1 == 0x5b && b2 >= 0x30 && b2 <= 0x39) {
      // Numeric CSI form: ESC [ <digits> ~ (or any non-digit terminator).
      var num = b2 - 0x30;
      while (await _bytes.hasNext) {
        final b3 = await _bytes.next;
        if (b3 < 0x30 || b3 > 0x39) break; // consumes the terminator
        num = num * 10 + (b3 - 0x30);
      }
      switch (num) {
        case 1:
          return 'home';
        case 3:
          return 'delete';
        case 4:
          return 'end';
      }
    }

    return null; // e.g. arrow Up/Down — recognized-but-unsupported
  }

  void _applyEscapeKey(String? key) {
    switch (key) {
      case 'left':
        _moveCursor(-1);
      case 'right':
        _moveCursor(1);
      case 'home':
        if (_cursorCol != 0) {
          _cursorCol = 0;
          _redraw();
        }
      case 'end':
        final end = _lastLine.length;
        if (_cursorCol != end) {
          _cursorCol = end;
          _redraw();
        }
      case 'delete':
        _deleteForward();
    }
  }

  void _moveCursor(int delta) {
    final newCol = (_cursorCol + delta).clamp(0, _lastLine.length);
    if (newCol == _cursorCol) return;
    _cursorCol = newCol;
    _redraw();
  }

  void _deleteForward() {
    final line = _lastLine;
    if (_cursorCol >= line.length) return;
    final idx = _lastLineStart + _cursorCol;
    _buffer = _buffer.substring(0, idx) + _buffer.substring(idx + 1);
    _redraw();
  }

  /// A trailing `\` continues composing onto a new line; otherwise this
  /// finalizes the buffer. Queues it (visible in the live region, not yet
  /// "sent") — if the caller is idle and already waiting via
  /// [nextMessage], that queue is immediately drained and dispatched;
  /// otherwise it waits alongside any other pending messages until the
  /// in-flight cycle settles and [nextMessage] is called again.
  void _submitOrContinue() {
    if (_buffer.endsWith('\\')) {
      _buffer = '${_buffer.substring(0, _buffer.length - 1)}\n';
      _cursorCol = 0;
      _redraw();
      return;
    }

    final content = _buffer;
    _buffer = '';
    _cursorCol = 0;

    if (content.trim().isEmpty) {
      _redraw();
      return;
    }

    _queuedMessages.add(content);

    final completer = _lineCompleter;
    if (completer != null) {
      _lineCompleter = null;
      completer.complete(_dispatchQueuedMessages());
      return;
    }

    // Busy: nothing waiting to dispatch to yet. Just show it as pending
    // in the live region until the current cycle settles.
    _redraw();
  }

  /// Pops every currently-queued message, joins them into a single turn,
  /// and marks that combined content as sent (dim markers, permanent
  /// transcript) — this is the one point where queued content stops
  /// being "pending" and becomes "dispatched," which is also exactly
  /// when its spinner should appear, so the two can never drift apart
  /// the way printing on queue (rather than on dispatch) previously did.
  String _dispatchQueuedMessages() {
    final combined = _queuedMessages.join('\n');
    _queuedMessages.clear();
    _erase();
    _printSent(combined);
    _redraw();
    return combined;
  }

  /// Echoes a just-submitted message with dim braille markers — a one-time,
  /// permanent transcript entry, not part of the live-redrawn prompt.
  void _printSent(String content) {
    console.setTextStyle(faint: true);
    for (final line in renderInputBoxLines(content)) {
      console.write(line);
      console.write('\n');
    }
    console.resetColorAttributes();
  }

  /// Terminal rows a single already-prefixed line occupies, accounting
  /// for wrapping at the terminal width — not just the trivial 1 row a
  /// naive newline-count would assume.
  int _rowsFor(String text) {
    final width = console.windowWidth;
    if (width <= 0) return 1;
    return (text.length / width).ceil().clamp(1, 1 << 30);
  }

  void _redraw() {
    _erase();

    // Spinner above the separator: it's status about system activity, not
    // part of the user's input area — the separator marks where the
    // purely-interactive prompt begins.
    if (busy) {
      _writeSpinnerRow();
    }
    _writeSeparator();

    _composeMayHaveWrapped = false;
    _writeQueuedMessages();

    final lines = _buffer.split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final text = '${i == 0 ? '> ' : '  '}${lines[i]}';
      // Raw write rather than Console.writeLine/writeAligned, which pads
      // every line out to the full terminal width and would otherwise
      // leave stray padding behind once a shorter line replaces a longer
      // one at the same row.
      console.write(text);
      console.write('\n');
      final rows = _rowsFor(text);
      _renderedRows += rows;
      if (rows > 1) _composeMayHaveWrapped = true;
    }

    // The last line is deliberately not newline-terminated: the cursor
    // stays right after it on the current row instead of committing to a
    // blank row below, so typing continues in place.
    final lastText = '${lines.length == 1 ? '> ' : '  '}${lines.last}';
    console.write(lastText);
    _trailingRows = _rowsFor(lastText);
    if (_trailingRows > 1) _composeMayHaveWrapped = true;

    // The write above leaves the cursor at the natural end of lastText.
    // If the edit cursor sits somewhere before that (not simply
    // appending), walk it back to the right row/column.
    final targetOffset = (2 + _cursorCol).clamp(0, lastText.length);
    if (targetOffset < lastText.length) {
      final width = console.windowWidth;
      final (endRow, endCol) = rowColFor(lastText.length, width);
      final (targetRow, targetCol) = rowColFor(targetOffset, width);
      final rowsUp = endRow - targetRow;
      if (rowsUp > 0) {
        console.write('\r');
        for (var i = 0; i < rowsUp; i++) {
          console.cursorUp();
        }
        for (var i = 0; i < targetCol; i++) {
          console.cursorRight();
        }
        _trailingCursorRowsUp = rowsUp;
      } else {
        for (var i = 0; i < endCol - targetCol; i++) {
          console.cursorLeft();
        }
      }
    }
  }

  /// Messages submitted while busy but not yet dispatched — shown plain
  /// (not dim; not yet a "sent" artifact, same reasoning as the
  /// currently-composing line) so the user can see what's piled up
  /// without it being mistaken for already-sent, already-in-flight
  /// content. Marked "sent" only once [_dispatchQueuedMessages] runs.
  void _writeQueuedMessages() {
    for (final queued in _queuedMessages) {
      final qLines = queued.split('\n');
      for (var i = 0; i < qLines.length; i++) {
        final text = '${i == 0 ? '» ' : '  '}${qLines[i]}';
        console.write(text);
        console.write('\n');
        final rows = _rowsFor(text);
        _renderedRows += rows;
        if (rows > 1) _composeMayHaveWrapped = true;
      }
    }
  }

  /// Fixed-length dim divider marking the boundary between the immutable
  /// transcript above and the live prompt below — see [separatorLine] for
  /// why it's a short constant rather than spanning the terminal width.
  void _writeSeparator() {
    console.setTextStyle(faint: true);
    console.write(separatorLine);
    console.resetColorAttributes();
    console.write('\n');
    _renderedRows += 1;
  }

  /// Dim animated braille frame + label shown above the compose line
  /// while [busy], so a still-forming queued message stays visible right
  /// beneath the loading indicator.
  void _writeSpinnerRow() {
    final text = renderSpinnerLine(_spinnerFrame);
    console.setTextStyle(faint: true);
    console.write(text);
    console.resetColorAttributes();
    console.write('\n');
    _renderedRows += _rowsFor(text);
  }

  void _erase() {
    // The rest of this method assumes the cursor starts at the trailing
    // block's natural bottom-right end (where writing left it). If the
    // last redraw moved it up to reflect an interior edit position (see
    // _redraw), undo that first — moving down doesn't need to also
    // restore the column, since the very next line resets to column 0.
    if (_trailingCursorRowsUp > 0) {
      for (var i = 0; i < _trailingCursorRowsUp; i++) {
        console.cursorDown();
      }
      _trailingCursorRowsUp = 0;
    }

    if (_trailingRows > 0) {
      console.write('\r');
      console.eraseLine();
      for (var i = 1; i < _trailingRows; i++) {
        console.cursorUp();
        console.eraseLine();
      }
      _trailingRows = 0;
    }
    for (var i = 0; i < _renderedRows; i++) {
      console.cursorUp();
      console.eraseLine();
    }
    _renderedRows = 0;

    // Every _erase() call runs from a state where row tracking is
    // trustworthy (it's either normal typing at a stable width, or the
    // safe branch of _handleResize) — so this is always a safe moment to
    // sweep up whatever a prior abandoned resize left behind.
    for (var i = 0; i < _orphanRows; i++) {
      console.cursorUp();
      console.eraseLine();
    }
    _orphanRows = 0;
  }
}
