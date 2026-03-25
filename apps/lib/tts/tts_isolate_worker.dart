import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/models/model_catalog.dart';
import '/tts/audio_source.dart';
import '/utils/logger.dart';
import '/voice/model_resolver.dart';

/// Task data passed to the isolate on spawn
class _IsolateTask {
  final SendPort sendPort;
  final RootIsolateToken rootIsolateToken;

  _IsolateTask(this.sendPort, this.rootIsolateToken);
}

/// Messages sent to the TTS worker isolate
sealed class TtsWorkerMessage {}

class InitializeTtsMessage extends TtsWorkerMessage {
  final SendPort responsePort;
  final String modelName;

  /// If non-null, use resolved downloaded model instead of bundled assets.
  final ResolvedTtsModel? resolvedModel;

  /// Absolute path to a reference WAV file for voice-cloning models (Pocket TTS).
  /// When set the isolate loads the audio after bindings are initialized and
  /// uses [sherpa_onnx.OfflineTts.generateWithConfig] for generation.
  final String? referenceWavPath;

  InitializeTtsMessage(
    this.responsePort,
    this.modelName, {
    this.resolvedModel,
    this.referenceWavPath,
  });
}

class GenerateAudioMessage extends TtsWorkerMessage {
  final String text;
  final String messageId;
  final int speakerId;
  final double speed;
  final SendPort responsePort;
  GenerateAudioMessage({
    required this.text,
    required this.messageId,
    required this.speakerId,
    required this.speed,
    required this.responsePort,
  });
}

class DisposeTtsMessage extends TtsWorkerMessage {}

/// Responses from the TTS worker isolate
sealed class TtsWorkerResponse {}

class InitializedResponse extends TtsWorkerResponse {}

class AudioGeneratedResponse extends TtsWorkerResponse {
  final Uint8List audioData;
  AudioGeneratedResponse(this.audioData);
}

class ErrorResponse extends TtsWorkerResponse {
  final String error;
  ErrorResponse(this.error);
}

/// Build TTS config from resolved absolute paths (no ModelLoader needed).
sherpa_onnx.OfflineTtsModelConfig _buildConfigFromResolvedPaths(
  ResolvedTtsModel resolved,
) {
  final paths = resolved.resolvedPaths;

  switch (resolved.architecture) {
    case ModelArchitecture.kokoro:
      return sherpa_onnx.OfflineTtsModelConfig(
        kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
          model: paths['model']!,
          voices: paths['voices']!,
          tokens: paths['tokens']!,
          dataDir: paths['dataDir']!,
          // Multilingual Kokoro v1.0+ requires a lexicon file.
          lexicon: paths['lexicon'] ?? '',
        ),
        numThreads: 2,
        debug: false,
      );

    case ModelArchitecture.vitsPiper:
      return sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: paths['model']!,
          tokens: paths['tokens']!,
          dataDir: paths['dataDir']!,
        ),
        numThreads: 2,
        debug: false,
      );

    case ModelArchitecture.pocket:
      return sherpa_onnx.OfflineTtsModelConfig(
        pocket: sherpa_onnx.OfflineTtsPocketModelConfig(
          lmFlow: paths['lmFlow']!,
          lmMain: paths['lmMain']!,
          encoder: paths['encoder']!,
          decoder: paths['decoder']!,
          textConditioner: paths['textConditioner']!,
          vocabJson: paths['vocabJson']!,
          tokenScoresJson: paths['tokenScoresJson']!,
        ),
        numThreads: 2,
        debug: false,
      );

    default:
      throw ArgumentError(
        'Unsupported TTS architecture: ${resolved.architecture}',
      );
  }
}

/// Worker isolate entry point
void _ttsWorkerIsolate(_IsolateTask task) {
  // CRITICAL: Initialize binary messenger to access Flutter platform channels and file system
  BackgroundIsolateBinaryMessenger.ensureInitialized(task.rootIsolateToken);

  final receivePort = ReceivePort();
  task.sendPort.send(receivePort.sendPort);

  sherpa_onnx.OfflineTts? tts;
  bool isInitialized = false;
  String? modelName;
  // Reference audio for voice-cloning models (Pocket TTS).
  Float32List? referenceAudio;
  int referenceSampleRate = 0;

  receivePort.listen((message) async {
    try {
      switch (message) {
        case InitializeTtsMessage():
          if (!isInitialized) {
            try {
              final totalStopwatch = Stopwatch()..start();

              modelName = message.modelName;
              Logger.debug('[TTS Worker] Received TTS model name: $modelName');

              final bindingsStopwatch = Stopwatch()..start();
              Logger.debug('[TTS Worker] Initializing Sherpa-ONNX bindings...');
              sherpa_onnx.initBindings();
              bindingsStopwatch.stop();
              Logger.debug(
                '[TTS Worker] Sherpa-ONNX bindings initialized (${bindingsStopwatch.elapsedMilliseconds}ms)',
              );

              // Load reference audio for voice-cloning models after bindings
              // are initialized so readWave() can use the native library.
              if (message.referenceWavPath != null) {
                final wave = sherpa_onnx.readWave(message.referenceWavPath!);
                referenceAudio = wave.samples;
                referenceSampleRate = wave.sampleRate;
                Logger.debug(
                  '[TTS Worker] Loaded reference audio: ${wave.samples.length} samples @ ${wave.sampleRate} Hz',
                );
              }

              final modelStopwatch = Stopwatch()..start();
              Logger.debug('[TTS Worker] Creating TTS model...');

              if (message.resolvedModel == null) {
                throw Exception('No resolved TTS model provided');
              }
              Logger.debug(
                '[TTS Worker] Using resolved paths: ${message.resolvedModel!.resolvedPaths}',
              );
              final modelConfig = _buildConfigFromResolvedPaths(
                message.resolvedModel!,
              );
              final config = sherpa_onnx.OfflineTtsConfig(
                model: modelConfig,
                ruleFsts: '',
                maxNumSenetences: 1,
              );
              tts = sherpa_onnx.OfflineTts(config);

              modelStopwatch.stop();
              Logger.debug(
                '[TTS Worker] TTS model created (${(modelStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)',
              );

              totalStopwatch.stop();
              isInitialized = true;
              Logger.debug(
                '[TTS Worker] Initialization complete (Total: ${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)',
              );
              message.responsePort.send(InitializedResponse());
            } catch (e, stackTrace) {
              Logger.debug('[TTS Worker] Initialization failed: $e');
              Logger.debug('[TTS Worker] Stack trace: $stackTrace');
              message.responsePort.send(
                ErrorResponse('Initialization failed: $e'),
              );
            }
          } else {
            message.responsePort.send(InitializedResponse());
          }

        case GenerateAudioMessage():
          if (!isInitialized || tts == null) {
            message.responsePort.send(ErrorResponse('TTS not initialized'));
            return;
          }

          final totalStopwatch = Stopwatch()..start();
          Logger.debug(
            '[TTS Worker] Generating audio for [${message.messageId}] '
            'using $modelName (${message.text.length} chars)...',
          );

          final generateStopwatch = Stopwatch()..start();
          // Voice-cloning models (Pocket TTS) require generateWithConfig with
          // a reference audio; standard models use the simpler generate() API.
          final audio = referenceAudio != null
              ? tts!.generateWithConfig(
                  text: message.text,
                  config: sherpa_onnx.OfflineTtsGenerationConfig(
                    referenceAudio: referenceAudio,
                    referenceSampleRate: referenceSampleRate,
                    speed: message.speed,
                    sid: message.speakerId,
                  ),
                )
              : tts!.generate(
                  text: message.text,
                  sid: message.speakerId,
                  speed: message.speed,
                );
          generateStopwatch.stop();

          if (audio.samples.isEmpty) {
            message.responsePort.send(
              ErrorResponse('Generated audio is empty'),
            );
            return;
          }

          final convertStopwatch = Stopwatch()..start();
          final wavBytes = generateWavBytes(audio);
          convertStopwatch.stop();

          totalStopwatch.stop();
          final audioDuration = audio.samples.length / audio.sampleRate;
          final rtf =
              (totalStopwatch.elapsedMilliseconds / 1000) / audioDuration;

          Logger.debug(
            '[TTS Worker] Audio generated for [${message.messageId}]:',
          );
          Logger.debug(
            '  - Generate: ${(generateStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s',
          );
          Logger.debug(
            '  - Convert to WAV: ${convertStopwatch.elapsedMilliseconds}ms',
          );
          Logger.debug(
            '  - Total: ${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s',
          );
          Logger.debug(
            '  - Audio duration: ${audioDuration.toStringAsFixed(2)}s',
          );
          Logger.debug(
            '  - RTF (Real-time Factor): ${rtf.toStringAsFixed(3)}x',
          );
          Logger.debug(
            '  - Output size: ${(wavBytes.length / 1024).toStringAsFixed(1)} KB',
          );

          message.responsePort.send(AudioGeneratedResponse(wavBytes));

        case DisposeTtsMessage():
          Logger.debug('[TTS Worker] Disposing TTS');
          tts?.free();
          tts = null;
          isInitialized = false;
          receivePort.close();
      }
    } catch (e, stackTrace) {
      Logger.debug('[TTS Worker] Error: $e\n$stackTrace');
      if (message is InitializeTtsMessage) {
        message.responsePort.send(ErrorResponse('Initialization failed: $e'));
      } else if (message is GenerateAudioMessage) {
        message.responsePort.send(ErrorResponse('Generation failed: $e'));
      }
    }
  });
}

/// Manager for the TTS worker isolate
class TtsIsolateWorker {
  Isolate? _isolate;
  SendPort? _workerSendPort;
  bool _isInitialized = false;

  /// Initialize the worker isolate and load TTS model.
  /// Pass [resolvedModel] to use a downloaded model instead of bundled assets.
  Future<void> initialize({required ResolvedTtsModel resolvedModel}) async {
    if (_isInitialized) return;

    // Pocket TTS (voice cloning) uses a reference WAV bundled with the model.
    final referenceWavPath = resolvedModel.resolvedPaths['referenceWav'];

    Logger.debug('[TTS Manager] Spawning worker isolate...');
    final receivePort = ReceivePort();

    // Get the root isolate token to pass to the background isolate
    final rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      throw Exception(
        'RootIsolateToken is null - ensure this is called from main isolate',
      );
    }

    _isolate = await Isolate.spawn(
      _ttsWorkerIsolate,
      _IsolateTask(receivePort.sendPort, rootIsolateToken),
      errorsAreFatal: false, // Prevent isolate crashes from taking down the app
    );

    // Get the worker's SendPort
    _workerSendPort = await receivePort.first as SendPort;
    Logger.debug('[TTS Manager] Worker isolate spawned');

    // Initialize TTS in the worker
    final initResponsePort = ReceivePort();
    _workerSendPort!.send(
      InitializeTtsMessage(
        initResponsePort.sendPort,
        'downloaded:${resolvedModel.modelId}',
        resolvedModel: resolvedModel,
        referenceWavPath: referenceWavPath,
      ),
    );

    final response = await initResponsePort.first;
    initResponsePort.close();

    if (response is ErrorResponse) {
      throw Exception('Failed to initialize TTS: ${response.error}');
    }

    _isInitialized = true;
    Logger.debug('[TTS Manager] TTS initialized in background');
  }

  /// Generate audio in the background isolate
  Future<Uint8List> generateAudio({
    required String text,
    required String messageId,
    required int speakerId,
    required double speed,
  }) async {
    if (!_isInitialized || _workerSendPort == null) {
      throw Exception('TTS worker not initialized');
    }

    final responsePort = ReceivePort();
    _workerSendPort!.send(
      GenerateAudioMessage(
        text: text,
        messageId: messageId,
        speakerId: speakerId,
        speed: speed,
        responsePort: responsePort.sendPort,
      ),
    );

    final response = await responsePort.first;
    responsePort.close();

    return switch (response) {
      AudioGeneratedResponse() => response.audioData,
      ErrorResponse() => throw Exception(response.error),
      _ => throw Exception('Unexpected response type'),
    };
  }

  /// Dispose the worker isolate
  void dispose() {
    if (_workerSendPort != null) {
      _workerSendPort!.send(DisposeTtsMessage());
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerSendPort = null;
    _isInitialized = false;
  }
}
