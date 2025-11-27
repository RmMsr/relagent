import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final item = QueueItem(messageId: messageId, text: text);
    // Don't add duplicates
    if (!state.playbackQueue.contains(item)) {
      final newQueue = [...state.playbackQueue, item];
      state = state.copyWith(playbackQueue: newQueue);
      // Start processing if nothing is playing
      if (!state.isAnyPlaying) {
        _processQueue();
      }
    }
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
    // Don't process if something is already playing or generating
    if (state.isAnyPlaying ||
        state.messageStates.values.any((s) => s.isGenerating)) {
      return;
    }

    // Get next item from queue
    if (state.playbackQueue.isEmpty) {
      return;
    }

    final item = state.playbackQueue.first;
    // Remove from queue
    final newQueue = state.playbackQueue.sublist(1);
    state = state.copyWith(playbackQueue: newQueue);

    // Play the item
    await togglePlayPause(item.text, item.messageId);
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

  void _handlePlaybackStarted(String messageId) {
    debugPrint('TtsProvider: Playback started for message: $messageId');

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
    debugPrint('TtsProvider: Playback finished for message: $messageId');
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
        _processQueue();
      }
    } else {
      // Normal queue processing
      _processQueue();
    }
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
