import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/voice/voice_service.dart';
import '../utils/logger.dart';

/// State for the background service
class BackgroundServiceState {
  final bool isActive;
  final String? error;

  const BackgroundServiceState({required this.isActive, this.error});

  factory BackgroundServiceState.initial() {
    return const BackgroundServiceState(isActive: false);
  }

  BackgroundServiceState copyWith({bool? isActive, String? Function()? error}) {
    return BackgroundServiceState(
      isActive: isActive ?? this.isActive,
      error: error != null ? error() : this.error,
    );
  }
}

/// Provider for managing the native background service
final backgroundServiceProvider =
    NotifierProvider<BackgroundServiceNotifier, BackgroundServiceState>(
      () => BackgroundServiceNotifier(),
    );

/// Manages the native Android foreground service for background audio operations.
///
/// This is a thin wrapper that mirrors AudioCoordinator state to the native service.
/// The service never makes state decisions - it only reflects AudioCoordinator state.
class BackgroundServiceNotifier extends Notifier<BackgroundServiceState> {
  VoiceService get _voiceService => ref.read(voiceServiceProvider);

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  @override
  BackgroundServiceState build() {
    ref.onDispose(() {
      _interruptionSub?.cancel();
    });
    _init();
    return BackgroundServiceState.initial();
  }

  void _init() {
    // Sync initial state
    final initialAudioState = ref.read(audioCoordinatorProvider);
    if (initialAudioState.mode != AudioMode.idle) {
      Logger.debug(
        'BackgroundServiceProvider: Syncing initial state: ${initialAudioState.mode}',
      );
      _syncServiceWithAudioMode(initialAudioState.mode);
    }

    // Listen to AudioCoordinator state changes and sync service
    ref.listen<AudioCoordinatorState>(audioCoordinatorProvider, (
      previous,
      next,
    ) {
      if (previous?.mode != next.mode) {
        _syncServiceWithAudioMode(next.mode);

        if (next.audioFocusState.status == AudioFocusStatus.temporaryLoss) {
          Logger.debug(
            'BackgroundServiceProvider: Mode changed during temporary loss, updating notification',
          );
          _updateNotificationForAudioFocus(next);
        }
      }

      if (previous?.audioFocusState.status != next.audioFocusState.status ||
          previous?.isWaiting != next.isWaiting) {
        _updateNotificationForAudioFocus(next);
      }
    });

    // Listen to settings changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      if (previous?.voiceMode != next.voiceMode &&
          next.voiceMode == VoiceMode.silent) {
        _stopService();
      }

      if (previous?.backgroundListeningDuration !=
          next.backgroundListeningDuration) {
        final currentMode = ref.read(audioCoordinatorProvider).mode;
        if (currentMode == AudioMode.recording) {
          Logger.debug(
            'BackgroundServiceProvider: Background listening duration changed, restarting service',
          );
          _syncServiceWithAudioMode(AudioMode.recording);
        }
      }
    });

    // Initialize audio session and listen to interruptions via VoiceService
    _initAudioSession();

    // Setup notification action handlers via VoiceService
    _setupNotificationActionHandlers();

    Logger.debug('BackgroundServiceProvider: Initialized');
  }

  void _setupNotificationActionHandlers() {
    _voiceService.setupNotificationActionHandler((method) async {
      if (method == 'stop') {
        Logger.debug(
          'BackgroundServiceProvider: User requested silence via notification',
        );
        await ref
            .read(settingsProvider.notifier)
            .updateVoiceMode(VoiceMode.silent);
      }
    });
  }

  Future<void> _initAudioSession() async {
    try {
      await _voiceService.configureAudioSession();

      // Listen to audio interruptions via VoiceService
      _interruptionSub = _voiceService.interruptionEvents.listen((event) {
        Logger.debug(
          'BackgroundServiceProvider: Audio interruption: type=${event.type}, begin=${event.begin}',
        );

        if (event.type != AudioInterruptionType.pause) {
          Logger.debug(
            'BackgroundServiceProvider: Ignoring non-pause interruption: ${event.type}',
          );
          return;
        }

        if (event.begin) {
          final currentMode = ref.read(audioCoordinatorProvider).mode;
          if (currentMode == AudioMode.idle) {
            Logger.debug(
              'BackgroundServiceProvider: Ignoring interruption start while idle',
            );
            return;
          }

          Logger.debug('BackgroundServiceProvider: Real interruption began');
          ref
              .read(audioCoordinatorProvider.notifier)
              .handleAudioFocusChange('temporary_loss');
        } else {
          Logger.debug('BackgroundServiceProvider: Interruption ended');
          ref
              .read(audioCoordinatorProvider.notifier)
              .handleAudioFocusChange('gain');
        }
      });

      Logger.debug('BackgroundServiceProvider: Audio session initialized');
    } catch (e) {
      Logger.debug(
        'BackgroundServiceProvider: Failed to initialize audio session: $e',
      );
    }
  }

  /// Update notification message based on audio focus state
  Future<void> _updateNotificationForAudioFocus(
    AudioCoordinatorState state,
  ) async {
    Logger.debug(
      'BackgroundServiceProvider: Updating notification for audio focus: ${state.audioFocusState.status}, isWaiting: ${state.isWaiting}, mode: ${state.mode}',
    );

    if (state.mode == AudioMode.idle && !state.isWaiting) {
      Logger.debug(
        'BackgroundServiceProvider: Skipping notification update for idle state',
      );
      return;
    }

    final String message;
    if (state.isWaiting) {
      message = 'Paused (waiting to resume)';
    } else {
      switch (state.mode) {
        case AudioMode.recording:
          message = 'Listening...';
        case AudioMode.playing:
          message = 'Speaking...';
        case AudioMode.idle:
          return;
      }
    }

    try {
      await _voiceService.updateNotification(message);
      Logger.debug('BackgroundServiceProvider: Notification updated: $message');
    } on PlatformException catch (e) {
      Logger.debug(
        'BackgroundServiceProvider: Failed to update notification: ${e.message}',
      );
    }
  }

  /// Sync the native service with the current AudioMode
  Future<void> _syncServiceWithAudioMode(AudioMode mode) async {
    Logger.debug('BackgroundServiceProvider: Syncing service with mode: $mode');

    if (!state.isActive) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    try {
      switch (mode) {
        case AudioMode.idle:
          await _startService('idle');
        case AudioMode.recording:
          final settings = ref.read(settingsProvider);
          final durationMinutes =
              settings.backgroundListeningDuration.duration.inMinutes;
          await _startService('recording', durationMinutes: durationMinutes);
        case AudioMode.playing:
          await _startService('playing');
      }
    } catch (e) {
      Logger.debug('BackgroundServiceProvider: Error syncing service: $e');
      state = state.copyWith(error: () => e.toString());
    }
  }

  Future<void> _startService(String mode, {int durationMinutes = -1}) async {
    try {
      if (mode == 'recording') {
        Logger.debug(
          'BackgroundServiceProvider: Starting service with duration: ${durationMinutes}min',
        );
      }
      await _voiceService.startBackgroundService(
        mode,
        durationMinutes: durationMinutes,
      );
      state = state.copyWith(isActive: true, error: () => null);
      Logger.debug(
        'BackgroundServiceProvider: Service started with mode: $mode',
      );
    } on PlatformException catch (e) {
      final isForegroundRestriction =
          e.message?.contains('startForegroundService() not allowed') ?? false;
      final isForegroundException =
          e.message?.contains('ForegroundServiceStartNotAllowedException') ??
          false;

      if (isForegroundRestriction || isForegroundException) {
        Logger.debug(
          'BackgroundServiceProvider: Cannot start service from background (Android 12+ restriction)',
        );
        Logger.debug(
          'BackgroundServiceProvider: Service will start when app returns to foreground',
        );
        state = state.copyWith(isActive: false, error: () => null);
      } else {
        Logger.debug(
          'BackgroundServiceProvider: Failed to start service: ${e.message}',
        );
        state = state.copyWith(error: () => e.message);
        rethrow;
      }
    }
  }

  Future<void> _stopService() async {
    try {
      await _voiceService.stopBackgroundService();
      state = state.copyWith(isActive: false, error: () => null);
      Logger.debug('BackgroundServiceProvider: Service stopped');
    } on PlatformException catch (e) {
      Logger.debug(
        'BackgroundServiceProvider: Failed to stop service: ${e.message}',
      );
      state = state.copyWith(error: () => e.message);
      rethrow;
    }
  }
}
