import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '/speech_recognition/sherpa_streaming_asr.dart';
import '/speech_recognition/utils.dart';

class ASR {
  late final AudioRecorder _audioRecorder;

  bool _isInitialized = false;

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OnlineStream? _stream;
  final int _sampleRate = 16000;

  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;

  final ValueChanged<String> textRecognized;
  final VoidCallback textFinished;
  final ValueChanged<RecordState>? onRecordStateChanged;

  RecordState get recordState => _recordState;

  ASR({
    required this.textRecognized,
    required this.textFinished,
    this.onRecordStateChanged,
  });

  void init() {
    _audioRecorder = AudioRecorder();

    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
  }

  Future<void> start() async {
    if (!_isInitialized) {
      developer.Timeline.startSync('ASR_Initialization');
      try {
        developer.Timeline.startSync('ASR_InitBindings');
        sherpa_onnx.initBindings();
        developer.Timeline.finishSync();

        developer.Timeline.startSync('ASR_CreateRecognizer');
        _recognizer = await createOnlineRecognizer();
        developer.Timeline.finishSync();

        developer.Timeline.startSync('ASR_CreateStream');
        _stream = _recognizer?.createStream();
        developer.Timeline.finishSync();

        _isInitialized = true;
      } finally {
        developer.Timeline.finishSync();
      }
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        const availableEncoders = [AudioEncoder.pcm16bits, AudioEncoder.aacLc];
        AudioEncoder? supportedEncoder;
        for (final e in availableEncoders) {
          if (await _isEncoderSupported(e)) {
            supportedEncoder = e;
            break;
          }
        }

        if (supportedEncoder == null) {
          debugPrint('No supported encoder found.');
          return;
        }

        final AudioEncoder encoder = supportedEncoder;
        final devs = await _audioRecorder.listInputDevices();
        debugPrint(devs.toString());

        final config = RecordConfig(
          androidConfig: AndroidRecordConfig(
            audioManagerMode: AudioManagerMode.modeNormal,
          ),
          encoder: encoder,
          sampleRate: 16000,
          numChannels: 1,
        );

        final stream = await _audioRecorder.startStream(config);

        stream.listen(
          (data) {
            developer.Timeline.startSync('ASR_ProcessAudioChunk');

            final samplesFloat32 = convertBytesToFloat32(
              Uint8List.fromList(data),
            );

            _stream!.acceptWaveform(
              samples: samplesFloat32,
              sampleRate: _sampleRate,
            );
            while (_recognizer!.isReady(_stream!)) {
              _recognizer!.decode(_stream!);
            }
            final text = _recognizer!.getResult(_stream!).text;

            if (text != '') {
              textRecognized(text);
            }

            if (_recognizer!.isEndpoint(_stream!)) {
              _recognizer!.reset(_stream!);
              textFinished();
            }

            developer.Timeline.finishSync();
          },
          onDone: () {
            debugPrint('stream stopped.');
          },
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> stop() async {
    _stream!.free();
    _stream = _recognizer!.createStream();

    await _audioRecorder.stop();
  }

  Future<void> pause() => _audioRecorder.pause();

  Future<void> resume() => _audioRecorder.resume();

  void _updateRecordState(RecordState recordState) {
    _recordState = recordState;
    onRecordStateChanged?.call(recordState);
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${e.name}');
        }
      }
    }

    return isSupported;
  }

  void dispose() {
    _recordSub?.cancel();
    _audioRecorder.dispose();
    _stream?.free();
    _recognizer?.free();
  }
}
