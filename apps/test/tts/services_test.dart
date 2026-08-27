import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/model_catalog.dart';
import 'package:relagent/tts/services.dart';
import 'package:relagent/voice/model_resolver.dart';
import 'package:relagent/voice/voice_service_stub.dart';

/// Records the model passed to each call so tests can assert TtsService
/// forwards the right one, without touching real sherpa-onnx/isolates.
class _RecordingVoiceService extends NoOpVoiceService {
  int initializeCallCount = 0;
  final List<ResolvedTtsModel?> generateCalls = [];

  @override
  Future<void> initializeTts({ResolvedTtsModel? resolvedTtsModel}) async {
    initializeCallCount++;
  }

  @override
  Future<Uint8List?> generateSpeech(
    String text,
    String messageId, {
    ResolvedTtsModel? resolvedTtsModel,
    int speakerId = 0,
    double speed = 1.0,
  }) async {
    generateCalls.add(resolvedTtsModel);
    if (resolvedTtsModel == null) return null;
    return Uint8List.fromList([1, 2, 3]);
  }
}

const _modelA = ResolvedTtsModel(
  modelId: 'model-a',
  architecture: ModelArchitecture.vitsPiper,
  resolvedPaths: {},
);

const _modelB = ResolvedTtsModel(
  modelId: 'model-b',
  architecture: ModelArchitecture.kokoro,
  resolvedPaths: {},
);

void main() {
  group('TtsService', () {
    test(
      'generate with no model at all and no resolvedTtsModel set returns null',
      () async {
        final voiceService = _RecordingVoiceService();
        final service = TtsService(voiceService);

        final result = await service.generate('hello', 'msg#0');

        expect(result, isNull);
        expect(voiceService.generateCalls, [null]);
      },
    );

    test('generate passes the per-call model through, ignoring any '
        'previously-resolved default', () async {
      final voiceService = _RecordingVoiceService();
      final service = TtsService(voiceService)..resolvedTtsModel = _modelA;

      final result = await service.generate('hello', 'msg#0', model: _modelB);

      expect(result, isNotNull);
      expect(voiceService.generateCalls, [_modelB]);
    });

    test(
      'generate without a per-call model falls back to resolvedTtsModel',
      () async {
        final voiceService = _RecordingVoiceService();
        final service = TtsService(voiceService)..resolvedTtsModel = _modelA;

        await service.generate('hello', 'msg#0');

        expect(voiceService.generateCalls, [_modelA]);
      },
    );

    test('initialize pre-warms with resolvedTtsModel', () async {
      final voiceService = _RecordingVoiceService();
      final service = TtsService(voiceService)..resolvedTtsModel = _modelA;

      await service.initialize();

      expect(voiceService.initializeCallCount, 1);
    });

    test('initialize is a no-op when resolvedTtsModel is unset', () async {
      final voiceService = _RecordingVoiceService();
      final service = TtsService(voiceService);

      await service.initialize();

      expect(voiceService.initializeCallCount, 0);
    });

    test(
      'reinitializeWithModel updates resolvedTtsModel and pre-warms it',
      () async {
        final voiceService = _RecordingVoiceService();
        final service = TtsService(voiceService);

        await service.reinitializeWithModel(_modelB);

        expect(service.resolvedTtsModel, _modelB);
        expect(voiceService.initializeCallCount, 1);
      },
    );

    test('a second call with the same messageId returns cached audio '
        'without calling generateSpeech again', () async {
      final voiceService = _RecordingVoiceService();
      final service = TtsService(voiceService);

      await service.generate('hello', 'msg#0', model: _modelA);
      await service.generate('hello', 'msg#0', model: _modelA);

      expect(voiceService.generateCalls, [_modelA]);
    });
  });
}
