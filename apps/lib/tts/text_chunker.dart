import '/tts/text_normalizer.dart';

final _paragraphBreak = RegExp(r'\n\s*\n');
final _sentenceBoundary = RegExp(r'(?<=[.!?])\s+');
final _headingLine = RegExp(r'^#{1,6}\s+');
final _leadingComma = RegExp(r'^\s*,\s*');

/// How much silence, if any, should follow a chunk's audio. `clause` is the
/// short pause after a list item — real appended silence, unlike relying on
/// the TTS model's own (unadjustable, if any) pause after a line break.
enum ChunkPause { none, clause, paragraph, heading }

/// One unit of speech-ready text, with enough context to drive playback
/// pacing (audio pause after it) and UI highlighting (which paragraph of
/// the original message it came from).
class SpeechChunk {
  final String text;
  final int sourceParagraphIndex;
  final ChunkPause pauseAfter;

  const SpeechChunk({
    required this.text,
    required this.sourceParagraphIndex,
    required this.pauseAfter,
  });
}

/// Splits raw (markdown) text into paragraph blocks on blank-line
/// boundaries, trimmed and with empty blocks dropped. Shared by TTS
/// chunking and by message rendering, so a chunk's [SpeechChunk.
/// sourceParagraphIndex] always lines up with the same paragraph in the UI.
List<String> splitRawParagraphs(String text) {
  return text
      .split(_paragraphBreak)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

class _NormalizedParagraph {
  final int sourceIndex;
  final String text;
  final bool isHeading;

  const _NormalizedParagraph({
    required this.sourceIndex,
    required this.text,
    required this.isHeading,
  });
}

/// Splits already-normalized-per-paragraph speech text into ordered
/// chunks, using paragraphs as the primary boundary and falling back to
/// grouped sentences for any paragraph that exceeds [maxChunkLength] on
/// its own.
List<SpeechChunk> splitIntoSpeechChunks(
  String rawText, {
  int maxChunkLength = 400,
}) {
  final rawParagraphs = splitRawParagraphs(rawText);
  final normalized = <_NormalizedParagraph>[];
  for (var i = 0; i < rawParagraphs.length; i++) {
    final raw = rawParagraphs[i];
    final text = stripMarkdownForSpeech(raw);
    if (text.isEmpty) continue;
    normalized.add(
      _NormalizedParagraph(
        sourceIndex: i,
        text: text,
        isHeading: _headingLine.hasMatch(raw),
      ),
    );
  }

  final chunks = <SpeechChunk>[];
  for (var i = 0; i < normalized.length; i++) {
    final paragraph = normalized[i];
    final hasNext = i + 1 < normalized.length;
    // A heading gets the longer pause on both sides: after whatever
    // precedes it (handled here via nextIsHeading) and after itself
    // (paragraph.isHeading) — otherwise a heading only paused before it,
    // running straight into the body text that follows.
    final nextIsHeading = hasNext && normalized[i + 1].isHeading;
    final pauseAfterParagraph = !hasNext
        ? ChunkPause.none
        : (paragraph.isHeading || nextIsHeading
            ? ChunkPause.heading
            : ChunkPause.paragraph);

    final clauses = paragraph.text
        .split(clausePauseMarker)
        .map((c) => c.trim().replaceFirst(_leadingComma, ''))
        .where((c) => c.isNotEmpty)
        .toList();

    for (var c = 0; c < clauses.length; c++) {
      final isLastClause = c == clauses.length - 1;
      final tailPause = isLastClause ? pauseAfterParagraph : ChunkPause.clause;
      _emitTextChunks(
        chunks,
        clauses[c],
        paragraph.sourceIndex,
        tailPause,
        maxChunkLength,
      );
    }
  }
  return chunks;
}

/// Splits [text] at [maxChunkLength] if needed (sentence-fallback), adding
/// resulting chunk(s) to [chunks]. Only the last resulting chunk gets
/// [tailPause] — earlier ones get [ChunkPause.none].
void _emitTextChunks(
  List<SpeechChunk> chunks,
  String text,
  int sourceParagraphIndex,
  ChunkPause tailPause,
  int maxChunkLength,
) {
  if (text.length <= maxChunkLength) {
    chunks.add(
      SpeechChunk(
        text: text,
        sourceParagraphIndex: sourceParagraphIndex,
        pauseAfter: tailPause,
      ),
    );
    return;
  }

  final subTexts = _splitOversizedParagraph(text, maxChunkLength);
  for (var j = 0; j < subTexts.length; j++) {
    final isLastSub = j == subTexts.length - 1;
    chunks.add(
      SpeechChunk(
        text: subTexts[j],
        sourceParagraphIndex: sourceParagraphIndex,
        pauseAfter: isLastSub ? tailPause : ChunkPause.none,
      ),
    );
  }
}

List<String> _splitOversizedParagraph(String paragraph, int maxChunkLength) {
  final sentences = paragraph
      .split(_sentenceBoundary)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final chunks = <String>[];
  var current = StringBuffer();
  for (final sentence in sentences) {
    if (current.isEmpty) {
      current.write(sentence);
    } else if (current.length + 1 + sentence.length <= maxChunkLength) {
      current
        ..write(' ')
        ..write(sentence);
    } else {
      chunks.add(current.toString());
      current = StringBuffer()..write(sentence);
    }
  }
  if (current.isNotEmpty) chunks.add(current.toString());
  return chunks;
}
