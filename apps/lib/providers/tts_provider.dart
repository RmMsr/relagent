import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
import '/tts/services.dart';

enum PlaybackStatus {
  idle,       // No audio generated or player stopped
  generating, // Currently generating audio
  playing,    // Audio is playing
  paused,     // Audio is paused
  completed,  // Playback finished naturally
}

class MessageTtsState {
  final PlaybackStatus status;
  final String? cachedAudioPath;
  final String? error;

  const MessageTtsState({
    this.status = PlaybackStatus.idle,
    this.cachedAudioPath,
    this.error,
  });

  MessageTtsState copyWith({
    PlaybackStatus? status,
    String? Function()? cachedAudioPath,
    String? Function()? error,
  }) {
    return MessageTtsState(
      status: status ?? this.status,
      cachedAudioPath: cachedAudioPath != null ? cachedAudioPath() : this.cachedAudioPath,
      error: error != null ? error() : this.error,
    );
  }

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isGenerating => status == PlaybackStatus.generating;
  bool get hasCache => cachedAudioPath != null;
}

class QueueItem {
  final String messageId;
  final String text;

  const QueueItem({required this.messageId, required this.text});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueueItem &&
          runtimeType == other.runtimeType &&
          messageId == other.messageId;

  @override
  int get hashCode => messageId.hashCode;
}

class TtsState {
  final Map<String, MessageTtsState> messageStates;
  final List<QueueItem> playbackQueue;
  final String? error;

  const TtsState({
    this.messageStates = const {},
    this.playbackQueue = const [],
    this.error,
  });

  factory TtsState.initial() {
    return const TtsState();
  }

  TtsState copyWith({
    Map<String, MessageTtsState>? messageStates,
    List<QueueItem>? playbackQueue,
    String? error,
  }) {
    return TtsState(
      messageStates: messageStates ?? this.messageStates,
      playbackQueue: playbackQueue ?? this.playbackQueue,
      error: error,
    );
  }

  MessageTtsState getMessageState(String messageId) {
    return messageStates[messageId] ?? const MessageTtsState();
  }

  bool isPlaying(String messageId) {
    return getMessageState(messageId).isPlaying;
  }

  bool get hasQueuedItems => playbackQueue.isNotEmpty;

  bool get isAnyPlaying =>
      messageStates.values.any((state) => state.isPlaying);
}

final ttsProvider = StateNotifierProvider<TtsNotifier, TtsState>((ref) {
  return TtsNotifier(ref);
});

class TtsNotifier extends StateNotifier<TtsState> {
  final Ref ref;
  TtsService? _service;
  bool _manualPlayInProgress = false;
  bool _isProcessingQueue = false; // Lock to prevent concurrent queue processing

  TtsNotifier(this.ref) : super(TtsState.initial()) {
    // Listen to settings changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.ttsSpeakerId != next.ttsSpeakerId ||
          previous?.ttsSpeed != next.ttsSpeed) {
        _handleSettingsChanged(next);
      }
    });
  }

  TtsService _getService() {
    if (_service == null) {
      final settings = ref.read(settingsProvider);
      _service = TtsService(
        onPlaybackStarted: _handlePlaybackStarted,
        onPlaybackFinished: _handlePlaybackFinished,
        onError: _handleError,
      )
        ..speakerId = settings.ttsSpeakerId
        ..speed = settings.ttsSpeed;
    }
    return _service!;
  }

  void _handleSettingsChanged(Settings settings) {
    final service = _service;
    if (service != null) {
      service.speakerId = settings.ttsSpeakerId;
      service.speed = settings.ttsSpeed;

      // Invalidate cached audio since settings affect generation
      final newStates = <String, MessageTtsState>{};
      for (final entry in state.messageStates.entries) {
        // Clear cache path to force regeneration on next play
        newStates[entry.key] = entry.value.copyWith(
          cachedAudioPath: () => null,
          status: PlaybackStatus.idle,
        );
      }
      state = state.copyWith(messageStates: newStates);

      // Clean up old audio files since they're now invalid
      service.cleanup(state.messageStates.keys.toSet());
    }
  }

  /// Pre-initialize TTS in background to minimize wait time when first needed
  Future<void> preInitialize() async {
    debugPrint('TtsProvider: Pre-initializing TTS...');
    final service = _getService();
    // Start background initialization
    await service.initialize();
    debugPrint('TtsProvider: TTS pre-initialization complete');
  }

  Future<void> togglePlayPause(String text, String messageId) async {
    final service = _getService();
    final messageState = state.getMessageState(messageId);
    final settings = ref.read(settingsProvider);

    if (messageState.isPlaying) {
      // Currently playing, so pause and release coordinator lock
      await service.pause(messageId);
      _updateMessageState(messageId, status: PlaybackStatus.paused);

      // Release coordinator lock when pausing
      debugPrint('TtsProvider: Releasing lock on pause');
      await ref.read(audioCoordinatorProvider.notifier).releasePlayback();
    } else if (messageState.isPaused) {
      // Paused, so resume - stop other playback first and acquire lock
      await _stopOthers(messageId);

      debugPrint('TtsProvider: Requesting playback permission for resume');
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestPlayback();

      if (!granted) {
        debugPrint('TtsProvider: Coordinator denied playback request');
        return;
      }

      await service.resume(messageId);
      _updateMessageState(messageId, status: PlaybackStatus.playing);
    } else {
      // Manual play: clear queue, stop others, play this message
      clearQueue(); // Clear existing queue
      await _stopOthers(messageId);

      // Ensure any existing lock is released before requesting new one
      final currentMode = ref.read(audioCoordinatorProvider).mode;
      if (currentMode == AudioMode.playing) {
        debugPrint('TtsProvider: Releasing existing playback lock before new playback');
        await ref.read(audioCoordinatorProvider.notifier).releasePlayback();
      }

      if (messageState.hasCache) {
        // Play from cache - request lock right before playing
        debugPrint('TtsProvider: Requesting playback permission for cached audio');
        final granted = await ref
            .read(audioCoordinatorProvider.notifier)
            .requestPlayback();

        if (!granted) {
          debugPrint('TtsProvider: Coordinator denied playback request');
          return;
        }

        await service.playFromCache(messageId);
        _updateMessageState(messageId, status: PlaybackStatus.playing);
      } else {
        // Generate new audio (don't request lock yet - let recording continue during generation)
        // Lock will be requested in _handlePlaybackStarted when audio is ready to play
        _updateMessageState(messageId, status: PlaybackStatus.generating);
        final success = await service.speak(text, messageId);
        if (success) {
          _updateMessageState(
            messageId,
            status: PlaybackStatus.playing,
            cachedAudioPath: messageId, // Use messageId as cache marker
          );
        } else {
          _updateMessageState(messageId, status: PlaybackStatus.idle);
        }
      }

      // If in auto-playback mode, re-enable queue processing after this message
      // (messages that arrive after this point will be queued and played)
      _manualPlayInProgress = !settings.isAutoPlayback;
    }
  }

  Future<void> stop(String messageId) async {
    final service = _getService();
    await service.stop(messageId);
    _updateMessageState(messageId, status: PlaybackStatus.idle);
  }

  Future<void> stopAll() async {
    _service?.stopAll();
    // Reset all message states to idle
    final newStates = <String, MessageTtsState>{};
    for (final entry in state.messageStates.entries) {
      newStates[entry.key] = entry.value.copyWith(status: PlaybackStatus.idle);
    }
    state = state.copyWith(messageStates: newStates);
  }

  /// Stop all messages except the specified one
  Future<void> _stopOthers(String exceptMessageId) async {
    final service = _service;
    if (service == null) return;

    final newStates = <String, MessageTtsState>{};
    for (final entry in state.messageStates.entries) {
      final messageId = entry.key;
      final messageState = entry.value;

      if (messageId == exceptMessageId) {
        // Keep this message's state unchanged
        newStates[messageId] = messageState;
      } else if (messageState.isPlaying || messageState.isPaused) {
        // Stop playing or paused messages completely
        await service.stop(messageId);
        newStates[messageId] = messageState.copyWith(status: PlaybackStatus.idle);
      } else {
        // Keep other states unchanged
        newStates[messageId] = messageState;
      }
    }
    state = state.copyWith(messageStates: newStates);
  }

  Future<void> replay(String messageId) async {
    final messageState = state.getMessageState(messageId);
    if (messageState.hasCache) {
      // Stop other playback first
      await _stopOthers(messageId);
      await stop(messageId);
      final service = _getService();
      await service.playFromCache(messageId);
      _updateMessageState(messageId, status: PlaybackStatus.playing);
    }
  }

  void onChatCleared() {
    // Clean up resources for all messages
    final messageIds = state.messageStates.keys.toSet();
    _service?.cleanup(messageIds);
    state = TtsState.initial();
  }

  /// Add a message to the playback queue
  void enqueue(String text, String messageId) {
    debugPrint('TtsProvider: enqueue() called for [$messageId]');
    final item = QueueItem(messageId: messageId, text: text);
    // Don't add duplicates
    if (!state.playbackQueue.contains(item)) {
      final newQueue = [...state.playbackQueue, item];
      state = state.copyWith(playbackQueue: newQueue);
      debugPrint('TtsProvider: Added [$messageId] to queue (queue size: ${newQueue.length})');

      // Eagerly pre-generate audio in background (non-blocking)
      // This allows audio to be ready when it's time to play
      _preGenerateAudio(text, messageId);

      // Start processing if nothing is playing
      if (!state.isAnyPlaying) {
        debugPrint('TtsProvider: Nothing playing, starting queue processing');
        _processQueue();
      } else {
        debugPrint('TtsProvider: Playback active, queue will process after current finishes');
      }
    } else {
      debugPrint('TtsProvider: Skipping duplicate [$messageId]');
    }
  }

  /// Pre-generate audio in background without blocking
  Future<void> _preGenerateAudio(String text, String messageId) async {
    final service = _getService();
    _updateMessageState(messageId, status: PlaybackStatus.generating);

    debugPrint('TtsProvider: Pre-generating audio [$messageId]');
    final success = await service.preGenerate(text, messageId);

    if (success) {
      // Mark as idle (audio cached, ready to play)
      _updateMessageState(messageId, status: PlaybackStatus.idle);
      debugPrint('TtsProvider: Pre-generation complete [$messageId]');
    } else {
      _updateMessageState(messageId, status: PlaybackStatus.idle, error: 'Generation failed');
    }

    // Trigger queue processing in case it was waiting for this message
    _processQueue();
  }

  /// Remove a specific item from the queue
  void dequeue(String messageId) {
    final newQueue = state.playbackQueue
        .where((item) => item.messageId != messageId)
        .toList();
    state = state.copyWith(playbackQueue: newQueue);
  }

  /// Clear the entire queue
  void clearQueue() {
    state = state.copyWith(playbackQueue: []);
  }

  /// Skip current playback and play next in queue
  Future<void> skipToNext() async {
    // Stop current playback
    for (final entry in state.messageStates.entries) {
      if (entry.value.isPlaying) {
        await stop(entry.key);
        break;
      }
    }
    // Process next in queue
    _processQueue();
  }

  /// Process the next item in the queue
  Future<void> _processQueue() async {
    // Acquire lock to prevent concurrent queue processing
    if (_isProcessingQueue) {
      debugPrint('TtsProvider: _processQueue already in progress, skipping');
      return;
    }
    _isProcessingQueue = true;

    try {
      debugPrint('TtsProvider: _processQueue() called (queue size: ${state.playbackQueue.length})');

      // Don't process if something is already playing
      if (state.isAnyPlaying) {
        debugPrint('TtsProvider: Something already playing, skipping queue processing');
        return;
      }

      // Get next item from queue
      if (state.playbackQueue.isEmpty) {
        debugPrint('TtsProvider: Queue is empty');
        return;
      }

      final item = state.playbackQueue.first;
      debugPrint('TtsProvider: Processing queue item [${item.messageId}]');

      // Wait for this specific message to finish generating before playing
      // (other messages can generate in background)
      final messageState = state.getMessageState(item.messageId);
      if (messageState.isGenerating) {
        debugPrint('TtsProvider: Queue waiting for [${item.messageId}] to finish generating');
        return;
      }

      // Remove from queue
      final newQueue = state.playbackQueue.sublist(1);
      state = state.copyWith(playbackQueue: newQueue);
      debugPrint('TtsProvider: Starting playback for [${item.messageId}]');

      // Play the item (from cache, as it was pre-generated)
      final service = _getService();

      // Request playback permission
      debugPrint('TtsProvider: Requesting playback permission for queued item [${item.messageId}]');
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestPlayback();

      if (!granted) {
        debugPrint('TtsProvider: Coordinator denied playback request');
        return;
      }

      // Play from cache (audio was pre-generated)
      await service.playFromCache(item.messageId);
      _updateMessageState(item.messageId, status: PlaybackStatus.playing);

      // Start polling player state to detect transitions
      debugPrint('TtsProvider: Starting state polling for [${item.messageId}]');
      _startPolling(item.messageId);
    } finally {
      // Release lock
      _isProcessingQueue = false;
    }

    // After playback command completes and lock is released, check if we should continue
    debugPrint('TtsProvider: Playback command completed, checking for next item');
    if (state.playbackQueue.isNotEmpty && !state.isAnyPlaying) {
      debugPrint('TtsProvider: Queue has more items, continuing processing');
      // Recursively process next item (lock is now released)
      await _processQueue();
    }
  }

  /// Start periodic polling for a message's player state
  void _startPolling(String messageId) {
    // Poll every 100ms to detect state changes
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      final service = _service;
      if (service == null) {
        timer.cancel();
        return;
      }

      final processingState = service.getProcessingState(messageId);

      // Stop polling when playback completes or player is disposed
      if (processingState == null ||
          processingState == ProcessingState.idle ||
          processingState == ProcessingState.completed) {
        debugPrint('TtsProvider: Stopping polling for [$messageId] (state: $processingState)');
        timer.cancel();

        // Do final poll to catch completion
        if (processingState == ProcessingState.completed) {
          _pollPlayerState(messageId);
        }
        return;
      }

      // Poll for state changes
      _pollPlayerState(messageId);
    });
  }

  void _updateMessageState(
    String messageId, {
    PlaybackStatus? status,
    String? cachedAudioPath,
    String? error,
  }) {
    final currentState = state.getMessageState(messageId);
    final newMessageState = currentState.copyWith(
      status: status,
      cachedAudioPath: cachedAudioPath != null ? () => cachedAudioPath : null,
      error: error != null ? () => error : null,
    );

    final newStates = Map<String, MessageTtsState>.from(state.messageStates);
    newStates[messageId] = newMessageState;
    state = state.copyWith(messageStates: newStates);
  }

  /// Poll player state to detect transitions (alternative to callbacks)
  void _pollPlayerState(String messageId) {
    final service = _service;
    if (service == null) return;

    final isPlaying = service.isPlaying(messageId);
    final processingState = service.getProcessingState(messageId);
    final currentStatus = state.getMessageState(messageId).status;

    // Detect playback started transition
    if (isPlaying && currentStatus != PlaybackStatus.playing) {
      debugPrint('TtsProvider: Detected playback start via polling [$messageId]');
      _handlePlaybackStarted(messageId);
    }

    // Detect playback finished transition
    if (processingState == ProcessingState.completed &&
        currentStatus == PlaybackStatus.playing) {
      debugPrint('TtsProvider: Detected playback finish via polling [$messageId]');
      _handlePlaybackFinished(messageId);
    }
  }

  void _handlePlaybackStarted(String messageId) {
    debugPrint('TtsProvider: Playback started [$messageId]');

    // Request playback lock when audio actually starts playing (for generated audio)
    // For cached audio, lock is already acquired before playback
    final coordinator = ref.read(audioCoordinatorProvider.notifier);
    final currentMode = ref.read(audioCoordinatorProvider).mode;

    if (currentMode != AudioMode.playing) {
      // Lock not yet acquired, request it now
      debugPrint('TtsProvider: Requesting playback permission (audio ready to play)');
      coordinator.requestPlayback().then((granted) {
        if (!granted) {
          debugPrint('TtsProvider: Warning - playback started but coordinator denied lock');
        }
      });
    }

    _updateMessageState(messageId, status: PlaybackStatus.playing);
  }

  void _handlePlaybackFinished(String messageId) {
    debugPrint('TtsProvider: Playback finished [$messageId]');
    _updateMessageState(messageId, status: PlaybackStatus.completed);

    // Check if any other message is still playing
    final stillPlaying = state.messageStates.values
        .any((s) => s.status == PlaybackStatus.playing);

    // If no other playback active, release coordinator lock
    if (!stillPlaying) {
      debugPrint('TtsProvider: No more playback, releasing coordinator lock');
      ref.read(audioCoordinatorProvider.notifier).releasePlayback();
    }

    // Resume queue processing after manual play finishes
    if (_manualPlayInProgress) {
      _manualPlayInProgress = false;
      final settings = ref.read(settingsProvider);
      if (settings.isAutoPlayback) {
        // Re-enable auto-queue: process any queued items
        if (!_isProcessingQueue) {
          _processQueue();
        }
      }
    } else {
      // Normal queue processing (only if not already processing)
      if (!_isProcessingQueue) {
        _processQueue();
      } else {
        debugPrint('TtsProvider [$messageId]: Queue processing already active, will continue automatically');
      }
    }

    // Reset completed message to idle after queue processing
    // This ensures the UI doesn't continue showing the pause icon
    _updateMessageState(messageId, status: PlaybackStatus.idle);
  }

  void _handleError(String messageId, String error) {
    _updateMessageState(messageId, status: PlaybackStatus.idle, error: error);
    state = state.copyWith(error: error);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
