import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
import '/speech_recognition/services.dart';

class RecordingState {
  final bool isRecording;
  final bool isContinuous;
  final String recognizedText;
  final String? textToSubmit; // Text ready to be submitted (endpoint detected)
  final String? error;
  final RecordState recordState;

  const RecordingState({
    this.isRecording = false,
    this.isContinuous = false,
    this.recognizedText = '',
    this.textToSubmit,
    this.error,
    this.recordState = RecordState.stop,
  });

  factory RecordingState.initial() {
    return const RecordingState();
  }

  RecordingState copyWith({
    bool? isRecording,
    bool? isContinuous,
    String? recognizedText,
    String? Function()? textToSubmit,
    String? error,
    RecordState? recordState,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isContinuous: isContinuous ?? this.isContinuous,
      recognizedText: recognizedText ?? this.recognizedText,
      textToSubmit: textToSubmit != null ? textToSubmit() : this.textToSubmit,
      error: error,
      recordState: recordState ?? this.recordState,
    );
  }
}

final recordingProvider =
    StateNotifierProvider<RecordingNotifier, RecordingState>((ref) {
      return RecordingNotifier(ref);
    });

class RecordingNotifier extends StateNotifier<RecordingState> {
  final Ref ref;
  ASR? _asr;

  RecordingNotifier(this.ref) : super(RecordingState.initial()) {
    // Listen to voice mode changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.voiceMode != next.voiceMode) {
        _handleVoiceModeChanged(previous?.voiceMode, next.voiceMode);
      }
    });

    // Listen to coordinator state changes - stop/resume as needed
    ref.listen<AudioCoordinatorState>(audioCoordinatorProvider, (
      previous,
      next,
    ) {
      // Handle forced stop (coordinator needs to play audio)
      if (state.isRecording &&
          previous?.mode == AudioMode.recording &&
          next.mode != AudioMode.recording) {
        debugPrint(
          'RecordingProvider: Coordinator forced stop, stopping recording',
        );
        internalStop();
      }

      // Handle auto-resume (coordinator finished playing, resuming continuous recording)
      if (!state.isRecording &&
          state.isContinuous &&
          previous?.mode != AudioMode.recording &&
          next.mode == AudioMode.recording) {
        debugPrint(
          'RecordingProvider: Coordinator auto-resumed, restarting recording',
        );
        internalStart();
      }
    });

    // Initialize based on current voice mode
    // Defer to avoid modifying other providers during initialization
    final currentMode = ref.read(settingsProvider).voiceMode;
    if (currentMode == VoiceMode.listening ||
        currentMode == VoiceMode.conversation) {
      Future.microtask(() => _startContinuous());
    }
  }

  void _handleVoiceModeChanged(VoiceMode? oldMode, VoiceMode newMode) {
    final wasContinuous =
        oldMode == VoiceMode.listening || oldMode == VoiceMode.conversation;
    final isContinuous =
        newMode == VoiceMode.listening || newMode == VoiceMode.conversation;

    if (!wasContinuous && isContinuous) {
      // Switching to continuous mode
      _startContinuous();
    } else if (wasContinuous && !isContinuous) {
      // Switching from continuous mode
      _stopContinuous();
    }
  }

  Future<void> _startContinuous() async {
    if (state.isContinuous) return;

    debugPrint('RecordingProvider: Starting continuous recording');
    final granted = await ref
        .read(audioCoordinatorProvider.notifier)
        .requestRecording();

    if (!granted) {
      debugPrint('RecordingProvider: Coordinator denied recording request');
      return;
    }

    try {
      _initASR();
      await _asr!.start();
      state = state.copyWith(
        isRecording: true,
        isContinuous: true,
        error: null,
      );
      debugPrint('RecordingProvider: Continuous recording started');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to start continuous recording: $e');
      state = state.copyWith(error: 'Failed to start continuous recording: $e');
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> _stopContinuous() async {
    if (!state.isContinuous) return;

    debugPrint('RecordingProvider: Stopping continuous recording');
    try {
      await _asr?.stop();
      state = state.copyWith(
        isRecording: false,
        isContinuous: false,
        recognizedText: '',
      );
      // Release coordinator lock
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      debugPrint('RecordingProvider: Continuous recording stopped');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to stop continuous recording: $e');
      state = state.copyWith(error: 'Failed to stop continuous recording: $e');
    }
  }

  Future<void> startOneShot() async {
    if (state.isRecording) return;

    debugPrint('RecordingProvider: Starting single recording');
    final granted = await ref
        .read(audioCoordinatorProvider.notifier)
        .requestRecording();

    if (!granted) {
      debugPrint('RecordingProvider: Coordinator denied recording request');
      state = state.copyWith(error: 'Cannot record while audio is playing');
      return;
    }

    try {
      _initASR();
      await _asr!.start();
      state = state.copyWith(
        isRecording: true,
        isContinuous: false,
        recognizedText: '',
        error: null,
      );
      debugPrint('RecordingProvider: Single recording started');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to start single recording: $e');
      state = state.copyWith(error: 'Failed to start recording: $e');
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> stopOneShot() async {
    if (!state.isRecording || state.isContinuous) return;

    debugPrint('RecordingProvider: Stopping single recording');
    try {
      await _asr?.stop();
      state = state.copyWith(isRecording: false);
      // Release coordinator lock
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      debugPrint('RecordingProvider: Single recording stopped');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to stop recording: $e');
      state = state.copyWith(error: 'Failed to stop recording: $e');
    }
  }

  void clearText() {
    state = state.copyWith(recognizedText: '');
  }

  void clearTextToSubmit() {
    state = state.copyWith(textToSubmit: () => null);
  }

  // Internal methods called by AudioCoordinator for forced stop/resume
  Future<void> internalStop() async {
    debugPrint('RecordingProvider: internalStop() called by coordinator');
    try {
      await _asr?.stop();
      state = state.copyWith(
        isRecording: false,
        // Keep isContinuous flag so we know to resume later
      );
      debugPrint('RecordingProvider: Internal stop completed');
    } catch (e) {
      debugPrint('RecordingProvider: Internal stop failed: $e');
    }
  }

  Future<void> internalStart() async {
    debugPrint('RecordingProvider: internalStart() called for auto-resume');
    try {
      _initASR();
      await _asr!.start();
      state = state.copyWith(isRecording: true, error: null);
      debugPrint('RecordingProvider: Internal start completed');
    } catch (e) {
      debugPrint('RecordingProvider: Internal start failed: $e');
      state = state.copyWith(error: 'Failed to resume recording: $e');
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  void _initASR() {
    if (_asr != null) return;

    _asr = ASR(
      textRecognized: (text) {
        debugPrint('Text recognized: $text');
        state = state.copyWith(recognizedText: text);
      },
      textFinished: () {
        // Endpoint detected (pause in speech)
        // In continuous mode: save text for submission and clear for next utterance
        // In single-recording mode: text stays for user to edit/submit
        if (state.isContinuous && state.recognizedText.isNotEmpty) {
          final textToSend = state.recognizedText;
          state = state.copyWith(
            recognizedText: '',
            textToSubmit: () => textToSend,
          );
        }
      },
      onRecordStateChanged: (recordState) {
        state = state.copyWith(recordState: recordState);
      },
    );
    _asr!.init();
  }

  @override
  void dispose() {
    _asr?.dispose();
    super.dispose();
  }
}
