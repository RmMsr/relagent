import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../tts/audio_source.dart';
import 'audio_coordinator_provider.dart';

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

enum PlaybackStatus { idle, playing }

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
  bool get isIdle => status == PlaybackStatus.idle;
}

class PlaybackService extends Notifier<PlaybackState> {
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  int _queueChangeCount = 0;

  @override
  PlaybackState build() {
    _player = AudioPlayer();
    _playerStateSub = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onItemFinished();
      }
    });

    ref.onDispose(() {
      _playerStateSub?.cancel();
      _player.dispose();
    });

    return const PlaybackState();
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

    await ref
        .read(audioCoordinatorProvider.notifier)
        .releasePlayback(autoResume: true);

    _completeCurrentItem();

    state = const PlaybackState();
  }

  Future<void> _processNext() async {
    final initialVersion = _queueChangeCount;

    if (state.queue.isEmpty) {
      // currentItem already cleared in _finishAndNext, no state update needed
      await ref
          .read(audioCoordinatorProvider.notifier)
          .releasePlayback(autoResume: true);
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

      if (_queueChangeCount != initialVersion) return;
      if (state.queue.isEmpty || state.queue.first != nextItem) return;

      if (!granted) {
        _finishAndNext(nextItem);
        return;
      }
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
    if (currentQueue.isNotEmpty) {
      await ref
          .read(audioCoordinatorProvider.notifier)
          .releasePlayback(autoResume: false);
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
