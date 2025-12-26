import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';

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
  @override
  AudioCoordinatorState build() {
    return AudioCoordinatorState.initial();
  }

  /// Handle audio focus change events from native platform
  void handleAudioFocusChange(String eventType) {
    debugPrint('AudioCoordinator: handleAudioFocusChange($eventType)');

    switch (eventType) {
      case 'temporary_loss':
        _handleTemporaryLoss();
      case 'permanent_loss':
        _handlePermanentLoss();
      case 'gain':
        _handleGain();
      default:
        debugPrint('AudioCoordinator: Unknown audio focus event: $eventType');
    }
  }

  void _handleTemporaryLoss() {
    debugPrint(
      'AudioCoordinator: Temporary audio focus loss - saving state and pausing',
    );

    // Save current mode for restoration
    final currentMode = state.mode;

    // Transition to idle (this will trigger Recording/Playback to stop)
    state = state.copyWith(
      mode: AudioMode.idle,
      audioFocusState: AudioFocusState(
        status: AudioFocusStatus.temporaryLoss,
        stateBeforeInterruption: currentMode,
      ),
    );
  }

  void _handlePermanentLoss() {
    debugPrint('AudioCoordinator: Permanent audio focus loss - stopping');

    // Transition to idle
    state = state.copyWith(
      mode: AudioMode.idle,
      audioFocusState: const AudioFocusState(
        status: AudioFocusStatus.permanentLoss,
      ),
    );

    // Update SettingsProvider to change voice mode to silent
    final currentSettings = ref.read(settingsProvider);
    if (currentSettings.voiceMode != VoiceMode.silent) {
      debugPrint(
        'AudioCoordinator: Changing voice mode to silent due to permanent audio focus loss',
      );
      ref.read(settingsProvider.notifier).updateVoiceMode(VoiceMode.silent);
    }
  }

  void _handleGain() {
    debugPrint('AudioCoordinator: Audio focus regained');

    // Only restore if we were temporarily interrupted
    if (state.audioFocusState.status == AudioFocusStatus.temporaryLoss) {
      final previousMode = state.audioFocusState.stateBeforeInterruption;
      debugPrint('AudioCoordinator: Restoring previous mode: $previousMode');

      // Clear waiting state
      state = state.copyWith(
        audioFocusState: const AudioFocusState(status: AudioFocusStatus.normal),
      );

      // Restore previous mode
      if (previousMode == AudioMode.recording) {
        requestRecording();
      } else if (previousMode == AudioMode.playing) {
        requestPlayback();
      }
    } else {
      // Just clear the focus state if no restoration needed
      state = state.copyWith(
        audioFocusState: const AudioFocusState(status: AudioFocusStatus.normal),
      );
    }
  }

  /// Request to start recording - returns true if granted
  Future<bool> requestRecording() async {
    debugPrint(
      'AudioCoordinator: requestRecording() - current mode: ${state.mode}',
    );

    if (state.mode == AudioMode.playing) {
      debugPrint('AudioCoordinator: Must stop playback first');
      // Transition to idle, which will trigger TTS to stop
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      // Give TTS a moment to stop and reset audio session
      await _resetAudioSession();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (state.mode != AudioMode.idle) {
      debugPrint('AudioCoordinator: Cannot record, mode is ${state.mode}');
      return false;
    }

    // Transition to recording (synchronous)
    debugPrint('AudioCoordinator: Transitioning to recording mode');
    state = const AudioCoordinatorState(mode: AudioMode.recording);

    debugPrint('AudioCoordinator: Recording lock acquired');
    return true;
  }

  /// Request to start playback - returns true if granted
  Future<bool> requestPlayback() async {
    debugPrint(
      'AudioCoordinator: requestPlayback() - current mode: ${state.mode}',
    );

    if (state.mode == AudioMode.recording) {
      debugPrint('AudioCoordinator: Must stop recording first');
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      // Reset audio session to clear Bluetooth SCO state from recording
      await _resetAudioSession();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (state.mode != AudioMode.idle) {
      debugPrint('AudioCoordinator: Cannot play, mode is ${state.mode}');
      return false;
    }

    // Configure audio session for speech/communication mode before playback
    // This ensures Android routes audio to Bluetooth SCO instead of speaker
    await _configureSpeechMode();

    debugPrint('AudioCoordinator: Transitioning to playing mode');
    state = const AudioCoordinatorState(mode: AudioMode.playing);

    debugPrint('AudioCoordinator: Playback lock acquired');
    return true;
  }

  Future<void> releaseRecording() async {
    debugPrint('AudioCoordinator: releaseRecording() - mode: ${state.mode}');
    if (state.mode != AudioMode.recording) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    // Auto-resume if in listening/conversation mode
    final voiceMode = ref.read(settingsProvider).voiceMode;
    if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      debugPrint('AudioCoordinator: Auto-resuming continuous recording');
      await requestRecording();
    }
  }

  Future<void> releasePlayback() async {
    debugPrint('AudioCoordinator: releasePlayback() - mode: ${state.mode}');
    if (state.mode != AudioMode.playing) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    // Delay auto-resume to allow any queued TTS messages to request playback first
    // This prevents rapid mode switching that confuses audio routing
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Only auto-resume if still idle (no new playback started)
    if (state.mode == AudioMode.idle) {
      final voiceMode = ref.read(settingsProvider).voiceMode;
      if (voiceMode == VoiceMode.listening ||
          voiceMode == VoiceMode.conversation) {
        debugPrint('AudioCoordinator: Auto-resuming continuous recording');
        await requestRecording();
      }
    }
  }

  /// Configure audio session for speech/communication mode
  /// This ensures Android routes audio to Bluetooth SCO for TTS playback
  Future<void> _configureSpeechMode() async {
    try {
      debugPrint('AudioCoordinator: Configuring audio session for speech mode');
      final session = await AudioSession.instance;

      // Ensure session is active with speech configuration
      // This should set Android audio mode to IN_COMMUNICATION
      await session.setActive(true);
      debugPrint('AudioCoordinator: Audio session activated for speech');
    } catch (e) {
      debugPrint('AudioCoordinator: Failed to configure speech mode: $e');
      // Don't fail the operation if configuration fails - continue anyway
    }
  }

  /// Reset audio session to clear Bluetooth SCO routing state
  /// This ensures clean transitions between recording and playback modes
  Future<void> _resetAudioSession() async {
    try {
      debugPrint('AudioCoordinator: Resetting audio session for clean routing');
      final session = await AudioSession.instance;

      // Deactivate to release Bluetooth SCO connection from record package
      await session.setActive(false);
      debugPrint('AudioCoordinator: Audio session deactivated');

      // Small delay to allow Android audio system to reset routing
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Reactivate with speech configuration for next operation
      await session.setActive(true);
      debugPrint('AudioCoordinator: Audio session reactivated');
    } catch (e) {
      debugPrint('AudioCoordinator: Failed to reset audio session: $e');
      // Don't fail the operation if reset fails - continue anyway
    }
  }
}
