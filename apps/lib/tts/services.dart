import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '/utils/logger.dart';
import '/voice/model_resolver.dart';
import '/voice/voice_service.dart';

class TtsService {
  final VoiceService _voiceService;
  bool _isInitialized = false;
  final Map<String, Uint8List> _audioCache = {};

  // LRU cache management (max 60 chunks, since cache keys are now
  // per-chunk rather than per-message)
  final int _maxCacheItems = 60;
  final List<String> _cacheOrder = [];

  // TTS generation settings
  int speakerId = 0;
  double speed = 1.0;

  /// Resolved TTS model for downloaded models (null = bundled).
  ResolvedTtsModel? resolvedTtsModel;

  TtsService(this._voiceService);

  Future<void> _init() async {
    if (_isInitialized) return;
    if (resolvedTtsModel == null) {
      // Nothing resolved yet — e.g. a model is selected but settings or
      // the downloaded-models scan hadn't finished loading the moment this
      // was first called. NativeVoiceService.initializeTts(null) is a
      // legitimate no-op (genuinely "no model"), not a failure, so it
      // won't throw here — but treating that no-op as a real success would
      // leave _isInitialized stuck true forever with nothing actually
      // initialized. Stay uninitialized instead, so the next call (once
      // TtsNotifier._getService has re-resolved resolvedTtsModel) retries
      // for real instead of silently no-op'ing again.
      return;
    }
    developer.Timeline.startSync('TTS_BackgroundInitialization');
    try {
      await _voiceService.initializeTts(resolvedTtsModel: resolvedTtsModel);
      _isInitialized = true;
      Logger.debug('TTS initialized via VoiceService');
    } catch (e) {
      Logger.error('Failed to initialize TTS: $e');
      rethrow;
    } finally {
      developer.Timeline.finishSync();
    }
  }

  /// Public method to pre-initialize TTS in background
  Future<void> initialize() async {
    await _init();
  }

  /// Reinitialize with a different model (disposes current, loads new).
  Future<void> reinitializeWithModel(ResolvedTtsModel? model) async {
    if (_isInitialized) {
      _voiceService.disposeTts();
      _isInitialized = false;
      _audioCache.clear();
      _cacheOrder.clear();
    }
    resolvedTtsModel = model;
    await _init();
  }

  /// Generate audio and return bytes
  Future<Uint8List?> generate(String text, String messageId) async {
    await _init();

    // Check cache first
    if (_audioCache.containsKey(messageId)) {
      Logger.debug('TtsService [$messageId]: Returning cached audio');
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
        Logger.debug('TtsService [$messageId]: Generated and cached');
      }
      return wavBytes;
    } catch (e) {
      developer.Timeline.finishSync();
      Logger.debug('TtsService [$messageId]: Generation failed: $e');
      return null;
    }
  }

  /// Add audio to cache with LRU eviction
  void _addToCache(String messageId, Uint8List audio) {
    if (_cacheOrder.length >= _maxCacheItems) {
      final oldest = _cacheOrder.removeAt(0);
      _audioCache.remove(oldest);
      Logger.debug('TTS cache evicted: $oldest');
    }

    _cacheOrder.remove(messageId);

    _cacheOrder.add(messageId);
    _audioCache[messageId] = audio;
  }

  void clearCache() {
    _audioCache.clear();
    _cacheOrder.clear();
  }

  void cleanup(Set<String> messageIdsToRemove) {
    final keysToRemove = _cacheOrder
        .where((key) => messageIdsToRemove.any((id) => key.startsWith('$id#')))
        .toList();
    for (final key in keysToRemove) {
      _audioCache.remove(key);
      _cacheOrder.remove(key);
    }
  }

  Future<void> dispose() async {
    _audioCache.clear();
    _cacheOrder.clear();
    _voiceService.disposeTts();
  }
}
