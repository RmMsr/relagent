import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '/utils/logger.dart';
import '/voice/voice_service.dart';

/// Dart facade over the native MicRouter (Android's single owner of audio
/// routing state). Every call is failure-contained: channel errors degrade to
/// default-device behavior with a log line and never block recording.
class MicRouter {
  static const _channel = MethodChannel('com.relagent.mic_router');
  static const _eventChannel = EventChannel('com.relagent.mic_router_events');

  final bool _supported;

  /// [supportedOverride] forces platform support in tests, where the host is
  /// never Android.
  MicRouter({bool? supportedOverride})
    : _supported = supportedOverride ?? Platform.isAndroid;

  bool get isSupported => _supported;

  Future<List<MicDevice>> listInputs() async {
    if (!isSupported) return const [];
    try {
      final list = await _channel.invokeListMethod<dynamic>('listInputs');
      return (list ?? const [])
          .whereType<Map<dynamic, dynamic>>()
          .map(MicDevice.fromMap)
          .toList();
    } catch (e) {
      Logger.debug('MicRouter: listInputs failed: $e');
      return const [];
    }
  }

  /// Establish the route for [preference] and wait until it is active
  /// (bounded natively by a 3s timeout). Safe to call before every recording.
  Future<MicSelectionResult> ensureReady(MicPreference preference) =>
      _selectionCall('ensureReady', preference);

  /// Resolve what [preference] would select without touching routing state.
  Future<MicSelectionResult> querySelection(MicPreference preference) =>
      _selectionCall('querySelection', preference);

  Future<MicSelectionResult> _selectionCall(
    String method,
    MicPreference preference,
  ) async {
    if (!isSupported) {
      return const MicSelectionResult(MicSelectionStatus.unsupported, null);
    }
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        method,
        preference.toChannelMap(),
      );
      final status =
          MicSelectionStatus.values.asNameMap()[map?['status']] ??
          MicSelectionStatus.error;
      final deviceMap = map?['device'] as Map<dynamic, dynamic>?;
      final device = deviceMap == null ? null : MicDevice.fromMap(deviceMap);
      Logger.debug(
        'MicRouter: $method -> ${status.name} (${device ?? 'default mic'})',
      );
      return MicSelectionResult(status, device);
    } catch (e) {
      Logger.debug('MicRouter: $method failed, using default mic: $e');
      return const MicSelectionResult(MicSelectionStatus.error, null);
    }
  }

  /// Schedule route release after the native idle period (5s); a new
  /// [ensureReady] within that window cancels it and reuses the route.
  Future<void> releaseAfterIdle() => _fireAndForget('releaseAfterIdle');

  /// Release the route immediately (e.g. when switching to playback).
  Future<void> releaseNow() => _fireAndForget('releaseNow');

  Future<void> _fireAndForget(String method) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (e) {
      Logger.debug('MicRouter: $method failed: $e');
    }
  }

  /// Fires when input devices connect or disconnect. Errors are swallowed
  /// into log lines so a native failure cannot break UI listeners.
  Stream<void> get deviceChanges {
    if (!isSupported) return const Stream.empty();
    return _eventChannel.receiveBroadcastStream().handleError((Object e) {
      Logger.debug('MicRouter: event stream error: $e');
    });
  }
}
