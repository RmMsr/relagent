## ADDED Requirements

### Requirement: Text Chunking
Normalized message text SHALL be split into an ordered list of chunks before synthesis, using paragraph breaks as the primary boundary and sentence grouping as a fallback for oversized paragraphs.

#### Scenario: Paragraphs become chunks
- **WHEN** normalized text contains multiple paragraphs separated by blank lines
- **THEN** each paragraph SHALL become its own chunk, in original order

#### Scenario: Oversized paragraph falls back to sentence grouping
- **WHEN** a single paragraph exceeds the configured maximum chunk length
- **THEN** the paragraph SHALL be further split at sentence boundaries
- **AND** consecutive sentences SHALL be grouped into chunks up to the maximum chunk length

#### Scenario: Short message yields a single chunk
- **WHEN** normalized text is shorter than the maximum chunk length and contains no paragraph breaks
- **THEN** it SHALL be returned as a single chunk

### Requirement: Progressive Chunk Synthesis and Playback
Chunks SHALL be synthesized and enqueued for playback progressively, with at most one chunk's synthesis running ahead of the chunk currently playing.

#### Scenario: Playback starts before full message is synthesized
- **WHEN** a multi-chunk message is queued for playback
- **THEN** playback of the first chunk SHALL begin as soon as that chunk's audio is ready
- **AND** playback SHALL NOT wait for later chunks to finish synthesizing

#### Scenario: Next chunk synthesis begins when current chunk starts playing
- **WHEN** a chunk begins playing
- **THEN** synthesis of the next chunk (if any) SHALL begin at that point
- **AND** synthesis of chunks beyond the next one SHALL NOT begin until their turn arrives

### Requirement: Inter-Chunk Pause Pacing
Chunk audio SHALL be paced with an appropriate silence after it, so clause, paragraph, and heading boundaries are audibly distinct. Pauses SHALL be real appended silence, not solely inferred from the synthesis engine's handling of punctuation.

#### Scenario: A pause follows a paragraph-ending chunk
- **WHEN** a chunk is the last chunk derived from its source paragraph and another paragraph follows
- **THEN** a base pause duration SHALL be appended to that chunk's audio

#### Scenario: A longer pause precedes a heading
- **WHEN** a chunk is the last chunk derived from its source paragraph and the next paragraph is a markdown heading
- **THEN** a longer pause duration SHALL be appended to that chunk's audio instead of the base pause

#### Scenario: A longer pause also follows a heading
- **WHEN** a chunk is the last chunk derived from a paragraph that is itself a markdown heading
- **THEN** the longer heading pause duration SHALL be appended to that chunk's audio, regardless of whether the following paragraph is also a heading

#### Scenario: A short pause follows each list item but the last
- **WHEN** a paragraph is a bullet or numbered list and is split into one chunk per item
- **THEN** a short pause duration, shorter than the paragraph pause, SHALL be appended to every item's chunk audio except the last
- **AND** the last item's chunk SHALL instead receive whatever pause tier follows the list as a whole (clause, paragraph, heading, or none)

#### Scenario: No extra pause within a sentence-split paragraph or clause
- **WHEN** a paragraph or a clause within it was split into multiple chunks because it exceeded the maximum chunk length
- **THEN** only the last of those chunks SHALL receive the pause appropriate to what follows it (clause, paragraph, or heading)
- **AND** earlier chunks from the same split SHALL receive no extra pause

#### Scenario: No trailing pause after the last chunk
- **WHEN** a chunk is the last chunk of the entire message
- **THEN** no extra pause SHALL be appended to its audio

#### Scenario: Pause duration scales with playback speed
- **WHEN** the TTS playback speed setting is other than 1.0x
- **THEN** each appended pause duration SHALL be scaled inversely with speed (e.g. halved at 2.0x, doubled at 0.5x) so pauses stay proportionate to the sped-up or slowed-down speech around them

### Requirement: Per-Chunk Caching
Generated chunk audio SHALL be cached independently per chunk, keyed by message identity and chunk position.

#### Scenario: Chunk audio is cached
- **WHEN** a chunk's audio has been generated
- **THEN** it SHALL be cached under a key derived from the message id and chunk index

#### Scenario: Replaying a message reuses cached audio
- **WHEN** a previously played chunk is requested again (e.g. via replay or chunk navigation) and is still in cache
- **THEN** the cached audio SHALL be returned without re-invoking synthesis

### Requirement: Message-Level Status Aggregation
Per-message playback status SHALL be derived from the status of its constituent chunks, not from a single synthesis call.

#### Scenario: Message is generating until first chunk is ready
- **WHEN** a message's chunks are being computed and its first chunk's audio is not yet ready
- **THEN** the message's playback status SHALL be `generating`

#### Scenario: Message is playing while any of its chunks are playing
- **WHEN** any chunk belonging to a message is the currently playing audio
- **THEN** the message's playback status SHALL be `playing`

#### Scenario: Message completes only after its last chunk finishes
- **WHEN** a message has multiple chunks
- **THEN** the message's playback status SHALL become `completed` only when its last chunk finishes playing
- **AND** intermediate chunks finishing SHALL NOT mark the message as completed

#### Scenario: A failed chunk is skipped, not fatal
- **WHEN** synthesis fails for one chunk of a message
- **THEN** that chunk SHALL be skipped
- **AND** playback SHALL continue with the message's remaining chunks

### Requirement: Chunk Navigation Controls
A message with playback focus SHALL expose back and forward controls that operate on its paragraphs, not on raw synthesis chunks — a short list's items count as one paragraph-sized unit for navigation, even though each item is its own synthesis chunk (see the Inter-Chunk Pause Pacing requirement). A paragraph is only ever split into multiple navigable steps when a piece of it ran long enough to require sentence-fallback splitting; a short list's items never are, regardless of how many there are.

#### Scenario: Back within first few seconds jumps to the previous paragraph
- **WHEN** the back control is activated no more than approximately 3 seconds into the current paragraph
- **AND** the current paragraph is not the message's first paragraph
- **THEN** playback SHALL jump to the start of the previous paragraph — its first item, if that paragraph is itself a list

#### Scenario: Back after first few seconds restarts the current paragraph
- **WHEN** the back control is activated more than approximately 3 seconds into the current paragraph
- **THEN** playback SHALL restart the current paragraph from its beginning — its first item, if it is a list, even if a later item is currently playing

#### Scenario: Back on the first paragraph near its start is a no-op
- **WHEN** the back control is activated no more than approximately 3 seconds into the message's first paragraph
- **THEN** playback SHALL continue unaffected

#### Scenario: Forward ends the current paragraph and advances
- **WHEN** the forward control is activated
- **THEN** the current paragraph SHALL end immediately — all of its remaining items at once, if it is a list — not just the currently-playing chunk
- **AND** playback SHALL advance to whatever the playback queue determines comes next

#### Scenario: Forward on the last paragraph ends message playback
- **WHEN** the forward control is activated during a message's last paragraph
- **THEN** the message's playback SHALL end
- **AND** control SHALL pass to the playback queue's normal advancement (next queued item, or idle if none)

#### Scenario: A list containing a long item is not collapsed for navigation
- **WHEN** a list paragraph contains at least one item whose text required sentence-fallback splitting into multiple chunks
- **THEN** back/forward SHALL navigate that paragraph one raw chunk at a time, the same as before this requirement's list-aware behavior existed, rather than treating the whole list as one unit

#### Scenario: Navigation controls are never disabled
- **WHEN** back or forward is activated in any paragraph position, including boundary cases
- **THEN** the control SHALL remain enabled and produce the behavior defined above rather than being visually disabled

### Requirement: Playback Focus Gating
Chunk navigation SHALL only be available for, and only ever act on, the message that currently owns the playing or paused audio.

#### Scenario: Navigation controls shown only for the focused message
- **WHEN** a message's status is `playing` or `paused`
- **THEN** that message SHALL display back/play-pause/forward controls in place of a single play button

#### Scenario: Skip actions ignored for a non-focused message
- **WHEN** a skip action is requested for a message that does not currently own the playing or paused audio
- **THEN** the action SHALL have no effect

#### Scenario: An interrupted message loses playback focus immediately
- **GIVEN** a message is playing or paused (has playback focus) when a different message is played immediately, interrupting it before its last chunk
- **WHEN** the interruption happens
- **THEN** the interrupted message's status SHALL become `idle`
- **AND** it SHALL stop displaying back/play-pause/forward controls in favor of a single play button

### Requirement: Interrupting Playback Replaces the Entire Queue
Playing a message immediately (interrupting whatever is currently playing) SHALL discard everything else queued, not just take over the currently-playing slot — including any not-yet-played chunk left over from a different message (e.g. one still mid-playback in another chat session).

#### Scenario: Playing a new message clears a leftover prefetched chunk from another message
- **GIVEN** a message is playing and its next chunk has already been prefetched into the queue (one-chunk-ahead prefetch)
- **WHEN** a different message is played immediately
- **THEN** the new message's first chunk SHALL play
- **AND** the previously-prefetched chunk from the other message SHALL NOT play afterward

#### Scenario: No stale chunks remain queued after the interruption
- **WHEN** playing a message immediately interrupts existing playback
- **THEN** the playback queue SHALL contain only the new message's chunks after the interruption completes

#### Scenario: The interrupted message's own chunk does not play again afterward
- **GIVEN** a message is actively playing (its chunk is the current, not merely queued, item) when a different message is played immediately
- **WHEN** the new message's first chunk finishes
- **THEN** playback SHALL NOT resume or replay the interrupted message's chunk
- **AND** playback SHALL advance to whatever the queue determines comes next (another queued item, or idle if none)

### Requirement: Active Paragraph Highlighting
While a message has playback focus, the paragraph the currently-playing/paused chunk was derived from SHALL be visually distinguished from the rest of the message.

#### Scenario: The active paragraph is highlighted
- **WHEN** a message's status is `playing` or `paused`
- **THEN** the paragraph corresponding to the currently-playing/paused chunk's source paragraph SHALL be rendered with a distinguishing background
- **AND** no other paragraph of that message SHALL be highlighted

#### Scenario: Highlighting does not shift surrounding content
- **WHEN** the highlighted paragraph changes (becomes highlighted or stops being highlighted)
- **THEN** the paragraph's padding/size SHALL remain constant so neighboring paragraphs do not move

#### Scenario: No paragraph is highlighted outside playback focus
- **WHEN** a message's status is `idle`, `generating`, `completed`, or `error`
- **THEN** none of its paragraphs SHALL be highlighted

#### Scenario: Highlighting tracks chunk navigation
- **WHEN** the currently-playing/paused chunk changes (via natural progression, skip forward, or skip back)
- **THEN** the highlighted paragraph SHALL update to match the new chunk's source paragraph
