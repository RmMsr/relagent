import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dart_console/dart_console.dart';

import 'input_box.dart';

/// Drives the REPL's live-updating input prompt directly from raw stdin
/// bytes, running continuously for the whole chat session — not re-created
/// per turn — so keystrokes typed while a cycle is in flight are captured
/// and shown immediately (forming a visible queue) instead of being
/// silently buffered until the next prompt.
///
/// While composing, input stays behind the "> " prompt — a `\`-continued
/// message spans plain, unbordered lines (first prefixed "> ", the rest
/// "  "), never a boxed widget: the content is still mutable, so it isn't
/// rendered as a finished artifact. Once submitted, the message is
/// immutable, and is echoed once as a bordered box (see [input_box.dart])
/// to mark it as a settled part of the transcript.
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

  /// Terminal rows occupied by fully committed (newline-terminated) lines
  /// above the cursor's current row — accounting for lines that wrap at
  /// the terminal width, not just literal `\n` count.
  int _renderedRows = 0;

  /// Terminal rows the trailing, not-yet-newline-terminated line
  /// currently occupies (the cursor sits at the end of the last of
  /// these), so typing continues right after it rather than committing to
  /// a blank row below. Always >= 1 once anything has been drawn.
  int _trailingRows = 0;

  /// Set by the caller around each `runCycle` call. Only affects what
  /// Enter does — sequential turn enforcement still applies.
  bool busy = false;

  Completer<String?>? _lineCompleter;
  String? _queuedReady;

  Completer<int>? _approvalCompleter;

  LiveInput(this.console)
    : _bytes = StreamQueue<int>(stdin.expand((chunk) => chunk));

  /// Starts the background read loop. Call once per session.
  void start() {
    unawaited(_readLoop());
  }

  /// Draws the initial empty prompt. Call once, right after [start].
  void showInitialPrompt() => _redraw();

  /// Waits for the next message to send: a message already queued while
  /// the previous cycle was in flight, if any, otherwise the next one the
  /// user submits. Returns `null` on Ctrl+D (EOF) with an empty buffer.
  Future<String?> nextMessage() async {
    final ready = _queuedReady;
    if (ready != null) {
      _queuedReady = null;
      return ready;
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
        // Swallow escape sequences (arrow keys and similar) rather than
        // inserting their raw bytes into the buffer. Line navigation and
        // history aren't supported by this minimal reader.
        if (await _bytes.hasNext) {
          final next = await _bytes.next;
          if ((next == 0x5b || next == 0x4f) && await _bytes.hasNext) {
            await _bytes.next;
          }
        }
        continue;
      }

      final approvalCompleter = _approvalCompleter;
      if (approvalCompleter != null) {
        final char = String.fromCharCode(byte).toLowerCase();
        if (char == 'g' || char == 'c') {
          _approvalCompleter = null;
          approvalCompleter.complete(byte);
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
        exit(130);
      case 0x04: // Ctrl+D / EOF
        if (_buffer.isEmpty) {
          _lineCompleter?.complete(null);
          _lineCompleter = null;
        }
      case 0x7f: // Backspace
      case 0x08:
        if (_buffer.isNotEmpty) {
          _buffer = _buffer.substring(0, _buffer.length - 1);
          _redraw();
        }
      case 0x0d: // Enter
      case 0x0a:
        _submitOrContinue();
      default:
        if (byte >= 0x20 && byte < 0x7f) {
          _buffer += String.fromCharCode(byte);
          _redraw();
        }
    }
  }

  /// A trailing `\` continues composing onto a new line; otherwise this
  /// finalizes the buffer — dispatched immediately if idle, or queued for
  /// automatic dispatch the moment the in-flight cycle settles.
  void _submitOrContinue() {
    if (_buffer.endsWith('\\')) {
      _buffer = '${_buffer.substring(0, _buffer.length - 1)}\n';
      _redraw();
      return;
    }

    final content = _buffer;
    _buffer = '';

    if (content.trim().isEmpty) {
      _redraw();
      return;
    }

    _erase();
    _printSent(content);
    _redraw();

    if (busy) {
      _queuedReady = content;
      return;
    }

    _lineCompleter?.complete(content);
    _lineCompleter = null;
  }

  /// Echoes a just-submitted message as a bordered box — a one-time,
  /// permanent transcript entry, not part of the live-redrawn prompt.
  void _printSent(String content) {
    for (final line in renderInputBoxLines(
      content,
      width: console.windowWidth - 1,
    )) {
      console.write(line);
      console.write('\n');
    }
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

    final lines = _buffer.split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final text = '${i == 0 ? '> ' : '  '}${lines[i]}';
      // Raw write rather than Console.writeLine/writeAligned, which pads
      // every line out to the full terminal width and would otherwise
      // leave stray padding behind once a shorter line replaces a longer
      // one at the same row.
      console.write(text);
      console.write('\n');
      _renderedRows += _rowsFor(text);
    }

    // The last line is deliberately not newline-terminated: the cursor
    // stays right after it on the current row instead of committing to a
    // blank row below, so typing continues in place.
    final lastText = '${lines.length == 1 ? '> ' : '  '}${lines.last}';
    console.write(lastText);
    _trailingRows = _rowsFor(lastText);
  }

  void _erase() {
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
  }
}
