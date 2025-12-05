import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '/tts/audio_source.dart';
import '/tts/tts_isolate_worker.dart';

class TtsService {
  final TtsIsolateWorker _worker = TtsIsolateWorker();
  bool _isInitialized = false;
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Uint8List> _audioCache = {};

  // LRU cache management (max 20 messages)
  final int _maxCacheItems = 20;
  final List<String> _cacheOrder = [];

  final ValueChanged<String>? onPlaybackStarted;
  final ValueChanged<String>? onPlaybackFinished;
  final void Function(String messageId, String error)? onError;

  // TTS generation settings
  int speakerId = 0;
  double speed = 1.0;

  TtsService({this.onPlaybackStarted, this.onPlaybackFinished, this.onError});

  Future<void> _init() async {
    if (!_isInitialized) {
      developer.Timeline.startSync('TTS_BackgroundInitialization');
      try {
        // This now happens in a background isolate with BackgroundIsolateBinaryMessenger!
        await _worker.initialize();
        _isInitialized = true;
        debugPrint('TTS initialized in background isolate');
      } catch (e) {
        debugPrint('Failed to initialize TTS: $e');
        rethrow;
      } finally {
        developer.Timeline.finishSync();
      }
    }
  }

  /// Public method to pre-initialize TTS in background
  Future<void> initialize() async {
    await _init();
  }

  /// Pre-generate audio without playing (for eager generation)
  Future<bool> preGenerate(String text, String messageId) async {
    await _init();

    // Skip if already cached
    if (_audioCache.containsKey(messageId)) {
      debugPrint('TtsService [$messageId]: Already cached, skipping generation');
      return true;
    }

    developer.Timeline.startSync('TTS_PreGeneration', arguments: {
      'text_length': text.length,
      'message_id': messageId,
    });

    try {
      // Generate audio in background isolate
      final wavBytes = await _worker.generateAudio(
        text: text,
        messageId: messageId,
        speakerId: speakerId,
        speed: speed,
      );
      developer.Timeline.finishSync();

      // Add to cache with LRU eviction
      _addToCache(messageId, wavBytes);
      debugPrint('TtsService [$messageId]: Pre-generated and cached');
      return true;
    } catch (e) {
      developer.Timeline.finishSync();
      debugPrint('TtsService [$messageId]: Pre-generation failed: $e');
      onError?.call(messageId, 'Failed to generate audio: $e');
      return false;
    }
  }

  Future<bool> speak(String text, String messageId) async {
    await _init();

    try {
      // Stop any currently playing audio for this message
      await stop(messageId);

      // Generate audio if not already cached
      if (!_audioCache.containsKey(messageId)) {
        developer.Timeline.startSync('TTS_BackgroundGeneration', arguments: {
          'text_length': text.length,
          'message_id': messageId,
        });

        try {
          // This now happens in a background isolate - won't block the UI!
          final wavBytes = await _worker.generateAudio(
            text: text,
            messageId: messageId,
            speakerId: speakerId,
            speed: speed,
          );
          developer.Timeline.finishSync();

          // Add to cache with LRU eviction
          _addToCache(messageId, wavBytes);
        } catch (e) {
          developer.Timeline.finishSync();
          debugPrint('Failed to generate audio: $e');
          onError?.call(messageId, 'Failed to generate audio: $e');
          return false;
        }
      }

      // Create player and play
      await _playFromCache(messageId);
      return true;
    } catch (e) {
      debugPrint('Failed to speak: $e');
      onError?.call(messageId, 'Failed to play audio: $e');
      return false;
    }
  }

  Future<void> playFromCache(String messageId) async {
    if (_audioCache.containsKey(messageId)) {
      await _playFromCache(messageId);
    }
  }

  bool hasCache(String messageId) {
    return _audioCache.containsKey(messageId);
  }

  Future<void> _playFromCache(String messageId) async {
    final audioBytes = _audioCache[messageId];
    if (audioBytes == null) return;

    // Create player if doesn't exist
    if (!_players.containsKey(messageId)) {
      final player = AudioPlayer();
      _players[messageId] = player;

      bool hasNotifiedStart = false;

      player.playerStateStream.listen((state) {
        debugPrint('TtsService: Player state for $messageId: playing=${state.playing}, processingState=${state.processingState}');

        // Notify when playback actually starts
        if (state.playing && !hasNotifiedStart) {
          hasNotifiedStart = true;
          debugPrint('TtsService: Calling onPlaybackStarted for $messageId');
          onPlaybackStarted?.call(messageId);
        }

        // Reset flag when not playing
        if (!state.playing) {
          hasNotifiedStart = false;
        }

        // Notify when playback completes
        if (state.processingState == ProcessingState.completed) {
          debugPrint('TtsService: Calling onPlaybackFinished for $messageId');
          onPlaybackFinished?.call(messageId);
        }
      });
    }

    // Play the audio from memory
    final player = _players[messageId]!;
    final audioSource = InMemoryAudioSource(audioBytes);
    await player.setAudioSource(audioSource);
    await player.play();
  }

  Future<void> pause(String messageId) async {
    final player = _players[messageId];
    if (player != null) {
      await player.pause();
    }
  }

  Future<void> resume(String messageId) async {
    final player = _players[messageId];
    if (player != null) {
      await player.play();
    }
  }

  Future<void> stop(String messageId) async {
    final player = _players[messageId];
    if (player != null) {
      await player.stop();
    }
  }

  Future<void> stopAll() async {
    for (final player in _players.values) {
      await player.stop();
    }
  }

  /// Add audio to cache with LRU eviction
  void _addToCache(String messageId, Uint8List audio) {
    // Remove oldest item if cache is full
    if (_cacheOrder.length >= _maxCacheItems) {
      final oldest = _cacheOrder.removeAt(0);
      _audioCache.remove(oldest);
      debugPrint('TTS cache evicted: $oldest');
    }

    // Remove messageId if it already exists (to update position)
    _cacheOrder.remove(messageId);

    // Add to end (most recently used)
    _cacheOrder.add(messageId);
    _audioCache[messageId] = audio;
  }

  void cleanup(Set<String> messageIdsToRemove) {
    for (final messageId in messageIdsToRemove) {
      // Dispose player
      final player = _players.remove(messageId);
      player?.dispose();

      // Remove audio from cache and order tracking
      _audioCache.remove(messageId);
      _cacheOrder.remove(messageId);
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();

    // Clear audio cache
    _audioCache.clear();
    _cacheOrder.clear();

    // Dispose the background worker isolate
    _worker.dispose();
  }
}
