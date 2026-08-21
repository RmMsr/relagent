import 'package:relagent_cli/input_box.dart';
import 'package:test/test.dart';

void main() {
  group('renderInputBoxLines', () {
    test('renders a single short line with markers', () {
      final lines = renderInputBoxLines('hi');

      expect(lines, hasLength(3)); // marker, text, marker
      expect(lines[0], equals('⢆⣀⣀'));
      expect(lines[1], equals('hi'));
      expect(lines[2], equals('⠎⠉⠉'));
    });

    test('empty buffer renders with markers and one empty text line', () {
      final lines = renderInputBoxLines('');

      expect(lines, hasLength(3));
      expect(lines[0], equals('⢆⣀⣀'));
      expect(lines[1], isEmpty);
      expect(lines[2], equals('⠎⠉⠉'));
    });

    test('embedded newlines produce one line per input line plus markers', () {
      final lines = renderInputBoxLines('first\nsecond\nthird');

      // 3 input lines + 2 markers
      expect(lines, hasLength(5));
      expect(lines[0], equals('⢆⣀⣀'));
      expect(lines[1], equals('first'));
      expect(lines[2], equals('second'));
      expect(lines[3], equals('third'));
      expect(lines[4], equals('⠎⠉⠉'));
    });

    test('long lines are not hard-wrapped', () {
      final longLine = 'x' * 30;
      final lines = renderInputBoxLines(longLine);

      // No hard-wrap: just markers around the long line
      expect(lines, hasLength(3));
      expect(lines[1], equals(longLine));
    });
  });
}
