import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/speech_recognition/services.dart';
import '/speech_recognition/asr_metadata.dart';
import '/speech_recognition/utils.dart';
import '/utils/files.dart';
import '/utils/logger.dart';
import '/voice/voice_service.dart';

/// ASR backend using OfflineRecognizer + VoiceActivityDetector.
///
/// Simulates streaming by feeding audio in 512-sample windows to Silero VAD.
/// When VAD detects a complete speech segment, the accumulated samples are
/// passed to the offline recognizer for transcription.
class VadAsr implements AsrService {
  final ValueChanged<String> textRecognized;
  final VoidCallback textFinished;
  final ValueChanged<AudioRecordingStatus>? onStatusChanged;
  final VoidCallback? onAudioDataReceived;
  final ValueChanged<double>? onAmplitudeChanged;
  final ValueChanged<Object>? onStreamError;
  final VoidCallback? onStreamDone;
  @override
  final AsrModelMetadata modelMetadata;

  AudioRecorder? _audioRecorder;
  bool _isAudioRecorderInitialized = false;
  bool _isInitialized = false;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  sherpa_onnx.VoiceActivityDetector? _vad;

  StreamSubscription<RecordState>? _recordSub;
  StreamSubscription<Amplitude>? _amplitudeSub;

  // Leftover samples that haven't filled a 512-sample window yet
  final List<double> _pending = [];

  static const int _windowSize = 512;
  static const int _sampleRate = 16000;

  VadAsr({
    required this.textRecognized,
    required this.textFinished,
    required this.modelMetadata,
    this.onStatusChanged,
    this.onAudioDataReceived,
    this.onAmplitudeChanged,
    this.onStreamError,
    this.onStreamDone,
  });

  @override
  void init() {
    if (_isAudioRecorderInitialized) return;

    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder!.onStateChanged().listen((state) {
      final status = switch (state) {
        RecordState.stop => AudioRecordingStatus.stopped,
        RecordState.record => AudioRecordingStatus.recording,
        RecordState.pause => AudioRecordingStatus.paused,
      };
      onStatusChanged?.call(status);
    });

    _amplitudeSub = _audioRecorder!
        .onAmplitudeChanged(const Duration(milliseconds: 200))
        .listen((amplitude) => onAmplitudeChanged?.call(amplitude.current));

    _isAudioRecorderInitialized = true;
  }

  @override
  Future<void> start() async {
    if (!_isInitialized) {
      developer.Timeline.startSync('VadAsr_Initialization');
      try {
        sherpa_onnx.initBindings();
        _recognizer = await _buildOfflineRecognizer();
        _vad = await _buildVad();
        _isInitialized = true;
        Logger.debug('[VadAsr] Initialized recognizer and VAD');
      } finally {
        developer.Timeline.finishSync();
      }
    } else {
      // Reset VAD state for fresh session
      _vad!.clear();
      _pending.clear();
    }

    if (!await _audioRecorder!.hasPermission()) {
      Logger.debug('[VadAsr] Microphone permission denied');
      return;
    }

    final encoder = await _pickEncoder();
    if (encoder == null) {
      Logger.debug('[VadAsr] No supported audio encoder found');
      return;
    }

    final config = RecordConfig(
      androidConfig: const AndroidRecordConfig(
        audioManagerMode: AudioManagerMode.modeInCommunication,
      ),
      encoder: encoder,
      sampleRate: _sampleRate,
      numChannels: 1,
      audioInterruption: AudioInterruptionMode.pauseResume,
    );

    Logger.debug('[VadAsr] Starting recording');
    final stream = await _audioRecorder!.startStream(config);

    stream.listen(
      (data) {
        onAudioDataReceived?.call();
        final samples = convertBytesToFloat32(Uint8List.fromList(data));
        _processChunk(samples);
      },
      onError: (Object error) {
        Logger.debug('[VadAsr] Audio stream error: $error');
        onStreamError?.call(error);
      },
      onDone: () {
        Logger.debug('[VadAsr] Audio stream done');
        onStreamDone?.call();
      },
    );
  }

  void _processChunk(Float32List samples) {
    _pending.addAll(samples);

    while (_pending.length >= _windowSize) {
      final window = Float32List.fromList(_pending.sublist(0, _windowSize));
      _pending.removeRange(0, _windowSize);
      _vad!.acceptWaveform(window);
    }

    // Drain all completed speech segments from VAD
    while (!_vad!.isEmpty()) {
      final segment = _vad!.front();
      _vad!.pop();
      _recognizeSegment(segment.samples);
    }
  }

  void _recognizeSegment(Float32List samples) {
    developer.Timeline.startSync('VadAsr_Recognize');
    try {
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      stream.free();

      final text = result.text.trim();
      Logger.debug('[VadAsr] Segment recognized: "$text"');

      if (text.isNotEmpty) {
        textRecognized(text);
        textFinished();
      }
    } finally {
      developer.Timeline.finishSync();
    }
  }

  @override
  Future<void> stop() async {
    Logger.debug('[VadAsr] Stopping');
    try {
      await _audioRecorder!.stop();
    } catch (e) {
      Logger.debug('[VadAsr] Error stopping recorder: $e');
    }
    _pending.clear();
  }

  @override
  Future<void> pause() => _audioRecorder!.pause();

  @override
  Future<void> resume() => _audioRecorder!.resume();

  @override
  void dispose() {
    _recordSub?.cancel();
    _amplitudeSub?.cancel();
    _audioRecorder?.dispose();
    _vad?.free();
    _vad = null;
    _recognizer?.free();
    _recognizer = null;
    _isInitialized = false;
  }

  Future<sherpa_onnx.OfflineRecognizer> _buildOfflineRecognizer() async {
    final files = modelMetadata.fileStructure;
    final loader = modelMetadata.loader;
    final id = modelMetadata.modelId;

    Logger.debug('[VadAsr] Building offline recognizer for $id');

    final config = sherpa_onnx.OfflineRecognizerConfig(
      model: sherpa_onnx.OfflineModelConfig(
        transducer: sherpa_onnx.OfflineTransducerModelConfig(
          encoder: await loader.loadModelFile(id, files['encoder']!),
          decoder: await loader.loadModelFile(id, files['decoder']!),
          joiner: await loader.loadModelFile(id, files['joiner']!),
        ),
        tokens: await loader.loadModelFile(id, files['tokens']!),
        modelType: 'nemo_transducer',
        numThreads: 2,
        debug: false,
      ),
    );
    return sherpa_onnx.OfflineRecognizer(config);
  }

  Future<sherpa_onnx.VoiceActivityDetector> _buildVad() async {
    final sileroVadPath = await copyAssetFileToCache('silero_vad.onnx');
    Logger.debug('[VadAsr] Silero VAD path: $sileroVadPath');

    final config = sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: sileroVadPath,
        threshold: 0.5,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        windowSize: _windowSize,
        maxSpeechDuration: 30.0,
      ),
      sampleRate: _sampleRate,
      numThreads: 1,
      debug: false,
    );
    return sherpa_onnx.VoiceActivityDetector(
      config: config,
      bufferSizeInSeconds: 30.0,
    );
  }

  Future<AudioEncoder?> _pickEncoder() async {
    for (final e in [AudioEncoder.pcm16bits, AudioEncoder.aacLc]) {
      if (await _audioRecorder!.isEncoderSupported(e)) return e;
    }
    return null;
  }
}
