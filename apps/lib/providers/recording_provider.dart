import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
import '/speech_recognition/services.dart';

class RecordingState {
  final bool isRecording;
  final bool isContinuous;
  final bool isInitializing; // ASR startup/init in progress
  final String recognizedText;
  final String? textToSubmit; // Text ready to be submitted (endpoint detected)
  final String? error;
  final RecordState recordState;
  final double? currentAmplitude; // Current amplitude in dBFS
  final List<double>
  amplitudeHistory; // Last 5 amplitude readings for visualization
  final List<double> barHeights; // Pre-calculated bar heights for visualization

  const RecordingState({
    this.isRecording = false,
    this.isContinuous = false,
    this.isInitializing = false,
    this.recognizedText = '',
    this.textToSubmit,
    this.error,
    this.recordState = RecordState.stop,
    this.currentAmplitude,
    this.amplitudeHistory = const [],
    this.barHeights = const [],
  });

  factory RecordingState.initial() {
    return const RecordingState();
  }

  RecordingState copyWith({
    bool? isRecording,
    bool? isContinuous,
    bool? isInitializing,
    String? recognizedText,
    String? Function()? textToSubmit,
    String? error,
    RecordState? recordState,
    double? currentAmplitude,
    List<double>? amplitudeHistory,
    List<double>? barHeights,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      isContinuous: isContinuous ?? this.isContinuous,
      isInitializing: isInitializing ?? this.isInitializing,
      recognizedText: recognizedText ?? this.recognizedText,
      textToSubmit: textToSubmit != null ? textToSubmit() : this.textToSubmit,
      error: error,
      recordState: recordState ?? this.recordState,
      currentAmplitude: currentAmplitude ?? this.currentAmplitude,
      amplitudeHistory: amplitudeHistory ?? this.amplitudeHistory,
      barHeights: barHeights ?? this.barHeights,
    );
  }
}

final recordingProvider = NotifierProvider<RecordingNotifier, RecordingState>(
  () {
    return RecordingNotifier();
  },
);

class RecordingNotifier extends Notifier<RecordingState> {
  static const _platform = MethodChannel('com.relagent.background_service');

  ASR? _asr;

  // Health monitoring fields
  Timer? _healthCheckTimer;
  DateTime? _lastAudioDataTime;

  // Auto-recovery fields
  int _recoveryAttempts = 0;

  // Duration-based shutoff field
  Timer? _durationTimer;

  // Baseline calculation for volume visualization
  double _currentBaseline = -60.0; // Initial baseline
  static const double _baselineAlpha = 0.1; // EMA smoothing factor

  @override
  RecordingState build() {
    // Clean up on dispose
    ref.onDispose(() {
      _asr?.dispose();
      _stopHealthMonitoring();
      _stopDurationTimer();
    });

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
    ) async {
      // Handle forced stop (coordinator needs to play audio)
      if (state.isRecording &&
          previous?.mode == AudioMode.recording &&
          next.mode != AudioMode.recording) {
        debugPrint(
          'RecordingProvider: Coordinator forced stop, stopping recording',
        );
        await internalStop();
      }

      // Handle auto-resume (coordinator finished playing, resuming continuous recording)
      if (!state.isRecording &&
          state.isContinuous &&
          previous?.mode != AudioMode.recording &&
          next.mode == AudioMode.recording) {
        debugPrint(
          'RecordingProvider: Coordinator auto-resumed, restarting recording',
        );
        await internalStart();
      }
    });

    return RecordingState.initial();
  }

  /// Called by initialization code (e.g., startup sequence) to pre-initialize ASR
  void initialize() {
    debugPrint('RecordingProvider: initializing ASR...');
    state = state.copyWith(isInitializing: true);
    _initASR();
    if (_asr != null) {
      _asr!.init();
    }
    state = state.copyWith(isInitializing: false);
  }

  /// Called by UI when ready to handle recording (e.g. ChatPage mounted)
  void checkAutoStart() {
    final currentMode = ref.read(settingsProvider).voiceMode;
    if (currentMode == VoiceMode.listening ||
        currentMode == VoiceMode.conversation) {
      _startContinuous();
    }
  }

  void _handleVoiceModeChanged(VoiceMode? oldMode, VoiceMode newMode) {
    debugPrint(
      'RecordingProvider: Voice mode changed from $oldMode to $newMode',
    );

    final wasContinuous =
        oldMode == VoiceMode.listening || oldMode == VoiceMode.conversation;
    final isContinuous =
        newMode == VoiceMode.listening || newMode == VoiceMode.conversation;

    if (!wasContinuous && isContinuous) {
      debugPrint('RecordingProvider: Switching to continuous mode');
      _startContinuous();
    } else if (wasContinuous && !isContinuous) {
      debugPrint(
        'RecordingProvider: Switching from continuous mode (stopping)',
      );
      _stopContinuous();
    }
  }

  Future<void> _startContinuous() async {
    if (state.isContinuous) return;

    debugPrint('RecordingProvider: Starting continuous recording');

    // Update UI state immediately to show recording has started
    state = state.copyWith(isRecording: true, isContinuous: true, error: null);

    try {
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestRecording();

      if (!granted) {
        debugPrint('RecordingProvider: Coordinator denied recording request');
        // Revert UI state on failure
        state = state.copyWith(isRecording: false, isContinuous: false);
        return;
      }

      state = state.copyWith(isInitializing: true);
      _initASR();
      // Ensure initialization is complete (defensive check)
      if (_asr != null) _asr!.init();
      await _asr!.start();
      state = state.copyWith(isInitializing: false);
      _recoveryAttempts = 0; // Reset recovery counter on successful start
      _startHealthMonitoring();
      _startDurationTimer();
      debugPrint('RecordingProvider: Continuous recording started');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to start continuous recording: $e');
      state = state.copyWith(
        isRecording: false,
        isContinuous: false,
        error: 'Failed to start continuous recording: $e',
      );
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> _stopContinuous() async {
    if (!state.isContinuous) return;

    debugPrint('RecordingProvider: Stopping continuous recording');
    _stopHealthMonitoring();
    _stopDurationTimer();
    try {
      await _asr?.stop();
    } catch (e) {
      debugPrint('RecordingProvider: Error during stop: $e');
    } finally {
      // Always update state and release lock, even if stop fails
      state = state.copyWith(
        isRecording: false,
        isContinuous: false,
        recognizedText: '',
      );
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      debugPrint(
        'RecordingProvider: Continuous recording stopped (state reset)',
      );
    }
  }

  Future<void> startOneShot() async {
    if (state.isRecording) return;

    debugPrint('RecordingProvider: Starting single recording');

    // Update UI state immediately
    state = state.copyWith(
      isRecording: true,
      isContinuous: false,
      recognizedText: '',
      error: null,
    );

    try {
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestRecording();

      if (!granted) {
        debugPrint('RecordingProvider: Coordinator denied recording request');
        state = state.copyWith(
          isRecording: false,
          error: 'Cannot record while audio is playing',
        );
        return;
      }

      state = state.copyWith(isInitializing: true);
      _initASR();
      // Ensure initialization is complete (defensive check)
      if (_asr != null) _asr!.init();
      await _asr!.start();
      state = state.copyWith(isInitializing: false);
      debugPrint('RecordingProvider: Single recording started');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to start single recording: $e');
      state = state.copyWith(
        isRecording: false,
        error: 'Failed to start recording: $e',
      );
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> stopOneShot() async {
    if (!state.isRecording || state.isContinuous) return;

    debugPrint('RecordingProvider: Stopping single recording');
    try {
      await _asr?.stop();
    } catch (e) {
      debugPrint('RecordingProvider: Error during stop: $e');
    } finally {
      // Always update state and release lock, even if stop fails
      state = state.copyWith(isRecording: false, amplitudeHistory: []);
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      debugPrint('RecordingProvider: Single recording stopped (state reset)');
    }
  }

  void clearText() {
    state = state.copyWith(recognizedText: '');
  }

  void clearTextToSubmit() {
    state = state.copyWith(textToSubmit: () => null);
  }

  void _updateAmplitude(double amplitudeDbFS) {
    // Update baseline first
    _updateBaseline(amplitudeDbFS);

    // Update amplitude history (keep last 5 readings for visualization)
    final newHistory = [...state.amplitudeHistory, amplitudeDbFS];
    if (newHistory.length > 5) {
      newHistory.removeAt(0);
    }

    // Calculate bar heights from amplitude history
    final barHeights = _calculateBarHeights(newHistory);

    state = state.copyWith(
      currentAmplitude: amplitudeDbFS,
      amplitudeHistory: newHistory,
      barHeights: barHeights,
    );
  }

  void _updateBaseline(double amplitudeDbFS) {
    // Update EMA baseline with new amplitude
    _currentBaseline =
        _baselineAlpha * amplitudeDbFS +
        (1.0 - _baselineAlpha) * _currentBaseline;
  }

  List<double> _calculateBarHeights(List<double> amplitudes) {
    const minBarHeight = 0.1;
    const maxBarHeight = 1.0;
    const upperLimitDb = -6.0;

    // Convert amplitudes to bar heights using current baseline
    final heights = <double>[];
    for (final amp in amplitudes) {
      double scaledValue = minBarHeight;
      if (amp > _currentBaseline && _currentBaseline < upperLimitDb) {
        scaledValue =
            (amp - _currentBaseline) / (upperLimitDb - _currentBaseline);
      }
      heights.add(scaledValue.clamp(minBarHeight, maxBarHeight));
    }

    return heights;
  }

  // Internal methods called by AudioCoordinator for forced stop/resume
  Future<void> internalStop() async {
    debugPrint('RecordingProvider: internalStop() called by coordinator');
    _stopHealthMonitoring();
    _stopDurationTimer();
    try {
      await _asr?.stop();
    } catch (e) {
      debugPrint('RecordingProvider: Error during internal stop: $e');
    } finally {
      // Always update state, even if stop fails
      state = state.copyWith(
        isRecording: false,
        amplitudeHistory: [], // Clear amplitude history on stop
        // Keep isContinuous flag so we know to resume later
      );
      debugPrint('RecordingProvider: Internal stop completed (state reset)');
    }
  }

  Future<void> internalStart() async {
    debugPrint('RecordingProvider: internalStart() called for auto-resume');
    try {
      state = state.copyWith(isInitializing: true);
      _initASR();
      // Ensure initialization is complete (defensive check)
      if (_asr != null) _asr!.init();
      await _asr!.start();
      state = state.copyWith(
        isInitializing: false,
        isRecording: true,
        error: null,
      );
      // Restart health monitoring and duration timer if this is continuous mode
      if (state.isContinuous) {
        _startHealthMonitoring();
        _startDurationTimer();
      }
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
      onAudioDataReceived: () {
        // Track last audio data time for health monitoring
        _lastAudioDataTime = DateTime.now();
      },
      onAmplitudeChanged: (amplitudeDbFS) {
        _updateAmplitude(amplitudeDbFS);
      },
      onStreamError: (error) {
        debugPrint('RecordingProvider: Audio stream error: $error');
        state = state.copyWith(error: 'Audio stream error: $error');
      },
      onStreamDone: () {
        debugPrint('RecordingProvider: Audio stream closed unexpectedly');
        if (state.isRecording) {
          state = state.copyWith(error: 'Audio stream closed unexpectedly');
        }
      },
    );
    // NOTE: Do NOT call init() here - it's called by initialize() or before start()
  }

  // Health Monitoring Methods

  void _startHealthMonitoring() {
    if (_healthCheckTimer != null) return;

    debugPrint(
      'RecordingProvider: Starting health monitoring (check every 30s)',
    );
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkHealth(),
    );
  }

  void _stopHealthMonitoring() {
    if (_healthCheckTimer == null) return;

    debugPrint('RecordingProvider: Stopping health monitoring');
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _lastAudioDataTime = null;
  }

  void _checkHealth() {
    debugPrint('RecordingProvider: Running health check...');

    // Verify recording state matches expected state
    final isRecordingExpected = state.isRecording && state.isContinuous;
    final isActuallyRecording = state.recordState == RecordState.record;

    if (isRecordingExpected && !isActuallyRecording) {
      debugPrint(
        'RecordingProvider: Health check FAILED - expected recording but recordState is ${state.recordState}',
      );
      _attemptRecovery('Record state mismatch');
      return;
    }

    // Verify audio data is flowing (within last 2 minutes)
    if (_lastAudioDataTime != null) {
      final timeSinceLastData = DateTime.now().difference(_lastAudioDataTime!);
      if (timeSinceLastData > const Duration(minutes: 2)) {
        debugPrint(
          'RecordingProvider: Health check FAILED - no audio data for ${timeSinceLastData.inSeconds}s',
        );
        _attemptRecovery('No audio data for ${timeSinceLastData.inSeconds}s');
        return;
      }
    }

    debugPrint('RecordingProvider: Health check passed');
  }

  // Auto-Recovery Methods

  Future<void> _attemptRecovery(String reason) async {
    _recoveryAttempts++;
    debugPrint(
      'RecordingProvider: Attempting recovery (attempt $_recoveryAttempts/3) - reason: $reason',
    );

    if (_recoveryAttempts > 3) {
      debugPrint(
        'RecordingProvider: Recovery attempts exhausted, degrading gracefully',
      );
      await _gracefulDegradation(reason);
      return;
    }

    // Exponential backoff delays: 0s, 2s, 5s
    final delays = [
      Duration.zero,
      const Duration(seconds: 2),
      const Duration(seconds: 5),
    ];
    final delay = delays[_recoveryAttempts - 1];

    if (delay > Duration.zero) {
      debugPrint(
        'RecordingProvider: Waiting ${delay.inSeconds}s before recovery...',
      );
      await Future<void>.delayed(delay);
    }

    try {
      debugPrint('RecordingProvider: Stopping ASR for recovery...');
      await internalStop();

      debugPrint('RecordingProvider: Restarting ASR...');
      await internalStart();

      debugPrint(
        'RecordingProvider: Recovery attempt $_recoveryAttempts succeeded',
      );
      // On successful recovery, reset counter will happen on next successful start
    } catch (e) {
      debugPrint(
        'RecordingProvider: Recovery attempt $_recoveryAttempts failed: $e',
      );
      // Will retry on next health check if attempts < 3
    }
  }

  Future<void> _gracefulDegradation(String reason) async {
    debugPrint('RecordingProvider: Graceful degradation triggered - $reason');

    // Stop health monitoring
    _stopHealthMonitoring();

    // Stop recording and release resources
    try {
      await _asr?.stop();
    } catch (e) {
      debugPrint('RecordingProvider: Error during graceful stop: $e');
    }

    // Update state to indicate failure
    state = state.copyWith(
      isRecording: false,
      error: 'Listening stopped - could not recover: $reason',
    );

    // Release audio coordinator lock
    await ref.read(audioCoordinatorProvider.notifier).releaseRecording();

    // Switch to Silent mode
    debugPrint(
      'RecordingProvider: Switching to Silent mode due to recovery failure',
    );
    await ref.read(settingsProvider.notifier).updateVoiceMode(VoiceMode.silent);

    // Show error notification to user
    try {
      await _platform.invokeMethod('showErrorNotification', {
        'title': 'Listening Stopped',
        'message': 'Could not recover audio recording: $reason',
      });
      debugPrint('RecordingProvider: Error notification sent');
    } catch (e) {
      debugPrint('RecordingProvider: Failed to show error notification: $e');
    }

    debugPrint('RecordingProvider: Graceful degradation complete');
  }

  // Duration-Based Auto-Shutoff Methods

  void _startDurationTimer() {
    if (_durationTimer != null) return;

    final settings = ref.read(settingsProvider);
    final duration = settings.backgroundListeningDuration.duration;

    debugPrint(
      'RecordingProvider: Starting duration timer (${duration.inMinutes} minutes)',
    );

    _durationTimer = Timer(duration, () async {
      debugPrint(
        'RecordingProvider: Duration timeout reached, switching to Silent mode',
      );
      // Switch to Silent mode, which will trigger _stopContinuous()
      await ref
          .read(settingsProvider.notifier)
          .updateVoiceMode(VoiceMode.silent);
    });
  }

  void _stopDurationTimer() {
    if (_durationTimer == null) return;

    debugPrint('RecordingProvider: Stopping duration timer');
    _durationTimer?.cancel();
    _durationTimer = null;
  }
}
