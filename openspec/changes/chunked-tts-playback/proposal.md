## Why

TTS currently speaks assistant responses verbatim, including markdown formatting characters (`#`, `**`, `` ` ``, etc.), which sounds broken. It also synthesizes and caches each message as a single audio blob, so long responses have a long silence before playback starts and offer no way to skip around within a response.

## What Changes

- Add a markdown-to-speech text normalizer applied to message text before synthesis: strips formatting markers, converts links to spoken text plus a "link" marker, drops code blocks/inline-code-as-code/tables/rules while reading inline code literally, and unwraps headers/emphasis/lists/blockquotes.
- Split normalized text into paragraph-based chunks (falling back to sentence-grouping for oversized paragraphs) instead of synthesizing the whole message as one block.
- Synthesize and play chunks progressively: the first chunk is generated and enqueued immediately, later chunks are generated one chunk ahead of playback via the existing playback queue, so audio starts well before the full response finishes synthesizing.
- Cache keys move from per-message to per-chunk (`messageId#chunkIndex`); LRU cache size increased to keep multiple long messages replayable.
- Message-level playback status (`generating`/`playing`/`completed`/etc.) now aggregates across a message's chunks instead of mapping 1:1 to a single synthesis call.
- Replace the single play/pause button with a back/play-pause/forward control once a message has playback focus (i.e. its audio is the one currently playing or paused):
  - **Back**: restarts the current chunk if more than ~3s into it; otherwise jumps to the previous chunk; no-ops at chunk 0 within the first ~3s.
  - **Forward**: ends the current chunk immediately, handing control to whatever the playback queue advances to next (the message's next chunk, or nothing if it was the last chunk).
  - Buttons are never disabled; edge cases are absorbed by the behavior above.
- Add four small primitives to `PlaybackService`: read current playback position, seek the current item to its start, skip the current item (stop and let the queue's normal advance-to-next logic take over), and remove not-yet-playing items matching a predicate (used to drop a stale prefetched chunk when a backward jump re-sequences upcoming playback).
- Keep the digit on numbered list items (e.g. `1. `) instead of stripping it, so the TTS engine speaks the number; bullet markers (`-`/`*`/`+`) are still stripped.
- Convert prose colons and parenthetical/bracketed asides into comma-bounded clauses, since commas are more reliably pause-inducing than colons/brackets across TTS engines (a text-level nudge — the pause length itself is whatever the model does with a comma, not otherwise controllable).
- Pace chunk-to-chunk playback with appended silence — real, exact, tunable silence, not a hope about model behavior: a short pause after a colon-triggered clause split, a base pause after a paragraph-ending chunk, a longer pause when the next paragraph is a markdown heading, and no extra pause between sentence-fallback sub-chunks of the same paragraph or after the message's last chunk. Implemented by appending zero-amplitude PCM samples to the chunk's WAV bytes (`appendSilenceToWav`), since the synthesis engine has no SSML-like pause markup. Colons additionally trigger their own chunk split so this real pause applies to them, not just paragraph/heading boundaries; brackets stay comma-only (chunk-splitting bracketed asides risked choppy, over-fragmented audio).
- Highlight the paragraph currently being spoken: each message is now rendered as one `GptMarkdown` widget per raw paragraph (instead of one widget for the whole message), and the paragraph matching the currently-playing/paused chunk's source paragraph gets a background tint while the message has playback focus (no border — padding/color stay constant between highlighted and non-highlighted states so nothing reflows).

## Capabilities

### New Capabilities
- `tts-markdown-normalization`: Converts raw markdown message text into speech-friendly plain text before TTS synthesis, per construct (headers, emphasis, links, code, tables, lists, blockquotes, images, bare URLs, numbered lists, prose punctuation pause cues).
- `tts-chunked-playback`: Splits long text into ordered chunks synthesized and played progressively with one-chunk-ahead prefetch, paces playback with inter-chunk silence, aggregates per-chunk playback state (including which source paragraph is active) to the message level, exposes back/forward chunk navigation controls, and highlights the active paragraph in the UI.

### Modified Capabilities
(none — no existing spec documents the pre-chunking TTS/playback behavior this change replaces)

## Impact

- **apps/lib/tts/text_normalizer.dart** (new) — `stripMarkdownForSpeech(String) → String`; numbered-list digit preservation; colon/bracket pause-cue insertion; exports `clausePauseMarker`, an invisible marker inserted after a prose colon so the chunker can split there.
- **apps/lib/tts/text_chunker.dart** (new) — `splitRawParagraphs(String) → List<String>` (shared with the UI) and `splitIntoSpeechChunks(String, {maxChunkLength}) → List<SpeechChunk>`, where `SpeechChunk` carries `text`, `sourceParagraphIndex`, and a `pauseAfter` hint (`none`/`clause`/`paragraph`/`heading`); splits paragraphs further on `clausePauseMarker` before the maxChunkLength sentence-fallback check.
- **apps/lib/tts/audio_source.dart** — new `appendSilenceToWav(Uint8List, Duration) → Uint8List`, patching the RIFF/data size header fields.
- **apps/lib/tts/services.dart** — cache keying changes to per-chunk; `cleanup()` updated to match by `messageId#` prefix.
- **apps/lib/providers/tts_provider.dart** — `playNow`/`enqueue` compute chunks and drive one-ahead prefetch; new `skipNextChunk`/`skipPreviousChunk` methods; `MessageTtsState` gains `currentChunkIndex`/`totalChunks`/`currentSourceParagraphIndex`; chunk-item-id → messageId + source-paragraph lookup for status aggregation; generated chunk audio gets silence appended per `SpeechChunk.pauseAfter`, scaled by `TtsService.speed`; `playNow` now clears the entire playback queue (not just the current item) before jumping in, fixing a leftover-prefetched-chunk-from-another-message bleed.
- **apps/lib/providers/playback_provider.dart** — new `currentPosition()`, `seekToStart()`, `skipCurrent()`, and `removeQueued()` methods on `PlaybackService`; also fixes a pre-existing bug where `_processNext` always re-requested the playback lock even when already holding it, causing `jumpQueue` to silently fail to interrupt already-active playback (see design.md's Implementation Findings).
- **apps/lib/widgets/tts_chunk_controls.dart** (new) — shared `TtsChunkControls`/`AnimatedTtsControls` widgets used by both chat surfaces.
- **apps/lib/pages/chat_page.dart**, **apps/lib/pages/agentic_chat_page.dart**, **apps/lib/chat/widgets.dart**, **apps/lib/agentic/widgets.dart** — swap single play/pause button for animated back/play-pause/forward control when a message has playback focus; `getMessagePlaybackStatus` callback renamed to `getMessageTtsState` (returns the full `MessageTtsState`, not just the status, so the UI can read `currentSourceParagraphIndex`); message body now renders one `GptMarkdown` per paragraph with the active one highlighted.
- No new pub dependencies.
