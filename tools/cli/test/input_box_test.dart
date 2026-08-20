import 'package:relagent_cli/input_box.dart';
import 'package:test/test.dart';

void main() {
  group('renderInputBoxLines', () {
    test('renders a single short line as a 3-row box', () {
      final lines = renderInputBoxLines('hi', width: 20);

      expect(lines, hasLength(3));
      expect(lines.first, startsWith('┌'));
      expect(lines.last, startsWith('└'));
      expect(lines[1], contains('hi'));
    });

    test('empty buffer still renders a box with one blank body row', () {
      final lines = renderInputBoxLines('', width: 20);

      expect(lines, hasLength(3));
    });

    test('every rendered line has the same width', () {
      final lines = renderInputBoxLines('hello\nworld', width: 20);

      final widths = lines.map((l) => l.length).toSet();
      expect(widths, hasLength(1));
    });

    test('embedded newlines produce one body row per input line', () {
      final lines = renderInputBoxLines('first\nsecond\nthird', width: 20);

      // 3 input lines + top + bottom border.
      expect(lines, hasLength(5));
      expect(lines[1], contains('first'));
      expect(lines[2], contains('second'));
      expect(lines[3], contains('third'));
    });

    test('a line longer than the inner width wraps onto extra body rows', () {
      final longLine = 'x' * 30;
      final lines = renderInputBoxLines(longLine, width: 20);

      // inner width is 20 - 4 = 16, so 30 chars wraps into 2 body rows.
      expect(lines, hasLength(4));
      expect(lines[1].contains('x' * 16), isTrue);
    });

    test('a very small width is clamped to a usable minimum', () {
      final lines = renderInputBoxLines('hi', width: 1);

      expect(lines.every((l) => l.length >= 8), isTrue);
    });
  });
}
