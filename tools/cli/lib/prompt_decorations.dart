/// Pure, terminal-independent string construction for the live prompt's
/// decorative rows (the separator line and the loading spinner) — kept
/// separate from `LiveInput`'s I/O so the formatting itself is directly
/// unit-testable, the same way `input_box.dart` separates rendering from
/// printing.

/// Braille spinner frames for the loading animation, cycled while a cycle
/// is in flight.
const spinnerFrames = [
  '⠋',
  '⠙',
  '⠹',
  '⠸',
  '⢰',
  '⢠',
  '⡀',
  '⣄',
];

/// The divider line drawn between the immutable transcript and the live
/// prompt: 10 solid characters, 10 dotted characters, then nothing —
/// deliberately fixed-length rather than spanning the terminal width.
/// A full-width rule has to be recomputed and correctly re-erased on
/// every resize, which in practice proved too fragile (terminal-side
/// reflow can desync cached row counts from what's actually on screen).
/// A short, fixed string sidesteps that entirely: it never depends on
/// the terminal's current width, so there's nothing for a resize to
/// invalidate.
final separatorLine = '${'─' * 10}${'┄' * 10}';

/// The spinner row's text for the given frame index, wrapping around the
/// frame count so any non-negative index is valid.
String renderSpinnerLine(int frameIndex) =>
    '${spinnerFrames[frameIndex % spinnerFrames.length]} Thinking…';

/// The (row, column) an absolute character offset [offset] lands on once
/// wrapped at terminal [width], both 0-indexed from the start of the
/// line. Accounts for the terminal's "deferred wrap": writing exactly a
/// full row's worth of characters leaves the cursor at the end of that
/// row rather than advancing to a new, empty one — it only advances once
/// another character is actually written. Used to move the compose
/// cursor to an interior edit position after redrawing the full line.
(int, int) rowColFor(int offset, int width) {
  if (width <= 0 || offset == 0) return (0, 0);
  final zeroBased = offset - 1;
  return (zeroBased ~/ width, (zeroBased % width) + 1);
}
