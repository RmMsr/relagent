import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/models/app_info.dart';
import '/models/model_catalog.dart';
import '/voice/imported_model_registry.dart';
import '/providers/background_service_provider.dart';
import '/providers/health_check_provider.dart';
import '/providers/invocation_listener_provider.dart';
import '/providers/invocation_provider.dart';
import '/providers/settings_provider.dart';
import '/router/app_router.dart';
import '/theme/app_colors.dart';
import '/utils/logger.dart';
import '/widgets/voice_init_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Linux/Windows audio backend for just_audio (no-op on other platforms)
  if (!kIsWeb) {
    JustAudioMediaKit.ensureInitialized();
  }

  // Load voice model catalog from bundled JSON asset
  await ModelCatalog.init();
  await ImportedModelRegistry.init();

  // Get runtime app info
  await AppInfo.initialize();

  // Initialize SharedPreferences for user settings
  final sharedPreferences = await SharedPreferences.getInstance();

  Logger.debug('SharedPreferences initialized');
  Logger.debug('Existing keys: ${sharedPreferences.getKeys()}');

  final initialSharedText = await getInitialSharedText();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        if (initialSharedText != null)
          invocationProvider.overrideWith(
            () => InvocationNotifier(initialSharedText),
          ),
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

    // Activate warm-intent and PROCESS_TEXT listeners for incoming shared text
    ref.read(invocationListenerProvider);

    // Navigate to /invoke whenever a warm intent sets the holder
    ref.listen(invocationProvider, (_, next) {
      if (next != null) {
        appRouter.go('/invoke?t=${DateTime.now().millisecondsSinceEpoch}');
      }
    });

    return MaterialApp.router(
      title: AppInfo.data.toString(),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) => VoiceInitOverlay(child: child!),
    );
  }
}
