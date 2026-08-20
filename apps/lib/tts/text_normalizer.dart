final _fencedCodeBlock = RegExp(r'```[\s\S]*?```');
final _tableSeparatorRow = RegExp(
  r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$',
);
final _horizontalRule = RegExp(
  r'^(?:-\s*){3,}$|^(?:\*\s*){3,}$|^(?:_\s*){3,}$',
);
final _headerLine = RegExp(r'^#{1,6}\s+');
final _blockquoteLine = RegExp(r'^(?:>\s?)+');
final _bulletLine = RegExp(r'^\s*[-*+]\s+');
// Numbered list markers keep their digit so the TTS engine speaks "one",
// "two", etc. — only the spacing after the marker is normalized.
final _numberedLine = RegExp(r'^\s*(\d+)\.\s+');
final _imagePattern = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final _linkPattern = RegExp(r'\[([^\]]*)\]\(([^)]*)\)');
final _bareUrlPattern = RegExp(r'https?://\S+');
final _inlineCodePattern = RegExp(r'`([^`\n]+)`');
final _boldStar = RegExp(r'\*\*(.+?)\*\*');
final _boldUnderscore = RegExp(r'__(.+?)__');
final _strikethrough = RegExp(r'~~(.+?)~~');
final _italicStar = RegExp(r'\*(.+?)\*');
// Flanking guard avoids treating snake_case_names as italic spans.
final _italicUnderscore = RegExp(r'(?<![\w])_([^_\n]+?)_(?![\w])');

/// Invisible marker inserted after each list item so the chunker can split
/// there and append a real, tunable silence between items — a plain newline
/// alone gets whatever (if any) pause the TTS model happens to give it,
/// which isn't adjustable. See `ChunkPause.clause` in text_chunker.dart.
const clausePauseMarker = '⁣';

// A colon followed by whitespace/end/the list-item marker (not e.g. "3:00")
// reads as a clause boundary — commas are the most reliably pause-inducing
// punctuation across TTS engines, more so than colons. The marker
// alternative covers a list item whose text ends in a colon: the marker
// already sits where "end of line" would otherwise be, right after it.
final _proseColon = RegExp(':(?=\\s|\$|$clausePauseMarker)');
final _parenthetical = RegExp(r'\(([^()]+)\)');
final _bracketed = RegExp(r'\[([^\[\]]+)\]');
final _doubleComma = RegExp(r',\s*,');
final _commaBeforeTerminal = RegExp(r',(?=[.!?])');
final _leadingComma = RegExp(r'^\s*,\s*');
final _spaceBeforeComma = RegExp(r'\s+,');

/// Converts raw markdown message text into speech-friendly plain text.
String stripMarkdownForSpeech(String input) {
  var text = input.replaceAll(_fencedCodeBlock, '');
  text = _stripTablesAndRules(text);
  text = _stripLineMarkers(text);
  text = text.replaceAllMapped(_imagePattern, (m) {
    final alt = m.group(1)!.trim();
    return alt.isEmpty ? '' : '$alt, image';
  });
  text = text.replaceAllMapped(_linkPattern, (m) {
    final label = m.group(1)!.trim();
    return label.isEmpty ? 'link' : '$label, link';
  });
  text = text.replaceAll(_bareUrlPattern, 'link');
  text = text.replaceAllMapped(_inlineCodePattern, (m) => m.group(1)!);
  text = _stripEmphasis(text);
  text = _insertPauseCues(text);
  return _collapseWhitespace(text);
}

String _stripTablesAndRules(String text) {
  final lines = text.split('\n');
  final result = <String>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final next = i + 1 < lines.length ? lines[i + 1] : null;
    if (next != null &&
        line.contains('|') &&
        _tableSeparatorRow.hasMatch(next)) {
      i += 2;
      while (i < lines.length &&
          lines[i].contains('|') &&
          lines[i].trim().isNotEmpty) {
        i++;
      }
      continue;
    }
    if (_horizontalRule.hasMatch(line.trim())) {
      i++;
      continue;
    }
    result.add(line);
    i++;
  }
  return result.join('\n');
}

/// Strips header/blockquote/list markers. List items (bullet or numbered)
/// also get [clausePauseMarker] appended so the chunker gives each item its
/// own short trailing pause instead of running straight into the next one.
String _stripLineMarkers(String text) {
  final lines = text.split('\n').map((line) {
    var l = line.replaceFirst(_headerLine, '');
    l = l.replaceFirst(_blockquoteLine, '');
    final isBullet = _bulletLine.hasMatch(l);
    l = l.replaceFirst(_bulletLine, '');
    final isNumbered = _numberedLine.hasMatch(l);
    l = l.replaceFirstMapped(_numberedLine, (m) => '${m.group(1)}. ');
    if ((isBullet || isNumbered) && l.trim().isNotEmpty) {
      l = '$l$clausePauseMarker';
    }
    return l;
  });
  return lines.join('\n');
}

String _stripEmphasis(String text) {
  var t = text;
  t = t.replaceAllMapped(_boldStar, (m) => m.group(1)!);
  t = t.replaceAllMapped(_boldUnderscore, (m) => m.group(1)!);
  t = t.replaceAllMapped(_strikethrough, (m) => m.group(1)!);
  t = t.replaceAllMapped(_italicStar, (m) => m.group(1)!);
  t = t.replaceAllMapped(_italicUnderscore, (m) => m.group(1)!);
  return t;
}

/// Converts prose colons and parenthetical/bracketed asides into
/// comma-bounded clauses so the TTS engine pauses around them (commas are
/// the most reliably pause-inducing punctuation across TTS engines), then
/// cleans up the resulting punctuation artifacts (double commas, a comma
/// right before a full stop, a leading comma). A real appended-silence pause
/// (as list items get via [clausePauseMarker]) was tried for colons too but
/// dropped — it read as too long/irritating on device.
String _insertPauseCues(String text) {
  var t = text.replaceAll(_proseColon, ',');
  t = t.replaceAllMapped(_parenthetical, (m) => ', ${m.group(1)!.trim()},');
  t = t.replaceAllMapped(_bracketed, (m) => ', ${m.group(1)!.trim()},');
  t = t.replaceAll(_spaceBeforeComma, ',');
  t = t.replaceAll(_doubleComma, ',');
  t = t.replaceAll(_commaBeforeTerminal, '');
  t = t
      .split('\n')
      .map((line) => line.replaceFirst(_leadingComma, ''))
      .join('\n');
  return t;
}

String _collapseWhitespace(String text) {
  final lines = text.split('\n').map((l) => l.trimRight()).toList();
  final collapsed = <String>[];
  var blankRun = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) {
      blankRun++;
      if (blankRun <= 1) collapsed.add('');
    } else {
      blankRun = 0;
      collapsed.add(line);
    }
  }
  while (collapsed.isNotEmpty && collapsed.first.isEmpty) {
    collapsed.removeAt(0);
  }
  while (collapsed.isNotEmpty && collapsed.last.isEmpty) {
    collapsed.removeLast();
  }
  return collapsed.join('\n');
}
