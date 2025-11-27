import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/tts/audio_source.dart';
import '/tts/sherpa_tts.dart';

class TtsService {
  bool _isInitialized = false;
  sherpa_onnx.OfflineTts? _tts;
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Uint8List> _audioCache = {};

  final ValueChanged<String>? onPlaybackStarted;
  final ValueChanged<String>? onPlaybackFinished;
  final void Function(String messageId, String error)? onError;

  // TTS generation settings
  int speakerId = 0;
  double speed = 1.0;

  TtsService({this.onPlaybackStarted, this.onPlaybackFinished, this.onError});

  Future<void> _init() async {
    if (!_isInitialized) {
      try {
        sherpa_onnx.initBindings();
        _tts = await createOfflineTts();
        _isInitialized = true;
      } catch (e) {
        debugPrint('Failed to initialize TTS: $e');
        rethrow;
      }
    }
  }

  Future<bool> speak(String text, String messageId) async {
    await _init();

    try {
      // Stop any currently playing audio for this message
      await stop(messageId);

      // Generate audio if not already cached
      if (!_audioCache.containsKey(messageId)) {
        final audio = _tts!.generate(text: text, sid: speakerId, speed: speed);

        if (audio.samples.isEmpty) {
          debugPrint('Generated audio is empty');
          onError?.call(messageId, 'Failed to generate audio');
          return false;
        }

        // Convert to WAV bytes and cache in memory
        final wavBytes = generateWavBytes(audio);
        _audioCache[messageId] = wavBytes;
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

  void cleanup(Set<String> messageIdsToRemove) {
    for (final messageId in messageIdsToRemove) {
      // Dispose player
      final player = _players.remove(messageId);
      player?.dispose();

      // Remove audio from cache
      _audioCache.remove(messageId);
    }
  }

  Future<void> dispose() async {
    for (final player in _players.values) {
      await player.dispose();
    }
    _players.clear();

    // Clear audio cache
    _audioCache.clear();

    _tts?.free();
  }
}
