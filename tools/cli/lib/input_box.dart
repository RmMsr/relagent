/// Pure, terminal-independent rendering of a sent chat message as a
/// bordered box — used once a message is finalized and becomes part of
/// the immutable transcript record, never while it's still being typed.
///
/// Wraps each line of [buffer] to fit within [width] columns and frames the
/// result with a border, producing the exact lines a terminal renderer
/// should print. Contains no I/O, so it is covered directly by unit tests,
/// independent of real terminal state.
List<String> renderInputBoxLines(String buffer, {required int width}) {
  final effectiveWidth = width < 8 ? 8 : width;
  final innerWidth = effectiveWidth - 4; // border + one space of padding each side
  final rawLines = buffer.isEmpty ? [''] : buffer.split('\n');

  final wrapped = <String>[];
  for (final line in rawLines) {
    if (line.isEmpty) {
      wrapped.add('');
      continue;
    }
    var remaining = line;
    while (remaining.length > innerWidth) {
      wrapped.add(remaining.substring(0, innerWidth));
      remaining = remaining.substring(innerWidth);
    }
    wrapped.add(remaining);
  }

  final top = '┌${'─' * (effectiveWidth - 2)}┐';
  final bottom = '└${'─' * (effectiveWidth - 2)}┘';
  final body = wrapped
      .map((line) => '│ ${line.padRight(innerWidth)} │')
      .toList();

  return [top, ...body, bottom];
}
