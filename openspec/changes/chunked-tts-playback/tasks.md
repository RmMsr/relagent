## 1. Text normalization

- [x] 1.1 Create `apps/lib/tts/text_normalizer.dart` with `String stripMarkdownForSpeech(String input)`
- [x] 1.2 Implement fenced code block removal (entire block including fences)
- [x] 1.3 Implement inline code handling (strip backticks, keep text)
- [x] 1.4 Implement link handling (`[text](url)` → text + link marker; bare URLs → link marker)
- [x] 1.5 Implement image handling (alt text + image marker, or drop if alt is empty)
- [x] 1.6 Implement header/emphasis/strikethrough/blockquote unwrapping
- [x] 1.7 Implement list marker stripping (bullets and numbered lists)
- [x] 1.8 Implement table detection and removal (GFM pipe tables)
- [x] 1.9 Implement horizontal rule removal
- [x] 1.10 Write unit tests for each construct in `apps/test/tts/text_normalizer_test.dart`, including mixed/combined-construct cases

## 2. Text chunking

- [x] 2.1 Create `apps/lib/tts/text_chunker.dart` with `List<String> splitIntoSpeechChunks(String text, {int maxChunkLength = 400})`
- [x] 2.2 Implement paragraph splitting on blank lines
- [x] 2.3 Implement sentence-boundary fallback splitting for paragraphs exceeding `maxChunkLength`, grouping consecutive sentences up to the limit
- [x] 2.4 Drop empty chunks (e.g. paragraphs that became empty after normalization removed a code block/table)
- [x] 2.5 Write unit tests in `apps/test/tts/text_chunker_test.dart`: single short message, multiple paragraphs, one oversized paragraph, mixed short+oversized paragraphs, all-empty-after-normalization input

## 3. PlaybackService primitives

- [x] 3.1 Add a synchronous current-position read to `PlaybackService` (pass-through to `AudioPlayer.position`)
- [x] 3.2 Add `seekToStart()` (or generic `seek(Duration)`) to `PlaybackService`
- [x] 3.3 Add `skipCurrent()` to `PlaybackService`: stop the player and invoke the existing finish-and-advance path so the queue proceeds to whatever's next (or goes idle)
- [x] 3.4 Add/extend `apps/test/providers/playback_provider_test.dart` coverage for the three new methods, including `skipCurrent()` with an empty queue afterward (goes idle) and with another item queued (advances)
- [x] 3.5 (found during implementation) Add `removeQueued(predicate)` to `PlaybackService` to drop stale not-yet-playing items before a backward chunk jump, plus test coverage

## 4. Per-chunk caching in TtsService

- [x] 4.1 Confirm `TtsService.generate(text, cacheKey)` needs no signature change; verify callers will pass `'$messageId#$chunkIndex'` as the cache key
- [x] 4.2 Increase `_maxCacheItems` from 20 to 60
- [x] 4.3 Update `TtsService.cleanup(Set<String> messageIds)` to remove all cache entries whose key starts with `'$id#'` for each id in the set

## 5. TtsNotifier orchestration

- [x] 5.1 Add `currentChunkIndex` and `totalChunks` fields to `MessageTtsState` (default `0` / `1`)
- [x] 5.2 Add internal per-message chunk bookkeeping to `TtsNotifier` (chunk text list, cache keys, next-chunk-to-prefetch cursor)
- [x] 5.3 Add a chunk-item-id → messageId lookup map, populated when a chunk's `PlaybackItem` is created
- [x] 5.4 Update `playNow` to compute chunks via normalizer + chunker, `jumpQueue` the first chunk, and kick off one-ahead prefetch bookkeeping
- [x] 5.5 Update `enqueue` the same way, using `playbackProvider.enqueue` for the first chunk instead of `jumpQueue`
- [x] 5.6 Update `_handlePlaybackStateChange` to resolve chunk item ids back to messageId via the lookup map, update `currentChunkIndex`, and trigger enqueueing the next chunk (one-ahead) when a chunk starts playing
- [x] 5.7 Ensure message status becomes `completed` only when the last chunk in the message's chunk list finishes (including when the last chunk's generation itself fails, via a dedicated error listener since a failed chunk never becomes the queue's current item)
- [x] 5.8 Handle per-chunk generation failure: skip the failed chunk, log it, continue with the next chunk instead of failing the whole message
- [x] 5.9 Add `skipNextChunk(messageId)`: guarded on the message currently having playback focus, calls `playbackProvider.notifier.skipCurrent()`
- [x] 5.10 Add `skipPreviousChunk(messageId)`: guarded on playback focus; reads current position; if >3s, calls `seekToStart()`; if ≤3s and `currentChunkIndex > 0`, calls `removeQueued` to drop this message's stale prefetched chunk, then builds/reuses the cached previous chunk and `jumpQueue`s it; if ≤3s and `currentChunkIndex == 0`, no-ops
- [x] 5.11 (found during implementation) Fix pre-existing `PlaybackService._processNext()` bug: it always re-requested the playback lock even when already holding it, so `jumpQueue` silently failed to interrupt already-active playback (affects `playNow` too, not just `skipPreviousChunk`)
- [x] 5.12 (found during implementation) Gate `_handlePlaybackStateChange`'s playing/paused handling on an actual transition (item or status changed), not just "is currently playing" — otherwise a queue-only mutation (e.g. `removeQueued` during a backward jump) spuriously re-triggers prefetch
- [x] 5.13 Add `apps/test/providers/tts_provider_test.dart` covering chunk count, one-ahead prefetch, completion-only-on-last-chunk (including a failed final chunk), and the backward-jump stale-prefetch regression; extend `AudioTestFixture` with an optional fake `VoiceService` override to support this

## 6. UI: chunk navigation controls

- [x] 6.1 Locate the existing play/pause button widget(s) in `apps/lib/pages/chat_page.dart` and `apps/lib/pages/agentic_chat_page.dart`
- [x] 6.2 Add a back/play-pause/forward control widget, shown when `MessageTtsState.status` is `playing` or `paused` for that message; single play button otherwise
- [x] 6.3 Wire back/forward buttons to `TtsNotifier.skipPreviousChunk`/`skipNextChunk`
- [x] 6.4 Animate the transition between the single-button and three-button layouts (`AnimatedSize` or equivalent)
- [ ] 6.5 Manually verify in the running app: short single-chunk message (buttons still work sensibly), long multi-chunk message (playback starts before full synthesis, back/forward navigate as specified), auto-playback queue with multiple messages (navigation only affects the focused message). Partial substitute added instead: `apps/test/chat/message_bubble_test.dart` widget-level coverage (idle → single button; playing/paused → back/pause-or-resume/forward row; tapping back/forward invokes the right callback). Does not cover actual audio, real chunking timing, or the auto-playback queue interaction — TTS is unavailable on the web target this environment can drive, and there's no way here to perceive audio playback. Needs a native build with a real voice model from the user.

## 7. Full-suite verification

- [x] 7.1 Run `fvm flutter test` for the full `apps/test` suite — 361/361 passing
- [x] 7.2 Run `fvm flutter analyze` and resolve any new warnings — 73 pre-existing issues, all in files untouched by this change; zero new issues

## 8. Refinement round (user testing feedback)

User confirmed the base implementation works in the running app, then requested: visual highlighting of the currently-speaking chunk, pauses between paragraphs (longer before headings), short pauses after colons/brackets, and preserving the digit on numbered list items.

- [x] 8.1 Restructure `text_chunker.dart`: `splitRawParagraphs(String) → List<String>` (shared with UI rendering); `splitIntoSpeechChunks` now normalizes per-paragraph (not the whole message at once) and returns `List<SpeechChunk>` carrying `text`, `sourceParagraphIndex`, and a `pauseAfter` hint (`none`/`clause`/`paragraph`/`heading`) based on whether the next paragraph is a markdown heading
- [x] 8.2 `text_normalizer.dart`: numbered list markers keep their digit (bullets still stripped); prose colons and parenthetical/bracketed asides become comma-bounded clauses, with cleanup for resulting punctuation artifacts
- [x] 8.3 `audio_source.dart`: add `appendSilenceToWav(Uint8List, Duration)`, patching RIFF/data size header fields to append zero-amplitude PCM silence
- [x] 8.4 `tts_provider.dart`: `_ChunkedMessage`/`_ChunkItemInfo` carry `SpeechChunk`/`sourceParagraphIndex`; `_buildChunkItem` appends pause-appropriate silence to generated audio; `MessageTtsState` gains `currentSourceParagraphIndex`
- [x] 8.5 Rename `getMessagePlaybackStatus: MessagePlaybackStatus Function(String)?` to `getMessageTtsState: MessageTtsState Function(String)?` across `chat_page.dart`, `agentic_chat_page.dart`, `chat/widgets.dart`, `agentic/widgets.dart` so the UI can read `currentSourceParagraphIndex`
- [x] 8.6 Render each message as one `GptMarkdown` per raw paragraph (via `splitRawParagraphs`) instead of one for the whole message; highlight the paragraph matching `currentSourceParagraphIndex` with a background tint while the message has playback focus
- [x] 8.7 Rewrite `text_chunker_test.dart` for the new `SpeechChunk`-returning API (pause hints, source paragraph indices, dropped-paragraph index preservation); add `audio_source_test.dart` for `appendSilenceToWav`; extend `text_normalizer_test.dart` for numbered lists and pause cues; add highlight-specific widget tests to `message_bubble_test.dart`
- [x] 8.8 Full suite: 376/376 passing, `flutter analyze` clean (same 73 pre-existing issues, zero new)

## 9. Second refinement round (further user testing feedback)

- [x] 9.1 Remove the left border from paragraph highlighting and make padding constant between highlighted/non-highlighted states (only the background color toggles) — the border + conditional padding were shifting surrounding content on every highlight change
- [x] 9.2 Give colons a real, tunable pause instead of relying on the model's comma-pause behavior: `text_normalizer.dart` inserts an invisible `clausePauseMarker` (U+2063, exported) right after a colon's comma; `text_chunker.dart` splits a paragraph on that marker (in addition to maxChunkLength/sentence-fallback splitting) so the leading clause becomes its own chunk with `ChunkPause.clause` (200ms, via the existing `appendSilenceToWav` mechanism); brackets deliberately excluded to avoid fragmenting short asides into three chunks
- [x] 9.3 Update `text_normalizer_test.dart`/`text_chunker_test.dart` for the marker-aware colon behavior (including the trailing-colon-produces-no-empty-chunk case); full suite 378/378 passing, `flutter analyze` clean
- [x] 9.4 Scale appended pause durations by `TtsService.speed` (user asked whether pauses account for the TTS speed setting — they didn't): `_pauseDurationFor` renamed to `pauseDurationFor` (`@visibleForTesting`) and divides the base duration by speed; unit-tested directly (400ms→200ms at 2.0x, 700ms→1400ms at 0.5x, `none` stays zero); full suite 380/380 passing, `flutter analyze` clean
- [x] 9.5 Fix cross-message queue bleed found via user testing: playing message A, switching chat sessions, and playing message B there would play B's first chunk correctly, then bleed into A's leftover prefetched chunk instead of B's second chunk. `playNow` now calls `PlaybackService.removeQueued((item) => true)` before `jumpQueue`, clearing everything not-yet-playing regardless of message — `jumpQueue` alone only ever inserted at the front, never touching stale content already queued behind it. Regression test added and verified to fail without the fix (reverted the fix, confirmed the test fails with the exact reported symptom, restored the fix); full suite 381/381 passing, `flutter analyze` clean

## 10. Third refinement round (testing on a second device/model combination)

- [x] 10.1 Reduce `_paragraphPauseDuration` 400ms → 250ms (reported too long)
- [x] 10.2 Give headings the longer pause on both sides, not just before: `text_chunker.dart`'s pause computation now also checks `paragraph.isHeading` (previously only checked whether the *next* paragraph was a heading), so a heading's own trailing pause is `ChunkPause.heading` instead of falling back to the plain paragraph tier
- [x] 10.3 Gate the colon real-pause mechanism (task 9.2) behind `const _useRealColonPause = false` in `text_normalizer.dart` for an A/B comparison against plain-comma — reported "irritatingly long" on the second device/model. The chunker's marker-splitting logic is untouched and still directly tested via an explicit marker in the input, so it doesn't bit-rot while the flag is off
- [x] 10.4 Update `text_chunker_test.dart` (heading-both-sides expectation; colon test split into "stays one chunk while the flag is off" + "chunker still splits on an explicit marker"), `text_normalizer_test.dart` (colon expectations back to plain comma), and `tts_provider_test.dart` (`pauseDurationFor` paragraph values 400ms→250ms/125ms); full suite 382/382 passing, `flutter analyze` clean

## 11. Fourth refinement round (task 9.5's fix was incomplete; colon/list-item follow-through)

User reported the cross-message bleed symptom was still audible after 9.5, plus paragraph/heading pauses seeming unchanged, despite the fixes being in the working tree. Root-caused via a fresh from-source device install (ruling out stale build/cache) plus temporary trace logging.

- [x] 11.1 Found the actual defect: `PlaybackService.removeQueued()` deliberately never touches `queue.first` (by design, for `skipPreviousChunk`'s "leave the actively-playing item alone" case). 9.5's `playNow` fix called it once *before* `jumpQueue`, when the old message's currently-playing chunk was still `queue.first` — so `removeQueued` preserved exactly the item it needed to discard. `jumpQueue` then inserted the new chunk at position 0 without evicting it, leaving it as a zombie tail entry that gets played next once the new chunk finishes. The same flaw existed in `skipPreviousChunk`'s call site, just untested for its full consequence (the old current chunk, not only the prefetched tail, was left behind).
- [x] 11.2 Fixed at the source in `jumpQueue()` itself: it now drops the old `queue.first` (the item it's abandoning) as part of building the new queue, while preserving any other unrelated tail entries (e.g. a different message's own prefetch from `enqueue`) — `[item, ...(currentItem != null ? queue.skip(1) : queue)]` instead of `[item, ...queue]`. This fixes both `playNow` and `skipPreviousChunk` in one place; a caller-side fix (calling `removeQueued` again after `jumpQueue`) was tried first and rejected — it bumps `_queueChangeCount`, which races `_processNext`'s in-flight optimistic-concurrency check and silently drops the transition to the new item instead.
- [x] 11.3 Strengthened the existing regression test (`playNow clears a stale prefetched chunk...`) to assert the queue is exactly `['msg-new#0']` right after the jump (not just "doesn't contain the prefetched tail item"), and to let the new chunk finish and confirm the old chunk never gets replayed. Confirmed this stronger test fails against the pre-11.2 code with the reported symptom (`currentItem` stuck at the old chunk id) before landing the fix.
- [x] 11.4 Permanently removed the `_useRealColonPause` A/B flag from `text_normalizer.dart` — colons stay comma-only for good; the real-appended-silence mechanism it gated was confirmed too long/irritating in 10.3 and not revisited.
- [x] 11.5 Repurposed the (now-unused-by-colons) `clausePauseMarker`/chunk-splitting mechanism for list items: `_stripLineMarkers` appends the marker after each bullet/numbered item's text, so the chunker gives every item but the last a `ChunkPause.clause` pause (the last item gets whatever pause tier follows the whole list, same as before). `_proseColon`'s lookahead was extended to also treat the marker as an end-of-text boundary, since a list item whose text itself ends in a colon (e.g. "1. If you want a heading:") would otherwise have the marker sitting between the colon and what the lookahead expected to see.
- [x] 11.6 Updated `text_normalizer_test.dart` (list items now expect a trailing marker; stale `_useRealColonPause` comments removed) and `text_chunker_test.dart` (new coverage: bullet list items get clause pauses with the last deferring to the paragraph pause; numbered list items too); full suite 384/384 passing, `flutter analyze` clean

## 12. Fifth refinement round (list-item pause tuning; interrupted-message UI stuck state)

- [x] 12.1 Reduce `_clausePauseDuration` 200ms → 150ms (list-item pause reported too long)
- [x] 12.2 Fix `playNow` leaving an interrupted message stuck reporting playback focus: `_handlePlaybackStateChange`'s completion detection only resets a message's status when the chunk it loses is that message's *last* one — interrupting a message mid-playback (the common case) never hit that path, so the old message's status stayed `playing`/`paused` forever, `hasPlaybackFocus` stayed true, and its UI kept showing the back/pause/forward row indefinitely (alongside the newly-started message's own row, since both now reported focus simultaneously — this was the same bug behind "the 3-button control should revert to 1 button when focus moves away"). Fixed by having `playNow` explicitly resolve whichever message currently owns `playbackProvider`'s `currentItem` (via `_chunkItemInfo`) and reset it to `idle` before jumping, when that's a different message than the one being played.
- [x] 12.3 Added `apps/test/providers/tts_provider_test.dart` coverage: interrupt a message mid-chunk (not its last) via `playNow` on a different message, assert the interrupted message's `hasPlaybackFocus` becomes false and its status becomes `idle`. Verified the test fails without the fix (reverted the fix, confirmed `hasPlaybackFocus` stayed `true`, restored). Updated `pauseDurationFor` test's clause-tier expectation for the 150ms change. Full suite 385/385 passing, `flutter analyze` clean.

## 13. Sixth refinement round (chunk navigation treats a short list as one paragraph)

User asked for back/forward to treat a list as one paragraph rather than stepping through it item by item, then immediately qualified it: not if the list's items contain long text.

- [x] 13.1 Reused an existing structural signal instead of an arbitrary length threshold: a `ChunkPause.none` pause before a paragraph's last chunk already marks a length-driven sentence-fallback split fragment (see §2.3/8.1), as opposed to a genuine item boundary (every real list item, per §11.5, gets a real `pauseAfter`, `clause` or the paragraph's exit tier). `_isNavigationGroup(chunks, start, end)` in `tts_provider.dart` treats a paragraph's chunk range as one navigable unit only when none of its chunks (but possibly the last) is such a fragment — so a list with one long item that had to be sentence-split reverts the *whole* paragraph to ordinary per-chunk navigation rather than collapsing it.
- [x] 13.2 Rewrote `skipNextChunk`/`skipPreviousChunk` around two new helpers, `_paragraphStart`/`_paragraphEnd` (first/last chunk index sharing a given chunk's `sourceParagraphIndex`) and `_jumpToChunk` (shared drop-stale-then-build-then-jump, previously duplicated). Forward jumps past a whole navigable group at once (or, if not grouped, one raw chunk as before — this is also what already happened for ordinary single-chunk paragraphs, so non-list behavior is unchanged). Back mirrors this: restarts/jumps to the current paragraph's first chunk instead of just the previous raw chunk, and from a paragraph's first chunk jumps to the *previous* paragraph's first chunk (or its single chunk, if that one isn't a navigable group either) rather than one chunk back.
- [x] 13.3 Added `apps/test/providers/tts_provider_test.dart` coverage: forward from a short list's first item jumps straight past all its items to the next paragraph; back from a short list's last item (reached via natural playback cascade, polled rather than timed since hop duration isn't precise enough to hit with a fixed delay) jumps to the list's first item, not the previous one; back from just after a short list jumps to the list's first item, not just its last; a list containing one long item is *not* collapsed — forward still steps one raw chunk at a time through it. Full suite 389/389 passing, `flutter analyze` clean.
