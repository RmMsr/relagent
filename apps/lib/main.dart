import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/config/app_config.dart';
import '/providers/settings_provider.dart';
import '/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.ensureInitialized();

  // Load static app config (ASR model, etc.)
  await AppConfig.load();

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
    );
  }
}
