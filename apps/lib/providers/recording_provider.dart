import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/model_download_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/speech_recognition/recording_target.dart';
import '/voice/model_resolver.dart';
import '/voice/voice_service.dart';
import '../utils/logger.dart';

class RecordingState {
  final bool isRecording;
  final bool isContinuous;
  final bool isInitializing;
  final String recognizedText;
  final String? textToSubmit;
  final String? error;
  final AudioRecordingStatus recordingStatus;
  final double? currentAmplitude;
  final List<double> amplitudeHistory;
  final List<double> barHeights;

  const RecordingState({
    this.isRecording = false,
    this.isContinuous = false,
    this.isInitializing = false,
    this.recognizedText = '',
    this.textToSubmit,
    this.error,
    this.recordingStatus = AudioRecordingStatus.stopped,
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
    AudioRecordingStatus? recordingStatus,
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
      recordingStatus: recordingStatus ?? this.recordingStatus,
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
  VoiceService get _voiceService => ref.read(voiceServiceProvider);

  // Track intentional stops to avoid false "unexpected closure" errors
  bool _stoppingIntentionally = false;
  // Track whether ASR has been initialized at least once (to show overlay only on first init)
  bool _asrInitialized = false;
  // Target management
  RecordingTarget? _activeTarget;

  // Health monitoring fields
  Timer? _healthCheckTimer;
  DateTime? _lastAudioDataTime;

  // Auto-recovery fields
  int _recoveryAttempts = 0;

  // Duration-based shutoff field
  Timer? _durationTimer;

  // Baseline calculation for volume visualization
  double _currentBaseline = -60.0;
  static const double _baselineAlpha = 0.05;
  static const double _baselineDecayAlpha = 0.02;
  static const double _minBaseline = -80.0;
  static const double _maxBaseline = -30.0;
  DateTime? _lastSignificantAudioTime;

  @override
  RecordingState build() {
    ref.onDispose(() {
      _stopHealthMonitoring();
      _stopDurationTimer();
    });

    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.selectedAsrModelId != next.selectedAsrModelId) {
        _asrInitialized = false;
      }
      if (previous?.voiceMode != next.voiceMode) {
        _handleVoiceModeChanged(previous?.voiceMode, next.voiceMode);
      }
    });

    ref.listen<AudioCoordinatorState>(audioCoordinatorProvider, (
      previous,
      next,
    ) async {
      if (state.isRecording &&
          previous?.mode == AudioMode.recording &&
          next.mode != AudioMode.recording) {
        Logger.debug(
          'RecordingProvider: Coordinator forced stop, stopping recording',
        );
        await internalStop();
      }

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

    // Restart ASR when selected model finishes downloading (startup race fix)
    ref.listen<ModelDownloadState>(modelDownloadProvider, (previous, next) async {
      final selectedId = ref.read(settingsProvider).selectedAsrModelId;
      if (selectedId != null &&
          !(previous?.isDownloaded(selectedId) ?? false) &&
          next.isDownloaded(selectedId) &&
          state.isContinuous &&
          state.isRecording) {
        Logger.debug(
          'RecordingProvider: Selected ASR model now downloaded, restarting...',
        );
        await internalStop();
        await internalStart();
      }
    });

    return RecordingState.initial();
  }

  void initialize() {
    Logger.debug('RecordingProvider: initializing ASR...');
    state = state.copyWith(isInitializing: true);
    _voiceService.initAudioRecorder();
    state = state.copyWith(isInitializing: false);
  }

  void checkAutoStart() {
    final settings = ref.read(settingsProvider);
    if (!settings.continuousVoiceEnabled) return;
    if (settings.voiceMode == VoiceMode.listening ||
        settings.voiceMode == VoiceMode.conversation) {
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

    if (!wasContinuous && isContinuous &&
        !ref.read(settingsProvider).continuousVoiceEnabled) {
      Logger.debug(
        'RecordingProvider: Continuous voice disabled, ignoring mode change',
      );
      return;
    }

    if (!wasContinuous && isContinuous) {
      if (state.isRecording && !state.isContinuous) {
        Logger.debug(
          'RecordingProvider: Upgrading dictation to continuous mode (keeping recording active)',
        );
        state = state.copyWith(isContinuous: true);
        _startHealthMonitoring();
        _startDurationTimer();
      } else {
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

    _resetAudioLevelTracking();

    state = state.copyWith(isRecording: true, isContinuous: true, error: null);

    try {
      final granted = await ref
          .read(audioCoordinatorProvider.notifier)
          .requestRecording();

      if (!granted) {
        Logger.debug('RecordingProvider: Coordinator denied recording request');
        state = state.copyWith(isRecording: false, isContinuous: false);
        return;
      }

      await _startASRWithInit();
      _recoveryAttempts = 0;
      _startHealthMonitoring();
      _startDurationTimer();
      Logger.debug('RecordingProvider: Continuous recording started');
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
      await _voiceService.stopRecording();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during stop: $e');
    } finally {
      _stoppingIntentionally = false;
      state = state.copyWith(
        isRecording: false,
        isContinuous: false,
        recognizedText: '',
      );
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      Logger.debug(
        'RecordingProvider: Continuous recording stopped (state reset)',
      );
      _activeTarget?.onRecordingStopped();
    }
  }

  Future<void> startDictation() async {
    if (state.isRecording) return;

    if (_activeTarget == null) {
      Logger.debug(
        'RecordingProvider: WARNING - Starting dictation without active target',
      );
    }

    Logger.debug('RecordingProvider: Starting dictation mode');

    _resetAudioLevelTracking();

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

      await _startASRWithInit();
      Logger.debug('RecordingProvider: Dictation mode started');
      _activeTarget?.onRecordingStarted();
    } catch (e) {
      Logger.debug('RecordingProvider: Failed to start dictation mode: $e');
      final errorMsg = 'Failed to start recording: $e';
      state = state.copyWith(isRecording: false, error: errorMsg);
      _activeTarget?.onError(errorMsg);
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  Future<void> stopDictation() async {
    if (!state.isRecording || state.isContinuous) return;

    Logger.debug('RecordingProvider: Stopping dictation mode');
    _stoppingIntentionally = true;
    try {
      await _voiceService.stopRecording();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during stop: $e');
    } finally {
      _stoppingIntentionally = false;
      state = state.copyWith(isRecording: false, amplitudeHistory: []);
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
      Logger.debug('RecordingProvider: Dictation mode stopped (state reset)');
      _activeTarget?.onRecordingStopped();
    }
  }

  void clearText() {
    state = state.copyWith(recognizedText: '');
  }

  void clearTextToSubmit() {
    state = state.copyWith(textToSubmit: () => null);
  }

  void registerTarget(RecordingTarget target) {
    if (_activeTarget != null) {
      Logger.debug(
        'RecordingProvider: Replacing existing target with new target',
      );
    }
    _activeTarget = target;
    Logger.debug('RecordingProvider: Target registered');
  }

  void unregisterTarget(RecordingTarget target) {
    if (_activeTarget == target) {
      _activeTarget = null;
      Logger.debug('RecordingProvider: Target unregistered');
    }
  }

  void _updateAmplitude(double amplitudeDbFS) {
    final oldBaseline = _currentBaseline;

    _updateBaseline(amplitudeDbFS);

    if ((_currentBaseline - oldBaseline).abs() > 1.0) {
      Logger.debug(
        'RecordingProvider: Baseline updated from ${oldBaseline.toStringAsFixed(1)}dB to ${_currentBaseline.toStringAsFixed(1)}dB (input: ${amplitudeDbFS.toStringAsFixed(1)}dB)',
      );
    }

    final newHistory = [...state.amplitudeHistory, amplitudeDbFS];
    if (newHistory.length > 5) {
      newHistory.removeAt(0);
    }

    final barHeights = _calculateBarHeights(newHistory);

    state = state.copyWith(
      currentAmplitude: amplitudeDbFS,
      amplitudeHistory: newHistory,
      barHeights: barHeights,
    );
  }

  void _updateBaseline(double amplitudeDbFS) {
    final now = DateTime.now();

    final significantThreshold = _currentBaseline + 10.0;
    final isSignificantAudio = amplitudeDbFS > significantThreshold;

    if (isSignificantAudio) {
      _currentBaseline =
          _baselineAlpha * amplitudeDbFS +
          (1.0 - _baselineAlpha) * _currentBaseline;
      _lastSignificantAudioTime = now;
    } else if (_lastSignificantAudioTime != null) {
      final timeSinceSignificant = now.difference(_lastSignificantAudioTime!);
      if (timeSinceSignificant.inSeconds > 2) {
        _currentBaseline =
            _baselineDecayAlpha * _minBaseline +
            (1.0 - _baselineDecayAlpha) * _currentBaseline;
      }
    }

    _currentBaseline = _currentBaseline.clamp(_minBaseline, _maxBaseline);
  }

  List<double> _calculateBarHeights(List<double> amplitudes) {
    const minBarHeight = 0.1;
    const maxBarHeight = 1.0;
    const upperLimitDb = -6.0;
    const minDynamicRangeDb = 20.0;

    final effectiveUpperLimit = _currentBaseline + minDynamicRangeDb;
    final usedUpperLimit = effectiveUpperLimit > upperLimitDb
        ? upperLimitDb
        : effectiveUpperLimit;

    final heights = <double>[];
    for (final amp in amplitudes) {
      double scaledValue = minBarHeight;

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

  Future<void> internalStop() async {
    Logger.debug('RecordingProvider: internalStop() called by coordinator');
    _stopHealthMonitoring();
    _stopDurationTimer();
    _stoppingIntentionally = true;
    try {
      await _voiceService.stopRecording();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during internal stop: $e');
    } finally {
      _stoppingIntentionally = false;
      state = state.copyWith(isRecording: false, amplitudeHistory: []);
      Logger.debug('RecordingProvider: Internal stop completed (state reset)');
    }
  }

  Future<void> internalStart() async {
    Logger.debug('RecordingProvider: internalStart() called for auto-resume');
    try {
      _resetAudioLevelTracking();

      await _startASRWithInit();
      state = state.copyWith(
        isRecording: true,
        error: null,
      );
      if (state.isContinuous) {
        _startHealthMonitoring();
        _startDurationTimer();
      }
      Logger.debug('RecordingProvider: Internal start completed');
    } catch (e) {
      Logger.debug('RecordingProvider: Internal start failed: $e');
      state = state.copyWith(error: 'Failed to resume recording: $e');
      await ref.read(audioCoordinatorProvider.notifier).releaseRecording();
    }
  }

  /// Yields until after the current frame is built and submitted to the raster
  /// thread. After this point the raster thread renders the overlay
  /// independently, so blocking the Dart thread does not prevent the user from
  /// seeing the initialization message.
  Future<void> _waitForFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
    return completer.future;
  }

  /// Starts ASR, showing an initialization overlay on the first call.
  /// Subsequent calls (model already loaded) start immediately with no overlay.
  Future<void> _startASRWithInit() async {
    final needsOverlay = !_asrInitialized;
    if (needsOverlay) {
      state = state.copyWith(isInitializing: true);
      await _waitForFrame();
    }
    try {
      await _startASR();
      _asrInitialized = true;
    } finally {
      if (needsOverlay) {
        state = state.copyWith(isInitializing: false);
      }
    }
  }

  Future<void> _startASR() async {
    final settings = ref.read(settingsProvider);
    final downloadState = ref.read(modelDownloadProvider);
    final asrMetadata = await resolveAsrMetadata(settings, downloadState);

    if (asrMetadata == null) {
      throw Exception(
        'No ASR model selected. Download one in Settings.',
      );
    }

    Logger.debug(
      'RecordingProvider: Using ASR model: ${asrMetadata.modelId}',
    );

    await _voiceService.startRecording(
      asrMetadata: asrMetadata,
      onTextRecognized: (text) {
        Logger.debug(
          'RecordingProvider: textRecognized - "$text" (continuous: ${state.isContinuous}, target: ${_activeTarget != null})',
        );
        state = state.copyWith(recognizedText: text);
        if (_activeTarget != null) {
          _activeTarget!.onTextRecognized(text);
        } else {
          Logger.debug('RecordingProvider: No active target to receive text');
        }
      },
      onTextFinished: () {
        Logger.debug(
          'RecordingProvider: textFinished - recognizedText: "${state.recognizedText}" (continuous: ${state.isContinuous})',
        );
        if (state.isContinuous && state.recognizedText.isNotEmpty) {
          final textToSend = state.recognizedText;
          Logger.debug(
            'RecordingProvider: Submitting text in continuous mode: "$textToSend"',
          );
          state = state.copyWith(
            recognizedText: '',
            textToSubmit: () => textToSend,
          );
        }
        // Always notify target: continuous mode submits, dictation mode
        // commits the utterance to baseline so the next one appends to it.
        _activeTarget?.onTextFinished();
      },
      onStatusChanged: (recordingStatus) {
        state = state.copyWith(recordingStatus: recordingStatus);
      },
      onAudioDataReceived: () {
        _lastAudioDataTime = DateTime.now();
      },
      onAmplitudeChanged: (amplitudeDbFS) {
        _updateAmplitude(amplitudeDbFS);
      },
      onStreamError: (Object error) {
        Logger.debug('RecordingProvider: Audio stream error: $error');
        final errorMsg = 'Audio stream error: $error';
        state = state.copyWith(error: errorMsg);
        _activeTarget?.onError(errorMsg);
      },
      onStreamDone: () {
        if (!_stoppingIntentionally) {
          Logger.debug('RecordingProvider: Audio stream closed unexpectedly');
          if (state.isRecording) {
            const errorMsg = 'Audio stream closed unexpectedly';
            state = state.copyWith(error: errorMsg);
            _activeTarget?.onError(errorMsg);
          }
        } else {
          Logger.debug(
            'RecordingProvider: Audio stream closed (intentional stop)',
          );
        }
      },
    );
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

    final isRecordingExpected = state.isRecording && state.isContinuous;
    final isActuallyRecording =
        state.recordingStatus == AudioRecordingStatus.recording;

    if (isRecordingExpected && !isActuallyRecording) {
      Logger.debug(
        'RecordingProvider: Health check FAILED - expected recording but recordingStatus is ${state.recordingStatus}',
      );
      _attemptRecovery('Record state mismatch');
      return;
    }

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
    } catch (e) {
      Logger.debug(
        'RecordingProvider: Recovery attempt $_recoveryAttempts failed: $e',
      );
    }
  }

  Future<void> _gracefulDegradation(String reason) async {
    Logger.debug('RecordingProvider: Graceful degradation triggered - $reason');

    _stopHealthMonitoring();

    try {
      await _voiceService.stopRecording();
    } catch (e) {
      Logger.debug('RecordingProvider: Error during graceful stop: $e');
    }

    state = state.copyWith(
      isRecording: false,
      error: 'Listening stopped - could not recover: $reason',
    );

    await ref.read(audioCoordinatorProvider.notifier).releaseRecording();

    Logger.debug(
      'RecordingProvider: Switching to Silent mode due to recovery failure',
    );
    await ref.read(settingsProvider.notifier).updateVoiceMode(VoiceMode.silent);

    await _voiceService.showErrorNotification(
      'Listening Stopped',
      'Could not recover audio recording: $reason',
    );

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
    _currentBaseline = -60.0;
    _lastSignificantAudioTime = null;

    state = state.copyWith(barHeights: []);

    Logger.debug('RecordingProvider: Reset audio level tracking baseline');
  }
}
