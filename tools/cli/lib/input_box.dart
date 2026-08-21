/// Pure, terminal-independent rendering of a sent chat message with
/// braille markers — used once a message is finalized and becomes part of
/// the immutable transcript record, never while it's still being typed.
///
/// Splits [buffer] on user line breaks only (no hard-wrapping, no width
/// parameter — the terminal's own soft-wrap handles overly long lines) and
/// frames the result with dim braille markers, producing the exact lines a
/// terminal renderer should print. Contains no I/O, so it is covered
/// directly by unit tests, independent of real terminal state.
List<String> renderInputBoxLines(String buffer) {
  final rawLines = buffer.isEmpty ? [''] : buffer.split('\n');

  const markerBegin = '⢆⣀⣀';
  const markerEnd = '⠎⠉⠉';

  return [markerBegin, ...rawLines, markerEnd];
}
