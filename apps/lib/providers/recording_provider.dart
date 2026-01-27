import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
import '/speech_recognition/recording_target.dart';
import '/speech_recognition/services.dart';
import '../utils/logger.dart';

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

  // Target management
  RecordingTarget? _activeTarget;

  // Track intentional stops to avoid false "unexpected closure" errors
  bool _stoppingIntentionally = false;

  // Health monitoring fields
  Timer? _healthCheckTimer;
  DateTime? _lastAudioDataTime;

  // Auto-recovery fields
  int _recoveryAttempts = 0;

  // Duration-based shutoff field
  Timer? _durationTimer;

  // Baseline calculation for volume visualization
  double _currentBaseline = -60.0; // Initial baseline
  static const double _baselineAlpha =
      0.05; // Reduced EMA smoothing factor for better responsiveness
  static const double _baselineDecayAlpha =
      0.02; // Decay factor for baseline during silence
  static const double _minBaseline = -80.0; // Minimum baseline level
  static const double _maxBaseline = -30.0; // Maximum baseline level
  DateTime? _lastSignificantAudioTime;

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
        Logger.debug(
          'RecordingProvider: Coordinator forced stop, stopping recording',
        );
        await internalStop();
      }

      // Handle auto-resume (coordinator finished playing, resuming continuous recording)
      if (!state.isRecording &&
          state.isContinuous &&
          previous?.mode != AudioMode.recording &&
          next.mode == AudioMode.recording) {
        Logger.debug(
          'RecordingProvider: Coordinator auto-resumed, restarting recording',
        );
        await internalStart();
      }
    });

    return RecordingState.initial();
  }

  /// Called by initialization code (e.g., startup sequence) to pre-initialize ASR
  void initialize() {
    Logger.debug('RecordingProvider: initializing ASR...');
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
    Logger.debug(
      'RecordingProvider: Voice mode changed from $oldMode to $newMode',
    );

    final wasContinuous =
        oldMode == VoiceMode.listening || oldMode == VoiceMode.conversation;
    final isContinuous =
        newMode == VoiceMode.listening || newMode == VoiceMode.conversation;

    if (!wasContinuous && isContinuous) {
      // Switching TO continuous mode
      if (state.isRecording && !state.isContinuous) {
        // Already recording in dictation mode - just update the flag
        Logger.debug(
          'RecordingProvider: Upgrading dictation to continuous mode (keeping recording active)',
        );
        state = state.copyWith(isContinuous: true);
        _startHealthMonitoring();
        _startDurationTimer();
      } else {
        // Not recording yet - start fresh
        Logger.debug('RecordingProvider: Switching to continuous mode');
        _startContinuous();
      }
    } else if (wasContinuous && !isContinuous) {
      Logger.debug(
        'RecordingProvider: Switching from continuous mode (stopping)',
      );
      _stopContinuous();
    }
  }

  Future<void> _startContinuous() async {
    if (state.isContinuous) return;

    Logger.debug('RecordingProvider: Starting continuous recording');

    // Reset baseline and tracking for new recording session
    _resetAudioLevelTracking();

    // Update UI state immediately to show recording has started
    state = state.copyWith(isRecording: true, isContinuous: true, error: null);

    try {
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestRecording();

      if (!granted) {
        Logger.debug('RecordingProvider: Coordinator denied recording request');
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
      Logger.debug('RecordingProvider: Continuous recording started');
      // Notify target that recording started
      _activeTarget?.onRecordingStarted();
    } catch (e) {
      Logger.debug(
        'RecordingProvider: Failed to start continuous recording: $e',
      );
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

    Logger.debug('RecordingProvider: Stopping continuous recording');
    _stopHealthMonitoring();
    _stopDurationTimer();
    _stoppingIntentionally = true;
    try {
      await _asr?.stop();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during stop: $e');
    } finally {
      _stoppingIntentionally = false;
      // Always update state and release lock, even if stop fails
      state = state.copyWith(
        isRecording: false,
        isContinuous: false,
        recognizedText: '',
      );
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      Logger.debug(
        'RecordingProvider: Continuous recording stopped (state reset)',
      );
      // Notify target that recording stopped
      _activeTarget?.onRecordingStopped();
    }
  }

  Future<void> startDictation() async {
    if (state.isRecording) return;

    // Defensive check: warn if no target registered
    if (_activeTarget == null) {
      Logger.debug(
        'RecordingProvider: WARNING - Starting dictation without active target',
      );
    }

    Logger.debug('RecordingProvider: Starting dictation mode');

    // Reset baseline for new recording session
    _resetAudioLevelTracking();

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
        Logger.debug('RecordingProvider: Coordinator denied recording request');
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
      Logger.debug('RecordingProvider: Dictation mode started');
      // Notify target that recording started
      _activeTarget?.onRecordingStarted();
    } catch (e) {
      Logger.debug('RecordingProvider: Failed to start dictation mode: $e');
      final errorMsg = 'Failed to start recording: $e';
      state = state.copyWith(isRecording: false, error: errorMsg);
      // Notify target of error
      _activeTarget?.onError(errorMsg);
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> stopDictation() async {
    if (!state.isRecording || state.isContinuous) return;

    Logger.debug('RecordingProvider: Stopping dictation mode');
    _stoppingIntentionally = true;
    try {
      await _asr?.stop();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during stop: $e');
    } finally {
      _stoppingIntentionally = false;
      // Always update state and release lock, even if stop fails
      state = state.copyWith(isRecording: false, amplitudeHistory: []);
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      Logger.debug('RecordingProvider: Dictation mode stopped (state reset)');
      // Notify target that recording stopped
      _activeTarget?.onRecordingStopped();
    }
  }

  void clearText() {
    state = state.copyWith(recognizedText: '');
  }

  void clearTextToSubmit() {
    state = state.copyWith(textToSubmit: () => null);
  }

  /// Register a target to receive speech recognition events.
  ///
  /// Only one target can be active at a time. If a target is already registered,
  /// this method will log a debug message and replace it with the new target.
  void registerTarget(RecordingTarget target) {
    if (_activeTarget != null) {
      Logger.debug(
        'RecordingProvider: Replacing existing target with new target',
      );
    }
    _activeTarget = target;
    Logger.debug('RecordingProvider: Target registered');
  }

  /// Unregister the active recording target.
  ///
  /// If the provided target is not the active target, this is a no-op.
  /// This prevents stale references when widgets are disposed.
  void unregisterTarget(RecordingTarget target) {
    if (_activeTarget == target) {
      _activeTarget = null;
      Logger.debug('RecordingProvider: Target unregistered');
    }
  }

  void _updateAmplitude(double amplitudeDbFS) {
    // Store old baseline for debugging
    final oldBaseline = _currentBaseline;

    // Update baseline first
    _updateBaseline(amplitudeDbFS);

    // Debug log baseline changes
    if ((_currentBaseline - oldBaseline).abs() > 1.0) {
      Logger.debug(
        'RecordingProvider: Baseline updated from ${oldBaseline.toStringAsFixed(1)}dB to ${_currentBaseline.toStringAsFixed(1)}dB (input: ${amplitudeDbFS.toStringAsFixed(1)}dB)',
      );
    }

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
    final now = DateTime.now();

    // Define significant audio threshold (10dB above current baseline)
    final significantThreshold = _currentBaseline + 10.0;
    final isSignificantAudio = amplitudeDbFS > significantThreshold;

    if (isSignificantAudio) {
      // Fast adaptation when there's significant audio
      _currentBaseline =
          _baselineAlpha * amplitudeDbFS +
          (1.0 - _baselineAlpha) * _currentBaseline;
      _lastSignificantAudioTime = now;
    } else if (_lastSignificantAudioTime != null) {
      // Apply decay during silence periods
      final timeSinceSignificant = now.difference(_lastSignificantAudioTime!);
      if (timeSinceSignificant.inSeconds > 2) {
        // Gradually decay baseline towards minimum during extended silence
        _currentBaseline =
            _baselineDecayAlpha * _minBaseline +
            (1.0 - _baselineDecayAlpha) * _currentBaseline;
      }
    }

    // Clamp baseline to reasonable bounds
    _currentBaseline = _currentBaseline.clamp(_minBaseline, _maxBaseline);
  }

  List<double> _calculateBarHeights(List<double> amplitudes) {
    const minBarHeight = 0.1;
    const maxBarHeight = 1.0;
    const upperLimitDb = -6.0;
    const minDynamicRangeDb =
        20.0; // Minimum dynamic range to ensure responsiveness

    // Calculate effective upper limit to maintain dynamic range
    final effectiveUpperLimit = _currentBaseline + minDynamicRangeDb;
    final usedUpperLimit = effectiveUpperLimit > upperLimitDb
        ? upperLimitDb
        : effectiveUpperLimit;

    // Convert amplitudes to bar heights using current baseline
    final heights = <double>[];
    for (final amp in amplitudes) {
      double scaledValue = minBarHeight;

      // Only calculate if amplitude is above baseline
      if (amp > _currentBaseline) {
        final dynamicRange = usedUpperLimit - _currentBaseline;
        if (dynamicRange > 0) {
          scaledValue = (amp - _currentBaseline) / dynamicRange;
        }
      }

      heights.add(scaledValue.clamp(minBarHeight, maxBarHeight));
    }

    return heights;
  }

  // Internal methods called by AudioCoordinator for forced stop/resume
  Future<void> internalStop() async {
    Logger.debug('RecordingProvider: internalStop() called by coordinator');
    _stopHealthMonitoring();
    _stopDurationTimer();
    _stoppingIntentionally = true;
    try {
      await _asr?.stop();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during internal stop: $e');
    } finally {
      _stoppingIntentionally = false;
      // Always update state, even if stop fails
      state = state.copyWith(
        isRecording: false,
        amplitudeHistory: [], // Clear amplitude history on stop
        // Keep isContinuous flag so we know to resume later
      );
      Logger.debug('RecordingProvider: Internal stop completed (state reset)');
    }
  }

  Future<void> internalStart() async {
    Logger.debug('RecordingProvider: internalStart() called for auto-resume');
    try {
      // Reset baseline for resumed recording session
      _resetAudioLevelTracking();

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
      Logger.debug('RecordingProvider: Internal start completed');
    } catch (e) {
      Logger.debug('RecordingProvider: Internal start failed: $e');
      state = state.copyWith(error: 'Failed to resume recording: $e');
      // Release coordinator lock on failure
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  void _initASR() {
    if (_asr != null) return;

    _asr = ASR(
      textRecognized: (text) {
        Logger.debug(
          'RecordingProvider: textRecognized - "$text" (continuous: ${state.isContinuous}, target: ${_activeTarget != null})',
        );
        state = state.copyWith(recognizedText: text);
        // Route to active target
        if (_activeTarget != null) {
          _activeTarget!.onTextRecognized(text);
        } else {
          Logger.debug('RecordingProvider: No active target to receive text');
        }
      },
      textFinished: () {
        Logger.debug(
          'RecordingProvider: textFinished - recognizedText: "${state.recognizedText}" (continuous: ${state.isContinuous})',
        );
        // Endpoint detected (pause in speech)
        // In continuous mode: submit text automatically
        // In dictation mode: target decides when to submit (e.g., user presses Enter)
        if (state.isContinuous && state.recognizedText.isNotEmpty) {
          final textToSend = state.recognizedText;
          Logger.debug(
            'RecordingProvider: Submitting text in continuous mode: "$textToSend"',
          );
          state = state.copyWith(
            recognizedText: '',
            textToSubmit: () => textToSend,
          );
          // Notify target that text is finished
          if (_activeTarget != null) {
            _activeTarget!.onTextFinished();
          } else {
            Logger.debug(
              'RecordingProvider: No active target for textFinished',
            );
          }
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
      onStreamError: (Object error) {
        Logger.debug('RecordingProvider: Audio stream error: $error');
        final errorMsg = 'Audio stream error: $error';
        state = state.copyWith(error: errorMsg);
        // Notify target of error
        _activeTarget?.onError(errorMsg);
      },
      onStreamDone: () {
        // Only log error if this wasn't an intentional stop
        if (!_stoppingIntentionally) {
          Logger.debug('RecordingProvider: Audio stream closed unexpectedly');
          if (state.isRecording) {
            const errorMsg = 'Audio stream closed unexpectedly';
            state = state.copyWith(error: errorMsg);
            // Notify target of error
            _activeTarget?.onError(errorMsg);
          }
        } else {
          Logger.debug(
            'RecordingProvider: Audio stream closed (intentional stop)',
          );
        }
      },
    );
    // NOTE: Do NOT call init() here - it's called by initialize() or before start()
  }

  // Health Monitoring Methods

  void _startHealthMonitoring() {
    if (_healthCheckTimer != null) return;

    Logger.debug(
      'RecordingProvider: Starting health monitoring (check every 30s)',
    );
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkHealth(),
    );
  }

  void _stopHealthMonitoring() {
    if (_healthCheckTimer == null) return;

    Logger.debug('RecordingProvider: Stopping health monitoring');
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _lastAudioDataTime = null;
  }

  void _checkHealth() {
    Logger.debug('RecordingProvider: Running health check...');

    // Verify recording state matches expected state
    final isRecordingExpected = state.isRecording && state.isContinuous;
    final isActuallyRecording = state.recordState == RecordState.record;

    if (isRecordingExpected && !isActuallyRecording) {
      Logger.debug(
        'RecordingProvider: Health check FAILED - expected recording but recordState is ${state.recordState}',
      );
      _attemptRecovery('Record state mismatch');
      return;
    }

    // Verify audio data is flowing (within last 2 minutes)
    if (_lastAudioDataTime != null) {
      final timeSinceLastData = DateTime.now().difference(_lastAudioDataTime!);
      if (timeSinceLastData > const Duration(minutes: 2)) {
        Logger.debug(
          'RecordingProvider: Health check FAILED - no audio data for ${timeSinceLastData.inSeconds}s',
        );
        _attemptRecovery('No audio data for ${timeSinceLastData.inSeconds}s');
        return;
      }
    }

    Logger.debug('RecordingProvider: Health check passed');
  }

  // Auto-Recovery Methods

  Future<void> _attemptRecovery(String reason) async {
    _recoveryAttempts++;
    Logger.debug(
      'RecordingProvider: Attempting recovery (attempt $_recoveryAttempts/3) - reason: $reason',
    );

    if (_recoveryAttempts > 3) {
      Logger.debug(
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
      Logger.debug(
        'RecordingProvider: Waiting ${delay.inSeconds}s before recovery...',
      );
      await Future<void>.delayed(delay);
    }

    try {
      Logger.debug('RecordingProvider: Stopping ASR for recovery...');
      await internalStop();

      Logger.debug('RecordingProvider: Restarting ASR...');
      await internalStart();

      Logger.debug(
        'RecordingProvider: Recovery attempt $_recoveryAttempts succeeded',
      );
      // On successful recovery, reset counter will happen on next successful start
    } catch (e) {
      Logger.debug(
        'RecordingProvider: Recovery attempt $_recoveryAttempts failed: $e',
      );
      // Will retry on next health check if attempts < 3
    }
  }

  Future<void> _gracefulDegradation(String reason) async {
    Logger.debug('RecordingProvider: Graceful degradation triggered - $reason');

    // Stop health monitoring
    _stopHealthMonitoring();

    // Stop recording and release resources
    try {
      await _asr?.stop();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during graceful stop: $e');
    }

    // Update state to indicate failure
    state = state.copyWith(
      isRecording: false,
      error: 'Listening stopped - could not recover: $reason',
    );

    // Release audio coordinator lock
    await ref.read(audioCoordinatorProvider.notifier).releaseRecording();

    // Switch to Silent mode
    Logger.debug(
      'RecordingProvider: Switching to Silent mode due to recovery failure',
    );
    await ref.read(settingsProvider.notifier).updateVoiceMode(VoiceMode.silent);

    // Show error notification to user
    try {
      await _platform.invokeMethod('showErrorNotification', {
        'title': 'Listening Stopped',
        'message': 'Could not recover audio recording: $reason',
      });
      Logger.debug('RecordingProvider: Error notification sent');
    } catch (e) {
      Logger.debug('RecordingProvider: Failed to show error notification: $e');
    }

    Logger.debug('RecordingProvider: Graceful degradation complete');
  }

  // Duration-Based Auto-Shutoff Methods

  void _startDurationTimer() {
    if (_durationTimer != null) return;

    final settings = ref.read(settingsProvider);
    final duration = settings.backgroundListeningDuration.duration;

    Logger.debug(
      'RecordingProvider: Starting duration timer (${duration.inMinutes} minutes)',
    );

    _durationTimer = Timer(duration, () async {
      Logger.debug(
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

    Logger.debug('RecordingProvider: Stopping duration timer');
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _resetAudioLevelTracking() {
    _currentBaseline = -60.0; // Reset to initial baseline
    _lastSignificantAudioTime = null; // Reset significant audio tracking

    // Start with empty bar heights - let real audio drive the visualization
    state = state.copyWith(barHeights: []);

    Logger.debug('RecordingProvider: Reset audio level tracking baseline');
  }
}
