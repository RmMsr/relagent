import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/config/app_config.dart'; // Only used by TtsIsolateWorker (main isolate)
import '/tts/audio_source.dart';
import '/tts/sherpa_tts.dart';

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
  InitializeTtsMessage(this.responsePort, this.modelName);
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

/// Worker isolate entry point
void _ttsWorkerIsolate(_IsolateTask task) {
  // CRITICAL: Initialize binary messenger to access Flutter platform channels and file system
  BackgroundIsolateBinaryMessenger.ensureInitialized(task.rootIsolateToken);

  final receivePort = ReceivePort();
  task.sendPort.send(receivePort.sendPort);

  sherpa_onnx.OfflineTts? tts;
  bool isInitialized = false;
  String? modelName;

  receivePort.listen((message) async {
    try {
      switch (message) {
        case InitializeTtsMessage():
          if (!isInitialized) {
            try {
              final totalStopwatch = Stopwatch()..start();

              modelName = message.modelName;
              debugPrint('[TTS Worker] Received TTS model name: $modelName');

              final bindingsStopwatch = Stopwatch()..start();
              debugPrint('[TTS Worker] Initializing Sherpa-ONNX bindings...');
              sherpa_onnx.initBindings();
              bindingsStopwatch.stop();
              debugPrint('[TTS Worker] ✓ Sherpa-ONNX bindings initialized (${bindingsStopwatch.elapsedMilliseconds}ms)');

              final modelStopwatch = Stopwatch()..start();
              debugPrint('[TTS Worker] Creating TTS model...');
              // BackgroundIsolateBinaryMessenger allows file system access for asset copying
              tts = await createOfflineTts(modelName: modelName);
              modelStopwatch.stop();
              debugPrint('[TTS Worker] ✓ TTS model created (${(modelStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');

              totalStopwatch.stop();
              isInitialized = true;
              debugPrint('[TTS Worker] ✓ Initialization complete (Total: ${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');
              message.responsePort.send(InitializedResponse());
            } catch (e, stackTrace) {
              debugPrint('[TTS Worker] ✗ Initialization failed: $e');
              debugPrint('[TTS Worker] Stack trace: $stackTrace');
              message.responsePort.send(ErrorResponse('Initialization failed: $e'));
            }
          } else {
            message.responsePort.send(InitializedResponse());
          }

        case GenerateAudioMessage():
          if (!isInitialized || tts == null) {
            message.responsePort.send(
              ErrorResponse('TTS not initialized'),
            );
            return;
          }

          final totalStopwatch = Stopwatch()..start();
          debugPrint('[TTS Worker] Generating audio for [${message.messageId}] (${message.text.length} chars)...');

          final generateStopwatch = Stopwatch()..start();
          final audio = tts!.generate(
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
          final rtf = (totalStopwatch.elapsedMilliseconds / 1000) / audioDuration;

          debugPrint('[TTS Worker] ✓ Audio generated for [${message.messageId}]:');
          debugPrint('  - Generate: ${(generateStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
          debugPrint('  - Convert to WAV: ${convertStopwatch.elapsedMilliseconds}ms');
          debugPrint('  - Total: ${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s');
          debugPrint('  - Audio duration: ${audioDuration.toStringAsFixed(2)}s');
          debugPrint('  - RTF (Real-time Factor): ${rtf.toStringAsFixed(3)}x');
          debugPrint('  - Output size: ${(wavBytes.length / 1024).toStringAsFixed(1)} KB');

          message.responsePort.send(AudioGeneratedResponse(wavBytes));

        case DisposeTtsMessage():
          debugPrint('[TTS Worker] Disposing TTS');
          tts?.free();
          tts = null;
          isInitialized = false;
          receivePort.close();
      }
    } catch (e, stackTrace) {
      debugPrint('[TTS Worker] Error: $e\n$stackTrace');
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

  /// Initialize the worker isolate and load TTS model
  Future<void> initialize() async {
    if (_isInitialized) return;

    // CRITICAL: Pre-cache model files in main isolate BEFORE spawning worker
    // Background isolates can't access rootBundle, so files must be cached first
    await preCacheTtsModelFiles(modelName: AppConfig.ttsModelName);

    debugPrint('[TTS Manager] Spawning worker isolate...');
    final receivePort = ReceivePort();

    // Get the root isolate token to pass to the background isolate
    final rootIsolateToken = RootIsolateToken.instance;
    if (rootIsolateToken == null) {
      throw Exception('RootIsolateToken is null - ensure this is called from main isolate');
    }

    _isolate = await Isolate.spawn(
      _ttsWorkerIsolate,
      _IsolateTask(receivePort.sendPort, rootIsolateToken),
      errorsAreFatal: false, // Prevent isolate crashes from taking down the app
    );

    // Get the worker's SendPort
    _workerSendPort = await receivePort.first as SendPort;
    debugPrint('[TTS Manager] Worker isolate spawned');

    // Initialize TTS in the worker, passing the model name from main isolate
    final initResponsePort = ReceivePort();
    _workerSendPort!.send(InitializeTtsMessage(
      initResponsePort.sendPort,
      AppConfig.ttsModelName, // Loaded in main isolate
    ));

    final response = await initResponsePort.first;
    initResponsePort.close();

    if (response is ErrorResponse) {
      throw Exception('Failed to initialize TTS: ${response.error}');
    }

    _isInitialized = true;
    debugPrint('[TTS Manager] TTS initialized in background');
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
    _workerSendPort!.send(GenerateAudioMessage(
      text: text,
      messageId: messageId,
      speakerId: speakerId,
      speed: speed,
      responsePort: responsePort.sendPort,
    ));

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
