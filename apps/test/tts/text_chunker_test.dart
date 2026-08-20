import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/tts/text_chunker.dart';
import 'package:relagent/tts/text_normalizer.dart' show clausePauseMarker;

void main() {
  group('splitRawParagraphs', () {
    test('splits on blank lines and trims/drops empties', () {
      expect(splitRawParagraphs('Para one.\n\nPara two.\n\n\nPara three.'), [
        'Para one.',
        'Para two.',
        'Para three.',
      ]);
    });

    test('a single block with no blank line stays one paragraph', () {
      expect(splitRawParagraphs('- one\n- two\n- three'), [
        '- one\n- two\n- three',
      ]);
    });
  });

  group('splitIntoSpeechChunks', () {
    test('a short message with no paragraph breaks yields a single chunk', () {
      final chunks = splitIntoSpeechChunks('Hello world.');
      expect(chunks, hasLength(1));
      expect(chunks[0].text, 'Hello world.');
      expect(chunks[0].sourceParagraphIndex, 0);
      expect(chunks[0].pauseAfter, ChunkPause.none);
    });

    test('multiple paragraphs become one chunk each, paced with pauses', () {
      final chunks = splitIntoSpeechChunks(
        'Para one.\n\nPara two.\n\nPara three.',
      );
      expect(chunks.map((c) => c.text), [
        'Para one.',
        'Para two.',
        'Para three.',
      ]);
      expect(chunks.map((c) => c.sourceParagraphIndex), [0, 1, 2]);
      expect(chunks.map((c) => c.pauseAfter), [
        ChunkPause.paragraph,
        ChunkPause.paragraph,
        ChunkPause.none,
      ]);
    });

    test('a heading gets the longer pause on both sides (before it, and '
        'after it before the following body text)', () {
      final chunks = splitIntoSpeechChunks('Intro.\n\n# Heading\n\nBody.');
      expect(chunks.map((c) => c.text), ['Intro.', 'Heading', 'Body.']);
      expect(chunks.map((c) => c.pauseAfter), [
        ChunkPause.heading,
        ChunkPause.heading,
        ChunkPause.none,
      ]);
    });

    test(
      'an oversized paragraph falls back to grouped sentences, sharing '
      'the source paragraph index and deferring the pause to the last sub-chunk',
      () {
        final chunks = splitIntoSpeechChunks(
          'One two three. Four five six. Seven eight nine.\n\nNext.',
          maxChunkLength: 30,
        );
        expect(chunks.map((c) => c.text), [
          'One two three. Four five six.',
          'Seven eight nine.',
          'Next.',
        ]);
        expect(chunks.map((c) => c.sourceParagraphIndex), [0, 0, 1]);
        expect(chunks.map((c) => c.pauseAfter), [
          ChunkPause.none,
          ChunkPause.paragraph,
          ChunkPause.none,
        ]);
      },
    );

    test('a paragraph that normalizes to nothing is dropped, preserving '
        'the source index of the paragraph that follows it', () {
      final chunks = splitIntoSpeechChunks(
        'Before.\n\n```\ncode only\n```\n\nAfter.',
      );
      expect(chunks.map((c) => c.text), ['Before.', 'After.']);
      expect(chunks.map((c) => c.sourceParagraphIndex), [0, 2]);
    });

    test('markdown formatting is normalized within each chunk', () {
      final chunks = splitIntoSpeechChunks('**Bold** paragraph.');
      expect(chunks[0].text, 'Bold paragraph.');
    });

    test('a prose colon stays a single chunk (colons are comma-only, no '
        'appended-silence pause)', () {
      final chunks = splitIntoSpeechChunks(
        'Options: A, B, or C. Next sentence.',
      );
      expect(chunks.map((c) => c.text), [
        'Options, A, B, or C. Next sentence.',
      ]);
      expect(chunks[0].pauseAfter, ChunkPause.none);
    });

    test('splits on an explicit clausePauseMarker if one is present', () {
      // Exercises the chunker's own clause-splitting mechanism directly,
      // independent of what in the normalizer produces the marker (list
      // items, currently).
      final chunks = splitIntoSpeechChunks(
        'Options,$clausePauseMarker A, B, or C. Next sentence.',
      );
      expect(chunks.map((c) => c.text), [
        'Options,',
        'A, B, or C. Next sentence.',
      ]);
      expect(chunks.map((c) => c.sourceParagraphIndex), [0, 0]);
      expect(chunks.map((c) => c.pauseAfter), [
        ChunkPause.clause,
        ChunkPause.none,
      ]);
    });

    test('list items each get a clause pause, and the last item gets the '
        'paragraph pause instead', () {
      final chunks = splitIntoSpeechChunks('- one\n- two\n- three\n\nAfter.');
      expect(chunks.map((c) => c.text), ['one', 'two', 'three', 'After.']);
      expect(chunks.map((c) => c.sourceParagraphIndex), [0, 0, 0, 1]);
      expect(chunks.map((c) => c.pauseAfter), [
        ChunkPause.clause,
        ChunkPause.clause,
        ChunkPause.paragraph,
        ChunkPause.none,
      ]);
    });

    test('numbered list items also get a clause pause between them', () {
      final chunks = splitIntoSpeechChunks('1. first\n2. second');
      expect(chunks.map((c) => c.text), ['1. first', '2. second']);
      expect(chunks.map((c) => c.pauseAfter), [
        ChunkPause.clause,
        ChunkPause.none,
      ]);
    });

    test('a trailing colon at the end of a paragraph does not produce an '
        'empty trailing chunk', () {
      final chunks = splitIntoSpeechChunks('Heads up:');
      expect(chunks.map((c) => c.text), ['Heads up,']);
    });

    test('empty or whitespace-only input yields no chunks', () {
      expect(splitIntoSpeechChunks(''), isEmpty);
      expect(splitIntoSpeechChunks('   \n\n  '), isEmpty);
    });
  });
}
