import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';

/// The ONLY valid audio states - enforces mutual exclusion at the type level
enum AudioMode {
  idle, // Nothing happening
  recording, // ASR active, TTS blocked
  playing, // TTS active, ASR blocked
}

class AudioCoordinatorState {
  final AudioMode mode;
  final String? error;

  const AudioCoordinatorState({required this.mode, this.error});

  factory AudioCoordinatorState.initial() {
    return const AudioCoordinatorState(mode: AudioMode.idle);
  }

  AudioCoordinatorState copyWith({AudioMode? mode, String? Function()? error}) {
    return AudioCoordinatorState(
      mode: mode ?? this.mode,
      error: error != null ? error() : this.error,
    );
  }

  bool get canRecord => mode == AudioMode.idle;
  bool get canPlay => mode == AudioMode.idle;
  bool get isRecording => mode == AudioMode.recording;
  bool get isPlaying => mode == AudioMode.playing;
  bool get isIdle => mode == AudioMode.idle;
}

final audioCoordinatorProvider =
    StateNotifierProvider<AudioCoordinator, AudioCoordinatorState>((ref) {
      return AudioCoordinator(ref);
    });

class AudioCoordinator extends StateNotifier<AudioCoordinatorState> {
  final Ref ref;

  AudioCoordinator(this.ref) : super(AudioCoordinatorState.initial());

  /// Request to start recording - returns true if granted
  Future<bool> requestRecording() async {
    debugPrint(
      'AudioCoordinator: requestRecording() - current mode: ${state.mode}',
    );

    if (state.mode == AudioMode.playing) {
      debugPrint('AudioCoordinator: Must stop playback first');
      // Transition to idle, which will trigger TTS to stop
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      // Give TTS a moment to stop
      await Future<void>.delayed(const Duration(milliseconds: 50));
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
      // Transition to idle, which will trigger Recording to stop
      state = const AudioCoordinatorState(mode: AudioMode.idle);
      // Give Recording a moment to stop
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    if (state.mode != AudioMode.idle) {
      debugPrint('AudioCoordinator: Cannot play, mode is ${state.mode}');
      return false;
    }

    // Transition to playing (synchronous)
    debugPrint('AudioCoordinator: Transitioning to playing mode');
    state = const AudioCoordinatorState(mode: AudioMode.playing);

    debugPrint('AudioCoordinator: Playback lock acquired');
    return true;
  }

  Future<void> releaseRecording() async {
    debugPrint('AudioCoordinator: releaseRecording() - mode: ${state.mode}');
    if (state.mode != AudioMode.recording) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    // Check if we should auto-resume based on voice mode
    final voiceMode = ref.read(settingsProvider).voiceMode;
    if (voiceMode == VoiceMode.listening ||
        voiceMode == VoiceMode.conversation) {
      debugPrint('AudioCoordinator: Auto-resuming continuous recording');
      // Auto-resume continuous recording
      await requestRecording();
    }
  }

  Future<void> releasePlayback({bool autoResume = true}) async {
    debugPrint('AudioCoordinator: releasePlayback(autoResume: $autoResume) - mode: ${state.mode}');
    if (state.mode != AudioMode.playing) return;

    state = const AudioCoordinatorState(mode: AudioMode.idle);

    // Check if we should auto-resume recording
    if (autoResume) {
      final voiceMode = ref.read(settingsProvider).voiceMode;
      if (voiceMode == VoiceMode.listening ||
          voiceMode == VoiceMode.conversation) {
        debugPrint('AudioCoordinator: Auto-resuming continuous recording');
        // Auto-resume continuous recording
        await requestRecording();
      }
    }
  }
}
