import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import '/models/app_info.dart';
import '/widgets/voice_init_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/model_catalog.dart';
import '/providers/background_service_provider.dart';
import '/providers/health_check_provider.dart';
import '/providers/settings_provider.dart';
import '/router/app_router.dart';
import '/utils/logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Linux/Windows audio backend for just_audio (no-op on other platforms)
  if (!kIsWeb) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Load voice model catalog from bundled JSON asset
  await ModelCatalog.init();

  // Get runtime app info
  await AppInfo.initialize();

  // Initialize SharedPreferences for user settings
  final sharedPreferences = await SharedPreferences.getInstance();

  Logger.debug('SharedPreferences initialized');
  Logger.debug('Existing keys: ${sharedPreferences.getKeys()}');

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

    // Trigger automatic health check on app startup with retry logic
    // This validates API connectivity with exponential backoff to allow
    // system recovery (network initialization, server startup, etc.)
    ref.read(healthCheckProvider.notifier).triggerStartupHealthCheck();

    return MaterialApp.router(
      title: AppInfo.data.toString(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.lightBlueAccent),
      ),
      routerConfig: appRouter,
      builder: (context, child) => VoiceInitOverlay(child: child!),
    );
  }
}
