import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/speech_recognition/asr_metadata.dart';
import '/speech_recognition/sherpa_streaming_asr.dart';
import '/speech_recognition/utils.dart';
import '../../utils/logger.dart';

/// Common interface for ASR service implementations (online and offline).
abstract class AsrService {
  AsrModelMetadata? get modelMetadata;
  void init();

  /// [isBluetoothRoute] lets implementations that need it (currently only
  /// [VadAsr]) adapt to Bluetooth SCO's lower audio quality; streaming
  /// architectures ignore it.
  Future<void> start({bool isBluetoothRoute = false});
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  void dispose();
}

class ASR implements AsrService {
  AudioRecorder? _audioRecorder;
  bool _isAudioRecorderInitialized = false;

  bool _isInitialized = false;

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  final int _sampleRate = 16000;

  StreamSubscription<RecordState>? _recordSub;
  StreamSubscription<Amplitude>? _amplitudeSub;
  RecordState _recordState = RecordState.stop;

  final ValueChanged<String> textRecognized;
  final VoidCallback textFinished;
  final ValueChanged<RecordState>? onRecordStateChanged;
  final VoidCallback? onAudioDataReceived;
  final ValueChanged<double>? onAmplitudeChanged;
  final ValueChanged<Object>? onStreamError;
  final VoidCallback? onStreamDone;

  /// Metadata for the downloaded ASR model. Null means no model is selected.
  @override
  final AsrModelMetadata? modelMetadata;

  RecordState get recordState => _recordState;

  ASR({
    required this.textRecognized,
    required this.textFinished,
    this.onRecordStateChanged,
    this.onAudioDataReceived,
    this.onAmplitudeChanged,
    this.onStreamError,
    this.onStreamDone,
    this.modelMetadata,
  });

  @override
  void init() {
    if (_isAudioRecorderInitialized) return;

    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder!.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });

    _amplitudeSub = _audioRecorder!
        .onAmplitudeChanged(
          const Duration(milliseconds: 200),
        ) // Even faster updates
        .listen((amplitude) {
          // The record package already returns dBFS values
          final dbFS = amplitude.current;
          onAmplitudeChanged?.call(dbFS);
        });

    _isAudioRecorderInitialized = true;
  }

  @override
  Future<void> start({bool isBluetoothRoute = false}) async {
    if (!_isInitialized) {
      developer.Timeline.startSync('ASR_Initialization');
      try {
        developer.Timeline.startSync('ASR_InitBindings');
        sherpa_onnx.initBindings();
        developer.Timeline.finishSync();

        developer.Timeline.startSync('ASR_CreateRecognizer');
        _recognizer = await createOnlineRecognizerFromMetadata(modelMetadata!);
        developer.Timeline.finishSync();

        _isInitialized = true;
      } finally {
        developer.Timeline.finishSync();
      }
    }

    // Create a fresh stream for each recording session
    // (stream is freed in stop(), so must recreate here)
    _stream = _recognizer?.createStream();

    try {
      if (await _audioRecorder!.hasPermission()) {
        const availableEncoders = [AudioEncoder.pcm16bits, AudioEncoder.aacLc];
        AudioEncoder? supportedEncoder;
        for (final e in availableEncoders) {
          if (await _isEncoderSupported(e)) {
            supportedEncoder = e;
            break;
          }
        }

        if (supportedEncoder == null) {
          Logger.debug('No supported encoder found.');
          return;
        }

        final AudioEncoder encoder = supportedEncoder;
        final devs = await _audioRecorder!.listInputDevices();
        Logger.debug(devs.toString());

        final config = RecordConfig(
          // MicRouter (native) is the single owner of Android audio mode and
          // Bluetooth SCO; leave audioManagerMode at its modeNormal default
          // and disable record's own Bluetooth management so it doesn't race
          // MicRouter's route with its own legacy startBluetoothSco() calls.
          // audioSource is voiceCommunication for its echo-cancellation/
          // noise-suppression benefit — confirmed NOT the cause of
          // device-switching getting stuck (reverted to defaultSource and
          // retested; switching was still broken), so no reason to give up
          // the AEC/NS benefit. The switching bug itself is tracked in
          // openspec/changes/mic-preferred-device-routing/.
          androidConfig: const AndroidRecordConfig(
            manageBluetooth: false,
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
          encoder: encoder,
          sampleRate: 16000,
          numChannels: 1,
          // Auto pause/resume on interruptions (phone calls, etc.)
          // This makes the recorder handle interruptions automatically
          audioInterruption: AudioInterruptionMode.pauseResume,
        );

        Logger.debug('ASR: Starting recording');
        final stream = await _audioRecorder!.startStream(config);
        String? lastText;

        stream.listen(
          (data) {
            developer.Timeline.startSync('ASR_ProcessAudioChunk');

            // Notify that audio data was received
            onAudioDataReceived?.call();

            final samplesFloat32 = convertBytesToFloat32(
              Uint8List.fromList(data),
            );

            // Fix: Add null checks to prevent race conditions
            if (_stream != null) {
              _stream!.acceptWaveform(
                samples: samplesFloat32,
                sampleRate: _sampleRate,
              );
              while (_recognizer!.isReady(_stream!)) {
                _recognizer!.decode(_stream!);
              }
              final text = _recognizer!.getResult(_stream!).text;

              if (text != '' && text != lastText) {
                lastText = text;
                textRecognized(text);
              }

              if (_recognizer!.isEndpoint(_stream!)) {
                _recognizer!.reset(_stream!);
                textFinished();
              }
            }

            developer.Timeline.finishSync();
          },
          onError: (Object error) {
            Logger.debug('Audio stream error: $error');
            onStreamError?.call(error);
          },
          onDone: () {
            Logger.debug('Audio stream done (unexpected closure)');
            onStreamDone?.call();
          },
        );
      }
    } catch (e) {
      Logger.debug(e.toString());
    }
  }

  @override
  Future<void> stop() async {
    Logger.debug('ASR: Stopping recording...');

    try {
      // Stop the audio recorder first - this should stop the stream callbacks
      await _audioRecorder!.stop();
      Logger.debug('ASR: Audio recorder stopped');
    } catch (e) {
      Logger.debug('ASR: Error stopping audio recorder: $e');
    }

    // Free the stream to clean up resources
    if (_stream != null) {
      _stream!.free();
      _stream = null;
      Logger.debug('ASR: Stream freed and nulled');
    }

    Logger.debug('ASR: Recording stop completed');
  }

  @override
  Future<void> pause() => _audioRecorder!.pause();

  @override
  Future<void> resume() => _audioRecorder!.resume();

  void _updateRecordState(RecordState recordState) {
    _recordState = recordState;
    onRecordStateChanged?.call(recordState);
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder!.isEncoderSupported(encoder);

    if (!isSupported) {
      Logger.debug('${encoder.name} is not supported on this platform.');
      Logger.debug('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder!.isEncoderSupported(e)) {
          Logger.debug('- ${e.name}');
        }
      }
    }

    return isSupported;
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder?.dispose();
    _stream?.free();
    _recognizer?.free();
  }
}
