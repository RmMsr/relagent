import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/voice/voice_service.dart';

/// Singleton provider for the platform voice service.
final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = createVoiceService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Exposes voice capabilities for UI guards.
final voiceCapabilitiesProvider = Provider<VoiceCapabilities>((ref) {
  return ref.watch(voiceServiceProvider);
});
