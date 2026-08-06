## ADDED Requirements

### Requirement: Markdown Stripping Before Synthesis
The system SHALL convert message text through a markdown-to-speech normalizer before it is passed to TTS synthesis, so formatting characters are never spoken literally.

#### Scenario: Normalization runs before synthesis
- **WHEN** a message is queued for TTS playback (via manual play or auto-playback)
- **THEN** the raw message text SHALL be passed through `stripMarkdownForSpeech` before any audio is generated
- **AND** the synthesizer SHALL only ever receive normalized text, never raw markdown

### Requirement: Header, Emphasis, and Blockquote Unwrapping
Headers, emphasis markers, strikethrough, and blockquote markers SHALL be removed while preserving the underlying text.

#### Scenario: Header markers stripped
- **WHEN** text contains a line starting with one or more `#` characters
- **THEN** the leading `#` characters and following space SHALL be removed
- **AND** the remaining header text SHALL be spoken as plain text

#### Scenario: Emphasis and strikethrough markers stripped
- **WHEN** text contains `**bold**`, `*italic*`, `__bold__`, `_italic_`, or `~~strikethrough~~` spans
- **THEN** the marker characters SHALL be removed
- **AND** the inner text SHALL be kept

#### Scenario: Blockquote marker stripped
- **WHEN** a line starts with `>` (optionally followed by more `>` for nesting)
- **THEN** the leading `>` characters SHALL be removed
- **AND** the remaining line text SHALL be kept

### Requirement: Link Handling
Markdown links and bare URLs SHALL be converted to spoken text that avoids reading the raw URL.

#### Scenario: Markdown link speaks text plus link marker
- **WHEN** text contains `[link text](url)`
- **THEN** the output SHALL contain the link text followed by an indication that it is a link (e.g. "link text, link")
- **AND** the URL SHALL NOT appear in the output

#### Scenario: Bare URL replaced with link marker
- **WHEN** text contains a bare URL (e.g. `https://example.com`) not wrapped in markdown link syntax
- **THEN** the URL SHALL be replaced with a short spoken indication that a link was present
- **AND** the raw URL characters SHALL NOT appear in the output

### Requirement: Code Handling
Fenced code blocks SHALL be omitted entirely; inline code SHALL be spoken as plain text.

#### Scenario: Fenced code block omitted
- **WHEN** text contains a fenced code block delimited by triple backticks
- **THEN** the entire block, including the fence markers, SHALL be removed from the output

#### Scenario: Inline code read literally
- **WHEN** text contains inline code delimited by single backticks (e.g. `` `variable_name` ``)
- **THEN** the backticks SHALL be removed
- **AND** the enclosed text SHALL be kept and spoken normally

### Requirement: Table and Rule Removal
Markdown tables and horizontal rules SHALL be removed entirely, as neither is intelligible when read aloud.

#### Scenario: Table dropped entirely
- **WHEN** text contains a GFM-style pipe table (a header row followed by a `|---|---|`-style separator row)
- **THEN** the entire table block SHALL be removed from the output

#### Scenario: Horizontal rule dropped
- **WHEN** text contains a horizontal rule line (e.g. `---`, `***`, `___` on its own line)
- **THEN** the rule line SHALL be removed from the output

### Requirement: List Marker Stripping
Bullet markers SHALL be removed; numbered markers SHALL keep their digit so the TTS engine speaks the number. Each item's text SHALL stay on its own line. Each list item SHALL also get a clause-boundary marker so the chunker (see the `tts-chunked-playback` capability's Inter-Chunk Pause Pacing requirement) can give it a real appended-silence pause, distinguishing it audibly from the next item.

#### Scenario: Bullet markers stripped
- **WHEN** text contains lines starting with `-`, `*`, or `+`
- **THEN** the marker and following space SHALL be removed
- **AND** each item's remaining text SHALL be kept on its own line

#### Scenario: Numbered markers keep their digit
- **WHEN** text contains a line starting with a numbered marker like `1. `
- **THEN** the digit and period SHALL be kept (spacing normalized to a single space after it)
- **AND** the item's remaining text SHALL be kept on its own line

#### Scenario: Each list item gets a clause-boundary marker
- **WHEN** a bullet or numbered list item's text is non-empty after its marker is stripped
- **THEN** an invisible clause-boundary marker SHALL be appended immediately after the item's text
- **AND** a colon at the end of that item's text SHALL still be recognized and converted to a comma despite the marker following it

### Requirement: Punctuation Pause Cues
Prose colons and parenthetical/bracketed asides SHALL be converted into comma-bounded clauses, since commas are more reliably pause-inducing than colons or bare brackets across TTS engines. Unlike list items (see the `tts-chunked-playback` capability's Inter-Chunk Pause Pacing requirement), colons and asides rely solely on the TTS model's own comma-pause behavior — a real appended-silence pause was tried for colons and dropped as too long/irritating on device.

#### Scenario: A prose colon becomes a comma
- **WHEN** text contains a colon followed by whitespace or end of text (e.g. `Options: A, B, or C.`)
- **THEN** the colon SHALL be replaced with a comma
- **AND** no clause-boundary marker SHALL be inserted — the comma relies on the TTS model's own pause behavior, not a real appended silence

#### Scenario: A colon with no following space is left alone
- **WHEN** text contains a colon immediately followed by a non-whitespace character (e.g. a time like `3:00`)
- **THEN** the colon SHALL NOT be modified

#### Scenario: A parenthetical or bracketed aside is comma-bounded
- **WHEN** text contains `(some aside)` or `[some aside]` that is not part of markdown link/image syntax
- **THEN** the enclosing parentheses/brackets SHALL be replaced with a leading and trailing comma
- **AND** resulting punctuation artifacts (a comma directly before a full stop, a doubled comma, a leading comma) SHALL be cleaned up

### Requirement: Image Handling
Images SHALL be converted to spoken alt text where available, or dropped entirely otherwise.

#### Scenario: Image with alt text speaks alt text
- **WHEN** text contains `![alt text](url)` with non-empty alt text
- **THEN** the output SHALL contain the alt text followed by an indication that it is an image (e.g. "alt text, image")
- **AND** the URL SHALL NOT appear in the output

#### Scenario: Image without alt text is dropped
- **WHEN** text contains `![](url)` with empty alt text
- **THEN** the entire image markup SHALL be removed from the output
