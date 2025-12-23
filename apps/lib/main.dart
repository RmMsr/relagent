import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:relagent/models/app_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/config/app_config.dart';
import '/providers/background_service_provider.dart';
import '/providers/settings_provider.dart';
import '/router/app_router.dart';
import '/tts/sherpa_tts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  // Load static app config (ASR model, etc.)
  await AppConfig.load();

  // Get runtime app info
  await AppInfo.initialize();

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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize background service provider to start listening to AudioCoordinator
    // This ensures the service syncs with audio state changes
    ref.read<BackgroundServiceState>(backgroundServiceProvider);

    return MaterialApp.router(
      title: AppInfo.data.toString(),
      debugShowCheckedModeBanner: AppInfo.data.isDebug,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlueAccent),
      ),
      routerConfig: appRouter,
    );
  }
}
