import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/settings.dart';
import '/providers/model_download_provider.dart';
import '/providers/playback_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/tts/audio_source.dart';
import '/tts/services.dart';
import '/tts/text_chunker.dart';
import '/utils/logger.dart';
import '/voice/model_resolver.dart';

const _clausePauseDuration = Duration(milliseconds: 150);
const _paragraphPauseDuration = Duration(milliseconds: 250);
const _headingPauseDuration = Duration(milliseconds: 700);

/// Base pause duration for [pause], scaled by [speed] so pauses stay
/// proportionate to the sped-up/slowed-down speech around them (audio
/// sample rate — and so silence-sample count per wall-clock ms — doesn't
/// change with speed, only how much speech fits in a given duration).
@visibleForTesting
Duration pauseDurationFor(ChunkPause pause, double speed) {
  final base = switch (pause) {
    ChunkPause.none => Duration.zero,
    ChunkPause.clause => _clausePauseDuration,
    ChunkPause.paragraph => _paragraphPauseDuration,
    ChunkPause.heading => _headingPauseDuration,
  };
  if (base == Duration.zero) return base;
  return Duration(microseconds: (base.inMicroseconds / speed).round());
}

enum MessagePlaybackStatus {
  idle,
  generating,
  playing,
  paused,
  completed,
  error,
}

class MessageTtsState {
  final MessagePlaybackStatus status;
  final String? error;
  final int currentChunkIndex;
  final int totalChunks;

  /// Which paragraph of the original message the currently-playing/paused
  /// chunk was derived from (index into [splitRawParagraphs] on the raw
  /// message text) — used by the UI to highlight that paragraph. `-1` when
  /// nothing is playing/paused.
  final int currentSourceParagraphIndex;

  const MessageTtsState({
    this.status = MessagePlaybackStatus.idle,
    this.error,
    this.currentChunkIndex = 0,
    this.totalChunks = 1,
    this.currentSourceParagraphIndex = -1,
  });

  MessageTtsState copyWith({
    MessagePlaybackStatus? status,
    String? Function()? error,
    int? currentChunkIndex,
    int? totalChunks,
    int? currentSourceParagraphIndex,
  }) {
    return MessageTtsState(
      status: status ?? this.status,
      error: error != null ? error() : this.error,
      currentChunkIndex: currentChunkIndex ?? this.currentChunkIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      currentSourceParagraphIndex:
          currentSourceParagraphIndex ?? this.currentSourceParagraphIndex,
    );
  }

  bool get isPlaying => status == MessagePlaybackStatus.playing;
  bool get isGenerating => status == MessagePlaybackStatus.generating;

  /// Whether this message currently owns the playing/paused audio, i.e.
  /// whether chunk navigation controls should be shown for it.
  bool get hasPlaybackFocus =>
      status == MessagePlaybackStatus.playing ||
      status == MessagePlaybackStatus.paused;
}

class TtsState {
  final Map<String, MessageTtsState> messageStates;

  /// Non-null when TTS model initialization failed. Cleared on next successful init.
  final String? initError;

  const TtsState({this.messageStates = const {}, this.initError});

  factory TtsState.initial() => const TtsState();

  TtsState copyWith({
    Map<String, MessageTtsState>? messageStates,
    String? Function()? initError,
  }) {
    return TtsState(
      messageStates: messageStates ?? this.messageStates,
      initError: initError != null ? initError() : this.initError,
    );
  }

  MessageTtsState getMessageState(String messageId) {
    return messageStates[messageId] ?? const MessageTtsState();
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(() {
  return TtsNotifier();
});

/// SharedPreferences key written before TTS init, cleared on success.
/// If present on startup the previous init caused a native crash (SIGABRT).
const _ttsCrashGuardKey = 'tts_crash_guard_model_id';

/// Which message a chunk's [PlaybackItem.id] belongs to, its position in
/// that message's chunk list, and the source paragraph it renders from.
class _ChunkItemInfo {
  final String messageId;
  final int chunkIndex;
  final int sourceParagraphIndex;
  const _ChunkItemInfo(
    this.messageId,
    this.chunkIndex,
    this.sourceParagraphIndex,
  );
}

/// Per-message chunk bookkeeping: the full ordered chunks, and how far
/// ahead synthesis has already been kicked off (drives one-chunk-ahead
/// prefetch and gets reset on a backward chunk jump).
class _ChunkedMessage {
  final List<SpeechChunk> chunks;
  int maxEnqueuedIndex;

  _ChunkedMessage(this.chunks, {required int firstIndex})
    : maxEnqueuedIndex = firstIndex;

  int get lastIndex => chunks.length - 1;
}

class TtsNotifier extends Notifier<TtsState> {
  TtsService? _service;

  // Track tasks to avoid overlapping generation for same message
  final Map<String, Future<void>> _pendingTasks = {};

  // Deferred reinit: true when model became available while generation was busy
  bool _pendingReinit = false;

  final Map<String, _ChunkedMessage> _chunkedMessages = {};
  final Map<String, _ChunkItemInfo> _chunkItemInfo = {};

  @override
  TtsState build() {
    ref.onDispose(() {
      _service?.dispose();
    });

    // Detect if a previous TTS init crashed (SIGABRT leaves the guard set).
    unawaited(Future.microtask(_checkCrashGuard).catchError((e) {
      Logger.error('TtsProvider: Error checking crash guard: $e');
    }));

    // Listen to settings changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.ttsSpeakerId != next.ttsSpeakerId ||
          previous?.ttsSpeed != next.ttsSpeed) {
        _handleSettingsChanged(next);
      }
      // Reinitialize TTS when model selection changes
      if (previous?.selectedTtsModelId != next.selectedTtsModelId) {
        _clearInitError();
        _handleTtsModelChanged();
      }
      // Stop reading whatever was queued from the previous server once the
      // engine URL changes — this notifier depends on settingsProvider, so
      // it must react to the change itself rather than settingsProvider
      // reaching back into it (that direction trips Riverpod's circular-
      // dependency safety check).
      if (previous != null && previous.engineBaseUrl != next.engineBaseUrl) {
        onChatCleared();
      }
    });

    // Listen to playback state to update our internal message states
    ref.listen<PlaybackState>(playbackProvider, (prev, next) {
      _handlePlaybackStateChange(prev, next);
    });

    // Reinitialize when selected model finishes downloading (startup race fix).
    // Defer if a generation is in progress to avoid killing the active isolate.
    ref.listen<ModelDownloadState>(modelDownloadProvider, (previous, next) {
      final selectedId = ref.read(settingsProvider).selectedTtsModelId;
      if (selectedId != null &&
          !(previous?.isDownloaded(selectedId) ?? false) &&
          next.isDownloaded(selectedId)) {
        if (_pendingTasks.isEmpty) {
          _clearInitError();
          _handleTtsModelChanged();
        } else {
          _pendingReinit = true;
        }
      }
    });

    return TtsState.initial();
  }

  /// On startup: if the crash-guard key is still set, the previous TTS init
  /// triggered a native abort. Deselect the offending model so the app stays usable.
  Future<void> _checkCrashGuard() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final crashedId = prefs.getString(_ttsCrashGuardKey);
    if (crashedId == null) return;

    await prefs.remove(_ttsCrashGuardKey);

    final currentId = ref.read(settingsProvider).selectedTtsModelId;
    if (currentId == crashedId) {
      Logger.error(
        'TtsProvider: model "$crashedId" crashed on last init, deselecting',
      );
      await ref.read(settingsProvider.notifier).clearModelSelection(crashedId);
      state = state.copyWith(
        initError: () =>
            'Voice model crashed and was deselected. Please choose a different model.',
      );
    }
  }

  Future<void> _setCrashGuard(SharedPreferences prefs, String? modelId) async {
    if (modelId != null) {
      await prefs.setString(_ttsCrashGuardKey, modelId);
    }
  }

  Future<void> _clearCrashGuard(SharedPreferences prefs) async {
    await prefs.remove(_ttsCrashGuardKey);
  }

  Future<void> initialize() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final modelId = ref.read(settingsProvider).selectedTtsModelId;
    await _setCrashGuard(prefs, modelId);
    try {
      final service = await _getService();
      await service.initialize();
      await _clearCrashGuard(prefs);
    } catch (e) {
      await _clearCrashGuard(prefs);
      Logger.error('TtsProvider: TTS initialization failed: $e');
      state = state.copyWith(initError: () => e.toString());
    }
  }

  Future<TtsService> _getService() async {
    if (_service == null) {
      final voiceService = ref.read(voiceServiceProvider);
      _service = TtsService(voiceService)
        ..speakerId = ref.read(settingsProvider).ttsSpeakerId
        ..speed = ref.read(settingsProvider).ttsSpeed;
    }
    if (_service!.resolvedTtsModel == null) {
      // Resolution came back empty last time — a model is selected but
      // settings or the downloaded-models scan hadn't finished loading yet
      // (a startup race). Retry on every call instead of caching that null
      // forever, so playback self-heals on the next attempt once whatever
      // hadn't loaded yet has: no explicit model switch should be needed.
      final settings = ref.read(settingsProvider);
      final downloadState = ref.read(modelDownloadProvider);
      _service!.resolvedTtsModel = await resolveTtsModel(
        settings,
        downloadState,
      );
    }
    return _service!;
  }

  void _handleSettingsChanged(Settings settings) {
    final service = _service;
    if (service != null) {
      service.speakerId = settings.ttsSpeakerId;
      service.speed = settings.ttsSpeed;
      // Cached audio was generated at the old speed/speaker — invalidate it.
      service.clearCache();
    }
  }

  void _clearInitError() {
    if (state.initError != null) {
      state = state.copyWith(initError: () => null);
    }
  }

  Future<void> _handleTtsModelChanged() async {
    if (_service == null) return;
    _clearInitError();
    final settings = ref.read(settingsProvider);
    final downloadState = ref.read(modelDownloadProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    await _setCrashGuard(prefs, settings.selectedTtsModelId);
    final resolved = await resolveTtsModel(settings, downloadState);
    Logger.debug('TtsProvider: TTS model changed, reinitializing...');
    try {
      await _service!.reinitializeWithModel(resolved);
      await _clearCrashGuard(prefs);
    } catch (e) {
      await _clearCrashGuard(prefs);
      Logger.error('TtsProvider: TTS initialization failed: $e');
      state = state.copyWith(initError: () => e.toString());
    }
  }

  void onChatCleared() {
    ref.read(playbackProvider.notifier).stop();
    state = TtsState.initial();
    // Clear pending generation tasks to prevent stale completions
    _pendingTasks.clear();
    _chunkedMessages.clear();
    _chunkItemInfo.clear();
  }

  List<SpeechChunk> _prepareChunks(String rawText) {
    return splitIntoSpeechChunks(rawText);
  }

  String _chunkKey(String messageId, int index) => '$messageId#$index';

  /// Builds a chunk's [PlaybackItem], registers it in [_chunkItemInfo], and
  /// (for the last chunk only) arranges to mark the message `completed` if
  /// its generation fails — a failed last chunk never becomes the playback
  /// queue's current item, so the normal playing→completed transition never
  /// fires for it.
  PlaybackItem _buildChunkItem(
    TtsService service,
    String messageId,
    List<SpeechChunk> chunks,
    int index,
  ) {
    final key = _chunkKey(messageId, index);
    final chunk = chunks[index];
    _chunkItemInfo[key] = _ChunkItemInfo(
      messageId,
      index,
      chunk.sourceParagraphIndex,
    );

    final contentFuture = service.generate(chunk.text, key).then((bytes) {
      if (bytes == null) {
        throw Exception('Generation failed');
      }
      return appendSilenceToWav(
        bytes,
        pauseDurationFor(chunk.pauseAfter, service.speed),
      );
    });

    if (index == chunks.length - 1) {
      contentFuture.then(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (_chunkedMessages.containsKey(messageId)) {
            _chunkedMessages.remove(messageId);
            _updateMessageState(
              messageId,
              status: MessagePlaybackStatus.completed,
            );
          }
        },
      );
    }

    return PlaybackItem(id: key, content: contentFuture);
  }

  /// Play a message immediately (user clicked play button)
  /// Stops current playback and plays this message
  Future<void> playNow(String text, String messageId) async {
    if (_pendingTasks.containsKey(messageId)) return;

    final chunks = _prepareChunks(text);
    if (chunks.isEmpty) {
      _updateMessageState(messageId, status: MessagePlaybackStatus.completed);
      return;
    }

    final service = await _getService();
    _updateMessageState(
      messageId,
      status: MessagePlaybackStatus.generating,
      currentChunkIndex: 0,
      totalChunks: chunks.length,
    );

    _chunkedMessages[messageId] = _ChunkedMessage(chunks, firstIndex: 0);
    final firstItem = _buildChunkItem(service, messageId, chunks, 0);

    final task = Future<void>(() async {
      try {
        final playback = ref.read(playbackProvider.notifier);

        // Interrupting a different message that was still playing/paused
        // doesn't naturally reset its status: _handlePlaybackStateChange
        // only marks a message completed when the chunk it loses is that
        // message's *last* one. Cut off mid-message (its more common case
        // here), it would otherwise stay stuck reporting playback focus —
        // hasPlaybackFocus stays true, so its UI keeps showing the
        // back/pause/forward row and the just-started new message's row
        // shows alongside it instead of replacing it.
        final interruptedItemId = playback.state.currentItem?.id;
        final interruptedInfo = interruptedItemId == null
            ? null
            : _chunkItemInfo[interruptedItemId];
        if (interruptedInfo != null && interruptedInfo.messageId != messageId) {
          _chunkedMessages.remove(interruptedInfo.messageId);
          _updateMessageState(
            interruptedInfo.messageId,
            status: MessagePlaybackStatus.idle,
          );
        }

        // "Play now" stops and replaces everything, not just the current
        // item — otherwise a prefetched next-chunk from whatever was
        // playing before (a different message, possibly a different chat
        // session) is still sitting in the queue and plays right after
        // this message's first chunk.
        playback.removeQueued((item) => true);
        await playback.jumpQueue(firstItem);
      } catch (e) {
        Logger.debug('TtsProvider: Error playing $messageId: $e');
        _updateMessageState(
          messageId,
          status: MessagePlaybackStatus.error,
          error: e.toString(),
        );
      }
    });

    _pendingTasks[messageId] = task;

    try {
      await task;
    } finally {
      _pendingTasks.remove(messageId);
      if (_pendingReinit && _pendingTasks.isEmpty) {
        _pendingReinit = false;
        _handleTtsModelChanged();
      }
    }
  }

  /// Add a message to the playback queue
  /// Logic:
  /// 1. Trigger generation of the first chunk (async)
  /// 2. Enqueue it directly to PlaybackService; later chunks follow via
  ///    one-chunk-ahead prefetch as earlier ones start playing.
  Future<void> enqueue(String text, String messageId) async {
    if (_pendingTasks.containsKey(messageId)) return;

    final chunks = _prepareChunks(text);
    if (chunks.isEmpty) {
      _updateMessageState(messageId, status: MessagePlaybackStatus.completed);
      return;
    }

    final service = await _getService();
    _updateMessageState(
      messageId,
      status: MessagePlaybackStatus.generating,
      currentChunkIndex: 0,
      totalChunks: chunks.length,
    );

    _chunkedMessages[messageId] = _ChunkedMessage(chunks, firstIndex: 0);
    final firstItem = _buildChunkItem(service, messageId, chunks, 0);

    // We wrap the enqueue in a pending task to prevent duplicates
    // But we don't await the playback itself here, just the enqueueing
    final task = Future<void>(() async {
      try {
        await ref.read(playbackProvider.notifier).enqueue(firstItem);
      } catch (e) {
        Logger.debug('TtsProvider: Error enqueueing $messageId: $e');
        _updateMessageState(
          messageId,
          status: MessagePlaybackStatus.error,
          error: e.toString(),
        );
      }
    });

    _pendingTasks[messageId] = task;

    try {
      await task;
    } finally {
      _pendingTasks.remove(messageId);
      if (_pendingReinit && _pendingTasks.isEmpty) {
        _pendingReinit = false;
        _handleTtsModelChanged();
      }
    }
  }

  /// Pause the currently playing message
  Future<void> pause() async {
    Logger.debug('TtsProvider: Pausing playback');
    await ref.read(playbackProvider.notifier).pause();
  }

  /// Resume the currently paused message
  Future<void> resume() async {
    Logger.debug('TtsProvider: Resuming playback');
    await ref.read(playbackProvider.notifier).resume();
  }

  bool _hasPlaybackFocus(String messageId) =>
      state.getMessageState(messageId).hasPlaybackFocus;

  /// Whether `chunks[start..end]` (one paragraph's worth of chunks) should
  /// be treated as a single unit for back/forward navigation — true for a
  /// list of short items, each its own whole chunk; false if any item ran
  /// long enough to need further splitting. A `ChunkPause.none` pause
  /// before the range's last chunk marks a length-driven split fragment
  /// rather than a genuine item boundary; if the paragraph contains one,
  /// the whole paragraph (not just that item) falls back to ordinary
  /// per-chunk navigation instead of being collapsed into one skip — a
  /// list with one long item is no longer "a list of short items."
  bool _isNavigationGroup(List<SpeechChunk> chunks, int start, int end) {
    if (end <= start) return false;
    for (var i = start; i < end; i++) {
      if (chunks[i].pauseAfter == ChunkPause.none) return false;
    }
    return true;
  }

  int _paragraphStart(List<SpeechChunk> chunks, int index) {
    final paragraph = chunks[index].sourceParagraphIndex;
    var start = index;
    while (start > 0 && chunks[start - 1].sourceParagraphIndex == paragraph) {
      start--;
    }
    return start;
  }

  int _paragraphEnd(List<SpeechChunk> chunks, int index) {
    final paragraph = chunks[index].sourceParagraphIndex;
    var end = index;
    while (end + 1 < chunks.length &&
        chunks[end + 1].sourceParagraphIndex == paragraph) {
      end++;
    }
    return end;
  }

  /// Drops this message's stale queued/prefetched chunks and jumps
  /// straight to [targetIndex] — shared by both navigation directions.
  Future<void> _jumpToChunk(
    String messageId,
    _ChunkedMessage chunked,
    int targetIndex,
  ) async {
    final playback = ref.read(playbackProvider.notifier);
    playback.removeQueued(
      (item) => _chunkItemInfo[item.id]?.messageId == messageId,
    );
    chunked.maxEnqueuedIndex = targetIndex;
    final service = await _getService();
    final item = _buildChunkItem(
      service,
      messageId,
      chunked.chunks,
      targetIndex,
    );
    await playback.jumpQueue(item);
  }

  /// Ends the current chunk — or, for a short list navigated as one
  /// paragraph, all of its remaining items — and lets the playback queue
  /// advance to whatever comes next (the next paragraph, or nothing if it
  /// was the last).
  Future<void> skipNextChunk(String messageId) async {
    if (!_hasPlaybackFocus(messageId)) return;

    final playback = ref.read(playbackProvider.notifier);
    final chunked = _chunkedMessages[messageId];
    final currentIndex = state.getMessageState(messageId).currentChunkIndex;
    if (chunked == null || currentIndex >= chunked.chunks.length) {
      await playback.skipCurrent();
      return;
    }

    final start = _paragraphStart(chunked.chunks, currentIndex);
    final end = _paragraphEnd(chunked.chunks, currentIndex);
    final targetIndex = _isNavigationGroup(chunked.chunks, start, end)
        ? end + 1
        : currentIndex + 1;

    if (targetIndex > chunked.lastIndex) {
      // Nothing but this message's own last paragraph remains (list items
      // included) — drop it and let the current chunk's natural finish
      // hand off to whatever the queue determines comes next.
      playback.removeQueued(
        (item) => _chunkItemInfo[item.id]?.messageId == messageId,
      );
      await playback.skipCurrent();
      return;
    }

    await _jumpToChunk(messageId, chunked, targetIndex);
  }

  /// Restarts the current paragraph if more than ~3s into it (jumping back
  /// to its first chunk for a multi-item list); otherwise jumps to the
  /// previous paragraph. No-ops on the message's first paragraph within
  /// the first ~3s.
  Future<void> skipPreviousChunk(String messageId) async {
    if (!_hasPlaybackFocus(messageId)) return;

    final playback = ref.read(playbackProvider.notifier);
    final chunked = _chunkedMessages[messageId];
    final currentIndex = state.getMessageState(messageId).currentChunkIndex;
    if (chunked == null || currentIndex >= chunked.chunks.length) return;

    // Chunks that aren't part of a navigable group behave as their own
    // one-chunk "paragraph" here, which reproduces the old per-chunk
    // behavior without a separate code path.
    final grouped = _isNavigationGroup(
      chunked.chunks,
      _paragraphStart(chunked.chunks, currentIndex),
      _paragraphEnd(chunked.chunks, currentIndex),
    );
    final paragraphStart = grouped
        ? _paragraphStart(chunked.chunks, currentIndex)
        : currentIndex;

    if (playback.currentPosition() > const Duration(seconds: 3)) {
      if (currentIndex == paragraphStart) {
        await playback.seekToStart();
      } else {
        await _jumpToChunk(messageId, chunked, paragraphStart);
      }
      return;
    }

    if (currentIndex > paragraphStart) {
      await _jumpToChunk(messageId, chunked, paragraphStart);
      return;
    }

    if (paragraphStart <= 0) return;
    final previousIndex = paragraphStart - 1;
    final previousGrouped = _isNavigationGroup(
      chunked.chunks,
      _paragraphStart(chunked.chunks, previousIndex),
      _paragraphEnd(chunked.chunks, previousIndex),
    );
    final targetIndex = previousGrouped
        ? _paragraphStart(chunked.chunks, previousIndex)
        : previousIndex;
    await _jumpToChunk(messageId, chunked, targetIndex);
  }

  void _prefetchNextChunk(String messageId, int playingIndex) async {
    final chunked = _chunkedMessages[messageId];
    if (chunked == null) return;

    final nextIndex = playingIndex + 1;
    if (nextIndex > chunked.lastIndex) return;
    if (nextIndex <= chunked.maxEnqueuedIndex) return;

    chunked.maxEnqueuedIndex = nextIndex;
    final service = await _getService();
    final item = _buildChunkItem(service, messageId, chunked.chunks, nextIndex);
    await ref.read(playbackProvider.notifier).enqueue(item);
  }

  void _handlePlaybackStateChange(PlaybackState? prev, PlaybackState next) {
    // Handle completion FIRST (transition from playing to idle/next)
    if (prev?.currentItem != null) {
      final prevItemId = prev!.currentItem!.id;
      final nextItemId = next.currentItem?.id;

      // Item is completed if it changed (new item started or became null)
      if (prevItemId != nextItemId) {
        final info = _chunkItemInfo.remove(prevItemId);
        if (info != null) {
          final chunked = _chunkedMessages[info.messageId];
          if (chunked != null && info.chunkIndex == chunked.lastIndex) {
            _chunkedMessages.remove(info.messageId);
            _updateMessageState(
              info.messageId,
              status: MessagePlaybackStatus.completed,
            );
          } else {
            // Cut off mid-message (not its last chunk). _finishAndNext
            // publishes an intermediate currentItem: null state while
            // _processNext works out what plays next - during ordinary
            // chunk-to-chunk progression the message's next chunk is
            // already sitting in `next.queue` at that point (prefetched
            // one chunk ahead), so checking the queue (not just
            // next.currentItem, which lags a beat behind it) is what tells
            // a genuine in-flight advance apart from an actual interrupt.
            // Most callers that interrupt a message themselves (playNow)
            // already reset it, but external stops - the notification Stop
            // button, an audio focus interruption - land here with no such
            // call site, so this is the only place that can catch them;
            // otherwise the message is left reporting playback focus
            // forever, stuck showing back/pause/forward controls for
            // content that already stopped.
            final sameMessageContinues = next.queue.any(
              (queued) =>
                  _chunkItemInfo[queued.id]?.messageId == info.messageId,
            );
            if (!sameMessageContinues) {
              _chunkedMessages.remove(info.messageId);
              _updateMessageState(
                info.messageId,
                status: MessagePlaybackStatus.idle,
              );
            }
          }
        }
      }
    }

    // Update playing/paused status of current item. Gated on an actual
    // transition (item or status changed) — a queue-only mutation (e.g. a
    // backward chunk jump's intermediate state, before _processNext gets
    // around to reassigning currentItem) must not re-fire this, or it would
    // re-trigger prefetch and resurrect a chunk that was just removed.
    final currentItemChanged = prev?.currentItem?.id != next.currentItem?.id;
    final statusChanged = prev?.status != next.status;
    if (next.currentItem != null && (currentItemChanged || statusChanged)) {
      final itemId = next.currentItem!.id;
      final info = _chunkItemInfo[itemId];
      if (info != null) {
        if (next.isPlaying) {
          _updateMessageState(
            info.messageId,
            status: MessagePlaybackStatus.playing,
            currentChunkIndex: info.chunkIndex,
            currentSourceParagraphIndex: info.sourceParagraphIndex,
          );
          _prefetchNextChunk(info.messageId, info.chunkIndex);
        } else if (next.isPaused) {
          _updateMessageState(
            info.messageId,
            status: MessagePlaybackStatus.paused,
            currentChunkIndex: info.chunkIndex,
            currentSourceParagraphIndex: info.sourceParagraphIndex,
          );
        }
      }
    }

    // Handle queue clearing - reset all items that were in queue but are gone
    if (prev != null && prev.queue.isNotEmpty && next.queue.isEmpty) {
      Logger.debug(
        'TtsProvider: Playback queue cleared, resetting ${prev.queue.length} pending items',
      );
      for (final item in prev.queue) {
        final info = _chunkItemInfo[item.id];
        final messageId = info?.messageId ?? item.id;
        final messageState = state.getMessageState(messageId);
        // Reset to idle if it was generating (waiting in queue)
        if (messageState.isGenerating) {
          _updateMessageState(messageId, status: MessagePlaybackStatus.idle);
        }
      }
    }
  }

  void _updateMessageState(
    String messageId, {
    MessagePlaybackStatus? status,
    String? error,
    int? currentChunkIndex,
    int? totalChunks,
    int? currentSourceParagraphIndex,
  }) {
    final currentState = state.getMessageState(messageId);
    final newMessageState = currentState.copyWith(
      status: status,
      error: error != null ? () => error : null,
      currentChunkIndex: currentChunkIndex,
      totalChunks: totalChunks,
      currentSourceParagraphIndex: currentSourceParagraphIndex,
    );

    final newStates = Map<String, MessageTtsState>.from(state.messageStates);
    newStates[messageId] = newMessageState;
    state = state.copyWith(messageStates: newStates);
  }
}
