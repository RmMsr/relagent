import 'package:relagent_cli/prompt_decorations.dart';
import 'package:test/test.dart';

void main() {
  group('separatorLine', () {
    test('is 10 solid characters followed by 10 dotted characters', () {
      expect(separatorLine, equals('${'─' * 10}${'┄' * 10}'));
      expect(separatorLine, hasLength(20));
    });
  });

  group('renderSpinnerLine', () {
    test('frame 0 is the first spinner glyph with the label', () {
      expect(renderSpinnerLine(0), equals('${spinnerFrames[0]} Thinking…'));
    });

    test('cycles through all frames in order', () {
      for (var i = 0; i < spinnerFrames.length; i++) {
        expect(renderSpinnerLine(i), equals('${spinnerFrames[i]} Thinking…'));
      }
    });

    test('wraps around past the last frame', () {
      expect(
        renderSpinnerLine(spinnerFrames.length),
        equals(renderSpinnerLine(0)),
      );
      expect(
        renderSpinnerLine(spinnerFrames.length + 3),
        equals(renderSpinnerLine(3)),
      );
    });
  });

  group('rowColFor', () {
    test('offset 0 is always row 0, column 0', () {
      expect(rowColFor(0, 20), equals((0, 0)));
    });

    test('offsets within the first row stay on row 0', () {
      expect(rowColFor(1, 20), equals((0, 1)));
      expect(rowColFor(10, 20), equals((0, 10)));
      expect(rowColFor(19, 20), equals((0, 19)));
    });

    test('an offset exactly filling a row stays on that row (deferred wrap)',
        () {
      // Filling exactly 20 columns leaves the cursor at column 20 of row
      // 0, not at column 0 of row 1 — matches real terminal behavior,
      // which only wraps once another character is written.
      expect(rowColFor(20, 20), equals((0, 20)));
    });

    test('one past a full row starts row 1 at column 1', () {
      expect(rowColFor(21, 20), equals((1, 1)));
    });

    test('a multi-row offset lands on the correct row and column', () {
      expect(rowColFor(45, 20), equals((2, 5)));
    });

    test('non-positive width is treated as a degenerate single row', () {
      expect(rowColFor(5, 0), equals((0, 0)));
      expect(rowColFor(5, -1), equals((0, 0)));
    });
  });
}
