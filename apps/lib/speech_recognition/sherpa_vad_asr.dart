import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:sherpa_voice/asr_config.dart';

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

  // Whichever route the current VAD instance was tuned for. The mic can
  // switch between built-in and Bluetooth SCO from one recording to the
  // next (headset connects/disconnects) without this VadAsr instance being
  // recreated, so start() rebuilds the VAD whenever this no longer matches.
  bool _isBluetoothRoute = false;

  // One-pole high-pass filter state (~80Hz cutoff at 16kHz), carried across
  // chunks. Only applied on Bluetooth SCO routes — see _highPassFilter().
  double _hpPrevIn = 0.0;
  double _hpPrevOut = 0.0;
  static const double _hpAlpha = 0.9695;

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
  Future<void> start({bool isBluetoothRoute = false}) async {
    final routeChanged = _isInitialized && isBluetoothRoute != _isBluetoothRoute;
    _isBluetoothRoute = isBluetoothRoute;
    _hpPrevIn = 0.0;
    _hpPrevOut = 0.0;

    if (!_isInitialized || routeChanged) {
      developer.Timeline.startSync('VadAsr_Initialization');
      try {
        if (!_isInitialized) {
          sherpa_onnx.initBindings();
          _recognizer = await _buildOfflineRecognizer();
        }
        // VAD sensitivity depends on route (see _buildVad) — rebuild it
        // whenever Bluetooth connects/disconnects between recordings.
        _vad?.free();
        _vad = await _buildVad();
        _isInitialized = true;
        Logger.debug(
          '[VadAsr] Initialized recognizer and VAD '
          '(bluetooth: $_isBluetoothRoute)',
        );
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
    // convertBytesToFloat32 always assumes raw little-endian PCM16 bytes.
    // If the picked encoder is anything else (e.g. the aacLc fallback),
    // that assumption is silently wrong and every sample is garbage — this
    // line is the fastest way to confirm/rule that out from a device log.
    Logger.debug('[VadAsr] Using audio encoder: $encoder');
    Logger.debug(
      '[VadAsr] Using audio source: ${AndroidAudioSource.voiceCommunication}',
    );

    final config = RecordConfig(
      // See services.dart: MicRouter owns Android routing; keep record's
      // own audio-mode/Bluetooth management out of the way. audioSource is
      // voiceCommunication for its echo-cancellation/noise-suppression
      // benefit — confirmed NOT the cause of device-switching getting stuck
      // (reverted to defaultSource and retested; switching was still
      // broken), so no reason to give up the AEC/NS benefit. The switching
      // bug itself is tracked in openspec/changes/mic-preferred-device-routing/.
      androidConfig: const AndroidRecordConfig(
        manageBluetooth: false,
        audioSource: AndroidAudioSource.voiceCommunication,
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
    _pending.addAll(_isBluetoothRoute ? _highPassFilter(samples) : samples);

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
      // Debug builds only (see dumpDebugWav) — lets a real VAD segment be
      // pulled off the device and replayed through
      // experiments/nb-whisper-onnx/sanity_check.py to check whether a
      // quality problem is in the recorded audio itself or elsewhere.
      unawaited(
        dumpDebugWav(
          'segment_${DateTime.now().millisecondsSinceEpoch}.wav',
          samples,
          _sampleRate,
        ),
      );

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
    final architecture = modelMetadata.architecture;
    Logger.debug(
      '[VadAsr] Building offline recognizer ($architecture) for '
      '${modelMetadata.modelId}',
    );
    // Never fall back to sherpa-onnx's Whisper auto-detect by passing an
    // empty language: on marginal audio it can lock onto the wrong language
    // and produce near-useless output — a real failure mode seen with other
    // multilingual models (Omnilingual ASR, Parakeet). See buildOfflineAsrRecognizer.
    return buildOfflineAsrRecognizer(
      architecture,
      modelMetadata.fileStructure,
      modelMetadata.loader,
      modelMetadata.modelId,
      language: modelMetadata.language,
    );
  }

  Future<sherpa_onnx.VoiceActivityDetector> _buildVad() async {
    final sileroVadPath = await copyAssetFileToCache('silero_vad.onnx');
    Logger.debug('[VadAsr] Silero VAD path: $sileroVadPath');

    // Bluetooth SCO's higher noise floor and compression artifacts trigger
    // more false-positive segments (empty/garbled transcriptions observed
    // in practice) than the built-in mic at the same sensitivity. Raising
    // the threshold and minimum speech duration filters out short noise
    // blips; raising minimum silence duration avoids cutting mid-word on
    // brief SCO dropouts/pauses.
    final config = sherpa_onnx.VadModelConfig(
      sileroVad: sherpa_onnx.SileroVadModelConfig(
        model: sileroVadPath,
        threshold: _isBluetoothRoute ? 0.6 : 0.5,
        minSilenceDuration: _isBluetoothRoute ? 0.8 : 0.5,
        minSpeechDuration: _isBluetoothRoute ? 0.5 : 0.25,
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

  /// One-pole high-pass filter (~80Hz cutoff at 16kHz) to strip low-frequency
  /// hum/noise that Bluetooth SCO's compression tends to introduce, before
  /// audio reaches the VAD or recognizer. State carries across calls within
  /// a recording; start() resets it for a fresh session.
  Float32List _highPassFilter(Float32List samples) {
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final x = samples[i];
      final y = _hpAlpha * (_hpPrevOut + x - _hpPrevIn);
      out[i] = y;
      _hpPrevIn = x;
      _hpPrevOut = y;
    }
    return out;
  }

  Future<AudioEncoder?> _pickEncoder() async {
    for (final e in [AudioEncoder.pcm16bits, AudioEncoder.aacLc]) {
      if (await _audioRecorder!.isEncoderSupported(e)) return e;
    }
    return null;
  }
}
