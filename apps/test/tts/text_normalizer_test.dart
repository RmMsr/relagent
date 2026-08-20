import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/tts/text_normalizer.dart';

const _m = clausePauseMarker;

void main() {
  group('stripMarkdownForSpeech', () {
    test('strips header markers', () {
      expect(stripMarkdownForSpeech('# Title'), 'Title');
      expect(stripMarkdownForSpeech('## Subtitle'), 'Subtitle');
    });

    test('strips bold/italic/strikethrough markers', () {
      expect(stripMarkdownForSpeech('**bold**'), 'bold');
      expect(stripMarkdownForSpeech('__bold__'), 'bold');
      expect(
        stripMarkdownForSpeech('This is _really_ important.'),
        'This is really important.',
      );
      expect(stripMarkdownForSpeech('*italic*'), 'italic');
      expect(stripMarkdownForSpeech('~~gone~~'), 'gone');
    });

    test('does not mangle snake_case identifiers', () {
      expect(
        stripMarkdownForSpeech('Use my_variable_name in the config.'),
        'Use my_variable_name in the config.',
      );
    });

    test('strips blockquote markers', () {
      expect(stripMarkdownForSpeech('> Quoted line'), 'Quoted line');
      expect(stripMarkdownForSpeech('>> Nested quote'), 'Nested quote');
    });

    test('strips bullet markers, keeping items on their own line, each '
        'tagged with a clause pause marker', () {
      expect(stripMarkdownForSpeech('- one\n- two'), 'one$_m\ntwo$_m');
    });

    test('keeps the number on numbered list items, each tagged with a '
        'clause pause marker', () {
      expect(
        stripMarkdownForSpeech('1. first\n2. second'),
        '1. first$_m\n2. second$_m',
      );
      expect(
        stripMarkdownForSpeech(
          '1. If you want ONE heading for the whole section:',
        ),
        '1. If you want ONE heading for the whole section,$_m',
      );
    });

    test('converts markdown links to text plus a link marker', () {
      expect(
        stripMarkdownForSpeech('[click here](https://example.com)'),
        'click here, link',
      );
    });

    test('replaces bare URLs with a link marker', () {
      expect(
        stripMarkdownForSpeech('Visit https://example.com now'),
        'Visit link now',
      );
    });

    test('speaks image alt text with an image marker', () {
      expect(
        stripMarkdownForSpeech('![a cute cat](https://example.com/cat.png)'),
        'a cute cat, image',
      );
    });

    test('drops images with empty alt text entirely', () {
      expect(
        stripMarkdownForSpeech('![](https://example.com/cat.png)'),
        isEmpty,
      );
    });

    test('drops fenced code blocks entirely', () {
      expect(
        stripMarkdownForSpeech('before\n```\ncode here\n```\nafter'),
        'before\n\nafter',
      );
    });

    test('reads inline code literally', () {
      expect(
        stripMarkdownForSpeech('Run `git status` now'),
        'Run git status now',
      );
    });

    test('drops tables entirely', () {
      final result = stripMarkdownForSpeech(
        'Name | Age\n---|---\nAlice | 30\n\nAfter table',
      );
      expect(result, 'After table');
      expect(result.contains('Alice'), isFalse);
      expect(result.contains('|'), isFalse);
    });

    test('drops horizontal rules entirely', () {
      expect(stripMarkdownForSpeech('Above\n\n---\n\nBelow'), 'Above\n\nBelow');
    });

    test('converts a prose colon into a pause-inducing comma', () {
      expect(
        stripMarkdownForSpeech('Options: A, B, or C.'),
        'Options, A, B, or C.',
      );
    });

    test('does not touch a colon with no following space (e.g. a time)', () {
      expect(
        stripMarkdownForSpeech('It starts at 3:00 sharp.'),
        'It starts at 3:00 sharp.',
      );
    });

    test('wraps a parenthetical aside in pause-inducing commas', () {
      expect(
        stripMarkdownForSpeech('This works (usually pretty well).'),
        'This works, usually pretty well.',
      );
    });

    test('wraps a bracketed aside in pause-inducing commas', () {
      expect(
        stripMarkdownForSpeech('See [important] note.'),
        'See, important, note.',
      );
    });

    test('handles a combination of constructs in one message', () {
      final result = stripMarkdownForSpeech(
        '# Title\n\nThis is **bold** and [a link](https://x.com) and `code`.',
      );
      expect(result, 'Title\n\nThis is bold and a link, link and code.');
    });
  });
}
