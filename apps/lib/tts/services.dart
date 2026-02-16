import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '/voice/voice_service.dart';

class TtsService {
  final VoiceService _voiceService;
  bool _isInitialized = false;
  final Map<String, Uint8List> _audioCache = {};

  // LRU cache management (max 20 messages)
  final int _maxCacheItems = 20;
  final List<String> _cacheOrder = [];

  // TTS generation settings
  int speakerId = 0;
  double speed = 1.0;

  TtsService(this._voiceService);

  Future<void> _init() async {
    if (!_isInitialized) {
      developer.Timeline.startSync('TTS_BackgroundInitialization');
      try {
        await _voiceService.initializeTts();
        _isInitialized = true;
        debugPrint('TTS initialized via VoiceService');
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

  /// Generate audio and return bytes
  Future<Uint8List?> generate(String text, String messageId) async {
    await _init();

    // Check cache first
    if (_audioCache.containsKey(messageId)) {
      debugPrint('TtsService [$messageId]: Returning cached audio');
      return _audioCache[messageId];
    }

    developer.Timeline.startSync(
      'TTS_Generation',
      arguments: {'text_length': text.length, 'message_id': messageId},
    );

    try {
      final wavBytes = await _voiceService.generateSpeech(
        text,
        messageId,
        speakerId: speakerId,
        speed: speed,
      );
      developer.Timeline.finishSync();

      if (wavBytes != null) {
        _addToCache(messageId, wavBytes);
        debugPrint('TtsService [$messageId]: Generated and cached');
      }
      return wavBytes;
    } catch (e) {
      developer.Timeline.finishSync();
      debugPrint('TtsService [$messageId]: Generation failed: $e');
      return null;
    }
  }

  /// Add audio to cache with LRU eviction
  void _addToCache(String messageId, Uint8List audio) {
    if (_cacheOrder.length >= _maxCacheItems) {
      final oldest = _cacheOrder.removeAt(0);
      _audioCache.remove(oldest);
      debugPrint('TTS cache evicted: $oldest');
    }

    _cacheOrder.remove(messageId);

    _cacheOrder.add(messageId);
    _audioCache[messageId] = audio;
  }

  void cleanup(Set<String> messageIdsToRemove) {
    for (final messageId in messageIdsToRemove) {
      _audioCache.remove(messageId);
      _cacheOrder.remove(messageId);
    }
  }

  Future<void> dispose() async {
    _audioCache.clear();
    _cacheOrder.clear();
    _voiceService.disposeTts();
  }
}
