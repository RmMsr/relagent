import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/utils/logger.dart';
import '/voice/voice_service.dart';
import 'settings_provider.dart';
import 'voice_service_provider.dart';

const _micPreferenceKey = 'mic_preference';

/// Persisted microphone preference (automatic or a pinned device), pushed to
/// the voice service so it applies to subsequent recordings.
final micPreferenceProvider =
    NotifierProvider<MicPreferenceNotifier, MicPreference>(
      MicPreferenceNotifier.new,
    );

class MicPreferenceNotifier extends Notifier<MicPreference> {
  @override
  MicPreference build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    var preference = const MicPreference.auto();
    final raw = prefs.getString(_micPreferenceKey);
    if (raw != null) {
      try {
        preference = MicPreference.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (e) {
        Logger.warning('Invalid stored mic preference, using auto: $e');
      }
    }
    ref.read(voiceServiceProvider).setInputDevicePreference(preference);
    return preference;
  }

  Future<void> set(MicPreference preference) async {
    state = preference;
    ref.read(voiceServiceProvider).setInputDevicePreference(preference);
    final prefs = ref.read(sharedPreferencesProvider);
    if (preference.isAuto) {
      await prefs.remove(_micPreferenceKey);
    } else {
      await prefs.setString(_micPreferenceKey, jsonEncode(preference.toJson()));
    }
  }
}

/// Available input devices, refreshed on device connect/disconnect.
final micDevicesProvider = FutureProvider<List<MicDevice>>((ref) {
  final service = ref.watch(voiceServiceProvider);
  final sub = service.deviceChangedEvents.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return service.listInputDevices();
});

/// The input device the current preference resolves to (null = built-in),
/// used for the recording button symbol. Refreshed on preference and device
/// changes.
final micSelectionProvider = FutureProvider<MicSelectionResult>((ref) {
  ref.watch(micPreferenceProvider);
  final service = ref.watch(voiceServiceProvider);
  final sub = service.deviceChangedEvents.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return service.queryInputSelection();
});
