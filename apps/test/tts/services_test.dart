import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/tts/services.dart';
import 'package:relagent/voice/model_resolver.dart';
import 'package:relagent/voice/voice_service_stub.dart';

/// Tracks calls so tests can tell whether TtsService actually reached the
/// underlying VoiceService again on a retry, versus believing it was
/// already initialized.
class _TrackingVoiceService extends NoOpVoiceService {
  int initializeCallCount = 0;
  bool initialized = false;

  @override
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel}) async {
    initializeCallCount++;
    // Mirrors NativeVoiceService.initializeTts: a null model is a
    // legitimate no-op, not a failure — it doesn't throw.
    if (resolvedTtsModel != null) {
      initialized = true;
    }
  }

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    if (!initialized) return null;
    return Uint8List.fromList([1, 2, 3]);
  }
}

const _testModel = ResolvedTtsModel(
  modelId: 'test-model',
  architecture: ModelArchitecture.vitsPiper,
  resolvedPaths: {},
);

void main() {
  group('TtsService', () {
    test('a null resolvedTtsModel does not permanently stick the service as '
        'initialized — a later call after it resolves succeeds without '
        'needing an explicit reinitializeWithModel', () async {
      final voiceService = _TrackingVoiceService();
      final service = TtsService(voiceService);
      // resolvedTtsModel starts null: e.g. a model is selected, but
      // settings or the downloaded-models scan hadn't finished loading the
      // moment this first ran.
      expect(service.resolvedTtsModel, isNull);

      final firstResult = await service.generate('hello', 'msg#0');
      expect(firstResult, isNull);
      // Nothing to initialize with, so the underlying VoiceService isn't
      // even called — the bug this guards against is _isInitialized
      // getting stuck true from a call that reported success without
      // resolvedTtsModel, not this call itself failing.
      expect(voiceService.initializeCallCount, 0);
      expect(voiceService.initialized, isFalse);

      // TtsNotifier._getService() would re-resolve and set this once the
      // race has settled — no dispose/reinitializeWithModel involved.
      service.resolvedTtsModel = _testModel;

      final secondResult = await service.generate('hello again', 'msg#1');
      expect(secondResult, isNotNull);
      expect(voiceService.initializeCallCount, 1);
      expect(voiceService.initialized, isTrue);
    });

    test('a resolved model initializes normally on the first call', () async {
      final voiceService = _TrackingVoiceService();
      final service = TtsService(voiceService)..resolvedTtsModel = _testModel;

      final result = await service.generate('hello', 'msg#0');

      expect(result, isNotNull);
      expect(voiceService.initializeCallCount, 1);
    });

    test('a second call with the same resolved model does not '
        're-initialize', () async {
      final voiceService = _TrackingVoiceService();
      final service = TtsService(voiceService)..resolvedTtsModel = _testModel;

      await service.generate('hello', 'msg#0');
      await service.generate('world', 'msg#1');

      expect(voiceService.initializeCallCount, 1);
    });
  });
}
