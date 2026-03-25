import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/model_download_provider.dart';
import '/providers/playback_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/tts/services.dart';
import '/utils/logger.dart';
import '/voice/model_resolver.dart';

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

  const MessageTtsState({this.status = MessagePlaybackStatus.idle, this.error});

  MessageTtsState copyWith({
    MessagePlaybackStatus? status,
    String? Function()? error,
  }) {
    return MessageTtsState(
      status: status ?? this.status,
      error: error != null ? error() : this.error,
    );
  }

  bool get isPlaying => status == MessagePlaybackStatus.playing;
  bool get isGenerating => status == MessagePlaybackStatus.generating;
}

class TtsState {
  final Map<String, MessageTtsState> messageStates;

  const TtsState({this.messageStates = const {}});

  factory TtsState.initial() => const TtsState();

  TtsState copyWith({Map<String, MessageTtsState>? messageStates}) {
    return TtsState(messageStates: messageStates ?? this.messageStates);
  }

  MessageTtsState getMessageState(String messageId) {
    return messageStates[messageId] ?? const MessageTtsState();
  }
}

final ttsProvider = NotifierProvider<TtsNotifier, TtsState>(() {
  return TtsNotifier();
});

class TtsNotifier extends Notifier<TtsState> {
  TtsService? _service;

  // Track tasks to avoid overlapping generation for same message
  final Map<String, Future<void>> _pendingTasks = {};

  // Deferred reinit: true when model became available while generation was busy
  bool _pendingReinit = false;

  @override
  TtsState build() {
    ref.onDispose(() {
      _service?.dispose();
    });

    // Listen to settings changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.ttsSpeakerId != next.ttsSpeakerId ||
          previous?.ttsSpeed != next.ttsSpeed) {
        _handleSettingsChanged(next);
      }
      // Reinitialize TTS when model selection changes
      if (previous?.selectedTtsModelId != next.selectedTtsModelId) {
        _handleTtsModelChanged();
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
          _handleTtsModelChanged();
        } else {
          _pendingReinit = true;
        }
      }
    });

    return TtsState.initial();
  }

  Future<void> initialize() async {
    final service = await _getService();
    await service.initialize();
  }

  Future<TtsService> _getService() async {
    if (_service == null) {
      final settings = ref.read(settingsProvider);
      final downloadState = ref.read(modelDownloadProvider);
      final voiceService = ref.read(voiceServiceProvider);
      final resolved = await resolveTtsModel(settings, downloadState);
      _service = TtsService(voiceService)
        ..speakerId = settings.ttsSpeakerId
        ..speed = settings.ttsSpeed
        ..resolvedTtsModel = resolved;
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

  Future<void> _handleTtsModelChanged() async {
    if (_service == null) return;
    final settings = ref.read(settingsProvider);
    final downloadState = ref.read(modelDownloadProvider);
    final resolved = await resolveTtsModel(settings, downloadState);
    Logger.debug('TtsProvider: TTS model changed, reinitializing...');
    await _service!.reinitializeWithModel(resolved);
  }

  void onChatCleared() {
    ref.read(playbackProvider.notifier).stop();
    state = TtsState.initial();
    // Clear pending generation tasks to prevent stale completions
    _pendingTasks.clear();
  }

  /// Play a message immediately (user clicked play button)
  /// Stops current playback and plays this message
  Future<void> playNow(String text, String messageId) async {
    if (_pendingTasks.containsKey(messageId)) return;

    // Start generation immediately
    final service = await _getService();
    _updateMessageState(messageId, status: MessagePlaybackStatus.generating);

    // Create a shared future for the content
    final contentFuture = service.generate(text, messageId).then((bytes) {
      if (bytes == null) {
        throw Exception('Generation failed');
      }
      return bytes;
    });

    final task = Future<void>(() async {
      try {
        final playbackItem = PlaybackItem(
          id: messageId,
          content: contentFuture,
        );
        await ref.read(playbackProvider.notifier).jumpQueue(playbackItem);
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
  /// 1. Trigger generation (async)
  /// 2. Enqueue directly to PlaybackService
  Future<void> enqueue(String text, String messageId) async {
    if (_pendingTasks.containsKey(messageId)) return;

    // Start generation immediately
    final service = await _getService();
    _updateMessageState(messageId, status: MessagePlaybackStatus.generating);

    // Create a shared future for the content
    final contentFuture = service.generate(text, messageId).then((bytes) {
      if (bytes == null) {
        throw Exception('Generation failed');
      }
      return bytes;
    });

    // We wrap the enqueue in a pending task to prevent duplicates
    // But we don't await the playback itself here, just the enqueueing
    final task = Future<void>(() async {
      try {
        final playbackItem = PlaybackItem(
          id: messageId,
          content: contentFuture,
        );
        await ref.read(playbackProvider.notifier).enqueue(playbackItem);
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

  void _handlePlaybackStateChange(PlaybackState? prev, PlaybackState next) {
    // Handle completion FIRST (transition from playing to idle/next)
    if (prev?.currentItem != null) {
      final prevId = prev!.currentItem!.id;
      final nextId = next.currentItem?.id;

      // Item is completed if it changed (new item started or became null)
      if (prevId != nextId) {
        _updateMessageState(prevId, status: MessagePlaybackStatus.completed);
      }
    }

    // Update playing/paused status of current item
    if (next.currentItem != null) {
      final messageId = next.currentItem!.id;
      if (next.isPlaying) {
        _updateMessageState(messageId, status: MessagePlaybackStatus.playing);
      } else if (next.isPaused) {
        _updateMessageState(messageId, status: MessagePlaybackStatus.paused);
      }
    }

    // Handle queue clearing - reset all items that were in queue but are gone
    if (prev != null && prev.queue.isNotEmpty && next.queue.isEmpty) {
      Logger.debug(
        'TtsProvider: Playback queue cleared, resetting ${prev.queue.length} pending items',
      );
      for (final item in prev.queue) {
        final messageState = state.getMessageState(item.id);
        // Reset to idle if it was generating (waiting in queue)
        if (messageState.isGenerating) {
          _updateMessageState(item.id, status: MessagePlaybackStatus.idle);
        }
      }
    }
  }

  void _updateMessageState(
    String messageId, {
    MessagePlaybackStatus? status,
    String? error,
  }) {
    final currentState = state.getMessageState(messageId);
    final newMessageState = currentState.copyWith(
      status: status,
      error: error != null ? () => error : null,
    );

    final newStates = Map<String, MessageTtsState>.from(state.messageStates);
    newStates[messageId] = newMessageState;
    state = state.copyWith(messageStates: newStates);
  }
}
