import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '../tts/audio_source.dart';
import 'audio_coordinator_provider.dart';

/// Provider for AudioPlayer instance with automatic disposal.
/// This enables dependency injection for testing.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(() {
    player.dispose();
  });
  return player;
});

class PlaybackItem {
  final String id;
  final Future<Uint8List> content;
  final Completer<void> onFinished;
  final bool requiresLock;

  PlaybackItem({
    required this.id,
    required this.content,
    Completer<void>? onFinished,
    this.requiresLock = true,
  }) : onFinished = onFinished ?? Completer<void>();
}

enum PlaybackStatus { idle, playing, paused }

class PlaybackState {
  final PlaybackStatus status;
  final PlaybackItem? currentItem;
  final List<PlaybackItem> queue;

  const PlaybackState({
    this.status = PlaybackStatus.idle,
    this.currentItem,
    this.queue = const [],
  });

  PlaybackState copyWith({
    PlaybackStatus? status,
    PlaybackItem? Function()? currentItem,
    List<PlaybackItem>? queue,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      currentItem: currentItem != null ? currentItem() : this.currentItem,
      queue: queue ?? this.queue,
    );
  }

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isPaused => status == PlaybackStatus.paused;
  bool get isIdle => status == PlaybackStatus.idle;
}

class PlaybackService extends Notifier<PlaybackState> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  int _queueChangeCount = 0;
  bool _ownsPlaybackLock = false;

  @override
  PlaybackState build() {
    _player = ref.watch(audioPlayerProvider);
    _playerStateSub = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onItemFinished();
      }
    });

    // Listen to settings changes - stop playback when switching to silent mode
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.voiceMode != next.voiceMode) {
        _handleVoiceModeChanged(previous?.voiceMode, next.voiceMode);
      }
    });

    ref.onDispose(() {
      _playerStateSub?.cancel();
      // Provider handles AudioPlayer disposal
    });

    return const PlaybackState();
  }

  void _handleVoiceModeChanged(VoiceMode? oldMode, VoiceMode newMode) {
    debugPrint('PlaybackService: Voice mode changed from $oldMode to $newMode');

    // Stop all playback and clear queue when switching to silent mode
    if (newMode == VoiceMode.silent) {
      if (state.isPlaying || state.queue.isNotEmpty) {
        debugPrint(
          'PlaybackService: Stopping playback and clearing queue due to silent mode',
        );
        stop();
      }
    }
  }

  Future<void> enqueue(PlaybackItem item) async {
    _queueChangeCount++;
    final newQueue = List<PlaybackItem>.from(state.queue)..add(item);
    state = state.copyWith(queue: newQueue);

    if (state.status == PlaybackStatus.idle) {
      _processNext();
    }
  }

  Future<void> replaceQueue(List<PlaybackItem> items) async {
    _queueChangeCount++;
    await stop();

    _queueChangeCount++;

    state = state.copyWith(queue: items);
    _processNext();
  }

  Future<void> jumpQueue(PlaybackItem item) async {
    _queueChangeCount++;

    await _player.stop();

    _completeCurrentItem();

    final newQueue = List<PlaybackItem>.from(state.queue)..insert(0, item);
    state = state.copyWith(queue: newQueue);

    _processNext();
  }

  Future<void> stop() async {
    _queueChangeCount++;
    await _player.stop();

    if (_ownsPlaybackLock) {
      await ref.read(audioCoordinatorProvider.notifier).releasePlayback();
      _ownsPlaybackLock = false;
    }

    // Complete current item and all queued items
    _completeCurrentItem();
    _completeQueuedItems();

    state = const PlaybackState();
  }

  /// Pause the currently playing audio.
  ///
  /// CRITICAL INVARIANT: Pause does NOT release the playback lock.
  /// The lock represents ownership of the audio session, not playback state.
  /// Pausing is a local operation - we still own the session.
  /// See: AUDIO_ARCHITECTURE.md#pauseresume-semantics
  Future<void> pause() async {
    if (state.status != PlaybackStatus.playing) return;

    debugPrint('PlaybackProvider: Pausing playback');
    await _player.pause();
    state = state.copyWith(status: PlaybackStatus.paused);
    // Lock intentionally NOT released - we still own the audio session
  }

  Future<void> resume() async {
    if (state.status != PlaybackStatus.paused) return;

    debugPrint('PlaybackProvider: Resuming playback');
    state = state.copyWith(status: PlaybackStatus.playing);
    await _player.play();
  }

  void _completeQueuedItems() {
    // Complete all items in queue so TTS provider can reset their status
    for (final item in state.queue) {
      if (!item.onFinished.isCompleted) {
        item.onFinished.complete();
      }
    }
  }

  Future<void> _processNext() async {
    final initialVersion = _queueChangeCount;

    if (state.queue.isEmpty) {
      // currentItem already cleared in _finishAndNext, no state update needed
      // Only release the lock if we own it
      if (_ownsPlaybackLock) {
        await ref.read(audioCoordinatorProvider.notifier).releasePlayback();
        _ownsPlaybackLock = false;
      }
      return;
    }

    final nextItem = state.queue.first;

    Uint8List? data;
    try {
      data = await nextItem.content;
    } catch (e) {
      debugPrint(
        'PlaybackProvider: Error loading content for ${nextItem.id}: $e',
      );
    }

    // Check if provider is still mounted after async gap
    if (!ref.mounted) return;
    if (_queueChangeCount != initialVersion) return;
    if (state.queue.isEmpty || state.queue.first != nextItem) return;

    if (data == null || data.isEmpty) {
      _finishAndNext(nextItem);
      return;
    }

    if (nextItem.requiresLock) {
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestPlayback();

      // Check if provider is still mounted after async gap
      if (!ref.mounted) return;
      if (_queueChangeCount != initialVersion) return;
      if (state.queue.isEmpty || state.queue.first != nextItem) return;

      if (!granted) {
        // CRITICAL INVARIANT: Do not release the playback lock here!
        // We never acquired it, so we don't own it. Releasing would
        // interrupt the current playback holder.
        // See: AUDIO_ARCHITECTURE.md#lock-ownership
        //
        // Playback denied - remove item from queue without releasing lock
        // (something else is currently holding the playback lock)
        debugPrint(
          'PlaybackProvider: Playback denied for ${nextItem.id}, removing from queue',
        );
        _queueChangeCount++;

        if (!nextItem.onFinished.isCompleted) {
          nextItem.onFinished.complete();
        }

        final currentQueue = List<PlaybackItem>.from(state.queue);
        if (currentQueue.isNotEmpty && currentQueue.first == nextItem) {
          currentQueue.removeAt(0);
          state = state.copyWith(queue: currentQueue);
        }

        // Don't call releasePlayback() here - we don't own the lock!
        // Just process the next item in queue
        _processNext();
        return;
      }
      // Lock acquired successfully
      _ownsPlaybackLock = true;
      // No additional delay needed - AudioCoordinator now handles audio session reset
    }

    state = state.copyWith(
      status: PlaybackStatus.playing,
      currentItem: () => nextItem,
    );

    await _playItem(data);
  }

  Future<void> _playItem(Uint8List data) async {
    try {
      final source = InMemoryAudioSource(data);
      await _player.setAudioSource(source);
      _player.play().catchError((Object e) {
        debugPrint('PlaybackProvider: Play error: $e');
        _onItemFinished();
      });
    } catch (e) {
      debugPrint('PlaybackProvider: Setup error: $e');
      _onItemFinished();
    }
  }

  void _onItemFinished() {
    if (state.currentItem != null) {
      _finishAndNext(state.currentItem!);
    }
  }

  Future<void> _finishAndNext(PlaybackItem item) async {
    _queueChangeCount++;

    if (!item.onFinished.isCompleted) {
      item.onFinished.complete();
    }

    final currentQueue = List<PlaybackItem>.from(state.queue);
    if (currentQueue.isNotEmpty && currentQueue.first == item) {
      currentQueue.removeAt(0);
      // Clear currentItem atomically to trigger completion detection
      state = state.copyWith(
        queue: currentQueue,
        currentItem: () => null,
        status: PlaybackStatus.idle,
      );
    }

    // Release playback lock before processing next item
    // This ensures the lock is available for the next item to acquire
    if (currentQueue.isNotEmpty && _ownsPlaybackLock) {
      await ref.read(audioCoordinatorProvider.notifier).releasePlayback();
      // Check if provider is still mounted after async gap
      if (!ref.mounted) return;
      _ownsPlaybackLock = false;
    }

    _processNext();
  }

  void _completeCurrentItem() {
    if (state.currentItem != null &&
        !state.currentItem!.onFinished.isCompleted) {
      state.currentItem!.onFinished.complete();
    }
  }
}

final playbackProvider = NotifierProvider<PlaybackService, PlaybackState>(() {
  return PlaybackService();
});
