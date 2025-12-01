import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/config/app_config.dart';
import '/providers/settings_provider.dart';
import '/router/app_router.dart';
import '/tts/sherpa_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  // Load static app config (ASR model, etc.)
  await AppConfig.load();

  // Pre-cache TTS model files in background (don't block app startup)
  // This ensures TTS is ready when needed without delaying UI initialization
  unawaited(preCacheTtsModelFiles());

  // Initialize SharedPreferences for user settings
  final sharedPreferences = await SharedPreferences.getInstance();

  // Log SharedPreferences keys for debugging
  debugPrint('SharedPreferences initialized');
  debugPrint('Existing keys: ${sharedPreferences.getKeys()}');

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Relagent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlueAccent),
      ),
      routerConfig: appRouter,
      // Performance overlay - shows FPS and frame rendering time
      showPerformanceOverlay: false,
    );
  }
}
