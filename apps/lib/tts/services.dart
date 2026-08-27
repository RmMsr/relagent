import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '/utils/logger.dart';
import '/voice/model_resolver.dart';
import '/voice/voice_service.dart';

class TtsService {
  final VoiceService _voiceService;
  final Map<String, Uint8List> _audioCache = {};

  // LRU cache management (max 60 chunks, since cache keys are now
  // per-chunk rather than per-message)
  final int _maxCacheItems = 60;
  final List<String> _cacheOrder = [];

  // TTS generation settings
  int speakerId = 0;
  double speed = 1.0;

  /// Model to pre-warm on [initialize] and to use for [generate] calls that
  /// don't pass their own model (the app's single "selected" TTS model).
  /// Per-call callers that resolve a per-message/per-language model instead
  /// pass it directly to [generate].
  ResolvedTtsModel? resolvedTtsModel;

  TtsService(this._voiceService);

  /// Pre-warm the engine pool with [resolvedTtsModel] so the first
  /// [generate] call doesn't pay the pool-miss cost.
  Future<void> initialize() async {
    if (resolvedTtsModel == null) {
      // Nothing resolved yet — e.g. a model is selected but settings or
      // the downloaded-models scan hadn't finished loading the moment this
      // was first called. Nothing to pre-warm; generate() resolves lazily
      // per call regardless.
      return;
    }
    developer.Timeline.startSync('TTS_BackgroundInitialization');
    try {
      await _voiceService.initializeTts(resolvedTtsModel: resolvedTtsModel);
      Logger.debug('TTS pre-warmed via VoiceService');
    } catch (e) {
      Logger.error('Failed to pre-warm TTS: $e');
      rethrow;
    } finally {
      developer.Timeline.finishSync();
    }
  }

  /// Updates the model used to pre-warm and for calls without their own
  /// model, and pre-warms it. Does not evict other pooled models.
  Future<void> reinitializeWithModel(ResolvedTtsModel? model) async {
    resolvedTtsModel = model;
    _audioCache.clear();
    _cacheOrder.clear();
    await initialize();
  }

  /// Generate audio and return bytes, using [model] (falling back to
  /// [resolvedTtsModel] when omitted).
  Future<Uint8List?> generate(
    String text,
    String messageId, {
    ResolvedTtsModel? model,
  }) async {
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
        resolvedTtsModel: model ?? resolvedTtsModel,
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
