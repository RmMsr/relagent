import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/settings_provider.dart';
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
  static const _platform = MethodChannel('com.relagent.background_service');
  static const _notificationActions = MethodChannel(
    'com.relagent.notification_actions',
  );

  @override
  BackgroundServiceState build() {
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
      // Update service mode when audio mode changes
      if (previous?.mode != next.mode) {
        _syncServiceWithAudioMode(next.mode);

        // Also update notification when mode changes during waiting state
        // This catches interruptions that don't fire audio session events
        if (next.audioFocusState.status == AudioFocusStatus.temporaryLoss) {
          Logger.debug(
            'BackgroundServiceProvider: Mode changed during temporary loss, updating notification',
          );
          _updateNotificationForAudioFocus(next);
        }
      }

      // Update notification when audio focus state or waiting state changes
      if (previous?.audioFocusState.status != next.audioFocusState.status ||
          previous?.isWaiting != next.isWaiting) {
        _updateNotificationForAudioFocus(next);
      }
    });

    // Listen to settings changes
    ref.listen<Settings>(settingsProvider, (previous, next) {
      // Stop service when going silent
      if (previous?.voiceMode != next.voiceMode &&
          next.voiceMode == VoiceMode.silent) {
        _stopService();
      }

      // Restart service with new duration if it changed while recording
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

    // Initialize audio_session and listen to interruptions
    _initAudioSession();

    // Setup notification action handlers
    _setupNotificationActionHandlers();

    Logger.debug('BackgroundServiceProvider: Initialized');
  }

  /// Handles notification button action from the native service.
  ///
  /// When user taps "Stop" button, we change voice mode to silent.
  /// This triggers the reactive chain: Settings change → RecordingProvider
  /// and PlaybackService react → all background activity stops.
  void _setupNotificationActionHandlers() {
    _notificationActions.setMethodCallHandler((call) async {
      if (call.method == 'stop') {
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
      final session = await AudioSession.instance;
      // Configure for speech mode - enables bidirectional Bluetooth SCO for both recording and playback
      await session.configure(const AudioSessionConfiguration.speech());

      // Listen to audio interruptions (phone calls, etc.)
      session.interruptionEventStream.listen((event) {
        Logger.debug(
          'BackgroundServiceProvider: Audio interruption: type=${event.type}, begin=${event.begin}',
        );

        // Only handle "pause" type interruptions (phone calls, alarms)
        // Ignore "duck" (volume reductions) and "unknown" (internal transitions)
        // "unknown" events occur during normal app audio transitions (TTS→recording)
        // and are not real external interruptions
        if (event.type != AudioInterruptionType.pause) {
          Logger.debug(
            'BackgroundServiceProvider: Ignoring non-pause interruption: ${event.type}',
          );
          return;
        }

        if (event.begin) {
          // Interruption started (phone call, alarm, etc.)
          // Only handle if we're actively using audio (not idle)
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
          // Interruption ended - always handle to restore from waiting state
          Logger.debug('BackgroundServiceProvider: Interruption ended');
          ref
              .read(audioCoordinatorProvider.notifier)
              .handleAudioFocusChange('gain');
        }
      });

      // Listen to device changes (Bluetooth connect/disconnect)
      session.devicesChangedEventStream.listen((event) {
        Logger.debug('BackgroundServiceProvider: Audio devices changed');
        Logger.debug('  Devices added: ${event.devicesAdded}');
        Logger.debug('  Devices removed: ${event.devicesRemoved}');
        _logCurrentAudioRouting(session);
      });

      // Log initial audio routing
      _logCurrentAudioRouting(session);

      Logger.debug('BackgroundServiceProvider: Audio session initialized');
    } catch (e) {
      Logger.debug(
        'BackgroundServiceProvider: Failed to initialize audio session: $e',
      );
    }
  }

  /// Log current audio routing information
  void _logCurrentAudioRouting(AudioSession session) {
    Logger.debug('=== Current Audio Routes ===');
    session.devicesStream.listen((devices) {
      final inputDevices = devices.where((d) => d.isInput).toList();
      final outputDevices = devices.where((d) => d.isOutput).toList();

      Logger.debug('Input devices (${inputDevices.length}):');
      for (final device in inputDevices) {
        Logger.debug('  - ${device.name} (${device.type.name})');
      }

      Logger.debug('Output devices (${outputDevices.length}):');
      for (final device in outputDevices) {
        Logger.debug('  - ${device.name} (${device.type.name})');
      }
      Logger.debug('========================');
    });
  }

  /// Update notification message based on audio focus state
  Future<void> _updateNotificationForAudioFocus(
    AudioCoordinatorState state,
  ) async {
    Logger.debug(
      'BackgroundServiceProvider: Updating notification for audio focus: ${state.audioFocusState.status}, isWaiting: ${state.isWaiting}, mode: ${state.mode}',
    );

    // Don't update notification if we're truly idle (not waiting)
    if (state.mode == AudioMode.idle && !state.isWaiting) {
      Logger.debug(
        'BackgroundServiceProvider: Skipping notification update for idle state',
      );
      return;
    }

    // Determine notification message based on state
    final String message;
    if (state.isWaiting) {
      message = 'Paused (waiting to resume)';
    } else {
      // Restore normal message based on mode
      switch (state.mode) {
        case AudioMode.recording:
          message = 'Listening...';
        case AudioMode.playing:
          message = 'Speaking...';
        case AudioMode.idle:
          // This shouldn't happen due to check above, but handle gracefully
          return;
      }
    }

    try {
      await _platform.invokeMethod('updateNotification', {'message': message});
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

    // Android 14+ (API 34+) requires the activity to be fully visible before
    // starting a foreground service with microphone type. Add a small delay
    // to ensure the activity is visible.
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
      final arguments = <String, dynamic>{'mode': mode};
      if (mode == 'recording') {
        arguments['durationMinutes'] = durationMinutes;
        Logger.debug(
          'BackgroundServiceProvider: Starting service with duration: ${durationMinutes}min',
        );
      }
      await _platform.invokeMethod('startService', arguments);
      state = state.copyWith(isActive: true, error: () => null);
      Logger.debug(
        'BackgroundServiceProvider: Service started with mode: $mode',
      );
    } on PlatformException catch (e) {
      // Android 12+ restriction: Cannot start foreground service from background
      // This is expected when app is backgrounded - service will resume when app returns to foreground
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
        // Don't rethrow - this is expected behavior when backgrounded
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
      await _platform.invokeMethod('stopService');
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
