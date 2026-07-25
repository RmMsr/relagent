import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/utils/logger.dart';
import '/voice/voice_service.dart';

/// Audio focus status from the native platform
enum AudioFocusStatus {
  normal, // We have focus or don't need it
  temporaryLoss, // Phone call, notification sound
  permanentLoss, // User started music app
}

/// Tracks audio focus state for handling interruptions
class AudioFocusState {
  final AudioFocusStatus status;
  final AudioMode? stateBeforeInterruption;

  const AudioFocusState({
    this.status = AudioFocusStatus.normal,
    this.stateBeforeInterruption,
  });

  AudioFocusState copyWith({
    AudioFocusStatus? status,
    AudioMode? Function()? stateBeforeInterruption,
  }) {
    return AudioFocusState(
      status: status ?? this.status,
      stateBeforeInterruption: stateBeforeInterruption != null
          ? stateBeforeInterruption()
          : this.stateBeforeInterruption,
    );
  }
}

/// The ONLY valid audio states - enforces mutual exclusion at the type level
enum AudioMode {
  idle, // Nothing happening
  recording, // ASR active, TTS blocked
  playing, // TTS active, ASR blocked
}

class AudioCoordinatorState {
  final AudioMode mode;
  final AudioFocusState audioFocusState;
  final String? error;

  const AudioCoordinatorState({
    required this.mode,
    this.audioFocusState = const AudioFocusState(),
    this.error,
  });

  factory AudioCoordinatorState.initial() {
    return const AudioCoordinatorState(mode: AudioMode.idle);
  }

  AudioCoordinatorState copyWith({
    AudioMode? mode,
    AudioFocusState? audioFocusState,
    String? Function()? error,
  }) {
    return AudioCoordinatorState(
      mode: mode ?? this.mode,
      audioFocusState: audioFocusState ?? this.audioFocusState,
      error: error != null ? error() : this.error,
    );
  }

  bool get isWaiting =>
      audioFocusState.status == AudioFocusStatus.temporaryLoss;
  bool get canRecord => mode == AudioMode.idle && !isWaiting;
  bool get canPlay => mode == AudioMode.idle && !isWaiting;
  bool get isRecording => mode == AudioMode.recording;
  bool get isPlaying => mode == AudioMode.playing;
  bool get isIdle => mode == AudioMode.idle;
}

final audioCoordinatorProvider =
    NotifierProvider<AudioCoordinator, AudioCoordinatorState>(() {
      return AudioCoordinator();
    });

class AudioCoordinator extends Notifier<AudioCoordinatorState> {
  VoiceService get _voiceService => ref.read(voiceServiceProvider);

  @override
  AudioCoordinatorState build() {
    return AudioCoordinatorState.initial();
  }

  /// Handle audio focus change events from native platform
  Future<void> handleAudioFocusChange(String eventType) async {
    Logger.debug('AudioCoordinator: handleAudioFocusChange($eventType)');

    switch (eventType) {
      case 'temporary_loss':
        _handleTemporaryLoss();
      case 'permanent_loss':
        _handlePermanentLoss();
      case 'gain':
        await _handleGain();
      default:
        Logger.debug('AudioCoordinator: Unknown audio focus event: $eventType');
    }
  }

  void _handleTemporaryLoss() {
    Logger.debug(
      'AudioCoordinator: Temporary audio focus loss - saving state and pausing',
    );

    final currentMode = state.mode;

    state = state.copyWith(
      mode: AudioMode.idle,
      audioFocusState: AudioFocusState(
        status: AudioFocusStatus.temporaryLoss,
        stateBeforeInterruption: currentMode,
      ),
    );
  }

  void _handlePermanentLoss() {
    Logger.debug('AudioCoordinator: Permanent audio focus loss - stopping');

    state = state.copyWith(
      mode: AudioMode.idle,
      audioFocusState: const AudioFocusState(
        status: AudioFocusStatus.permanentLoss,
      ),
    );

    final currentSettings = ref.read(settingsProvider);
    if (currentSettings.voiceMode != VoiceMode.silent) {
      Logger.debug(
        'AudioCoordinator: Changing voice mode to silent due to permanent audio focus loss',
      );
      ref.read(settingsProvider.notifier).updateVoiceMode(VoiceMode.silent);
    }
  }

  Future<void> _handleGain() async {
    Logger.debug('AudioCoordinator: Audio focus regained');

    if (state.audioFocusState.status == AudioFocusStatus.temporaryLoss) {
      final previousMode = state.audioFocusState.stateBeforeInterruption;
      Logger.debug('AudioCoordinator: Restoring previous mode: $previousMode');

      state = state.copyWith(
        audioFocusState: const AudioFocusState(status: AudioFocusStatus.normal),
      );

      if (previousMode == AudioMode.recording) {
        await requestRecording();
      } else if (previousMode == AudioMode.playing) {
        await requestPlayback();
      }
    } else {
      state = state.copyWith(
        audioFocusState: const AudioFocusState(status: AudioFocusStatus.normal),
      );
    }
  }

  /// Request to start recording - returns true if granted
  Future<bool> requestRecording() async {
    Logger.debug(
      'AudioCoordinator: requestRecording() - current mode: ${state.mode}',
    );

    if (state.mode == AudioMode.playing) {
      Logger.debug('AudioCoordinator: Must stop playback first');
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      await _resetAudioSession();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (state.mode != AudioMode.idle) {
      Logger.debug('AudioCoordinator: Cannot record, mode is ${state.mode}');
      return false;
    }

    await _voiceService.configureAudioSessionForRecording();

    if (!ref.mounted) return false;

    Logger.debug('AudioCoordinator: Transitioning to recording mode');
    state = const AudioCoordinatorState(mode: AudioMode.recording);

    Logger.debug('AudioCoordinator: Recording lock acquired');
    return true;
  }

  /// Request to start playback - returns true if granted
  Future<bool> requestPlayback() async {
    Logger.debug(
      'AudioCoordinator: requestPlayback() - current mode: ${state.mode}',
    );

    if (state.mode == AudioMode.recording) {
      Logger.debug('AudioCoordinator: Must stop recording first');
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      await _resetAudioSession();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (state.mode != AudioMode.idle) {
      Logger.debug('AudioCoordinator: Cannot play, mode is ${state.mode}');
      return false;
    }

    await _voiceService.configureAudioSessionForPlayback();

    if (!ref.mounted) return false;

    Logger.debug('AudioCoordinator: Transitioning to playing mode');
    state = const AudioCoordinatorState(mode: AudioMode.playing);

    Logger.debug('AudioCoordinator: Playback lock acquired');
    return true;
  }

  Future<void> releaseRecording() async {
    Logger.debug('AudioCoordinator: releaseRecording() - mode: ${state.mode}');
    if (state.mode != AudioMode.recording) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    final settings = ref.read(settingsProvider);
    if (settings.continuousVoiceEnabled && settings.isContinuousRecording) {
      Logger.debug('AudioCoordinator: Auto-resuming continuous recording');
      await requestRecording();
    }
  }

  Future<void> releasePlayback() async {
    Logger.debug('AudioCoordinator: releasePlayback() - mode: ${state.mode}');
    if (state.mode != AudioMode.playing) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    await Future<void>.delayed(const Duration(milliseconds: 100));

    if (!ref.mounted) return;

    if (state.mode == AudioMode.idle) {
      final settings = ref.read(settingsProvider);
      if (settings.continuousVoiceEnabled && settings.isContinuousRecording) {
        Logger.debug('AudioCoordinator: Auto-resuming continuous recording');
        await requestRecording();
      }
    }
  }

  Future<void> _resetAudioSession() async {
    try {
      Logger.debug('AudioCoordinator: Resetting audio session for clean routing');
      await _voiceService.deactivateAudioSession();
      Logger.debug('AudioCoordinator: Audio session deactivated');

      await Future<void>.delayed(const Duration(milliseconds: 100));

      await _voiceService.activateAudioSession();
      Logger.debug('AudioCoordinator: Audio session reactivated');
    } catch (e) {
      Logger.debug('AudioCoordinator: Failed to reset audio session: $e');
    }
  }
}
