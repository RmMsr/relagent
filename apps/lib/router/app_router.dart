import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/pages/chat_router_page.dart';
import '/pages/info_page.dart';
import '/pages/invocation_page.dart';
import '/models/model_catalog.dart';
import '/widgets/model_management_section.dart';
import '/pages/sessions_page.dart';
import '/pages/settings_page.dart';
import '/pages/splash_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'splash',
      pageBuilder: (context, state) => const MaterialPage(child: SplashPage()),
    ),
    GoRoute(
      path: '/chat',
      name: 'chat',
      pageBuilder: (context, state) =>
          const MaterialPage(child: ChatRouterPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) =>
          const MaterialPage(child: SettingsPage()),
    ),
    GoRoute(
      path: '/info',
      name: 'info',
      pageBuilder: (context, state) => const MaterialPage(child: InfoPage()),
    ),
    GoRoute(
      path: '/voice-models',
      name: 'voiceModels',
      pageBuilder: (context, state) {
        final tab = state.extra as int? ?? 0;
        return MaterialPage(
          child: ModelCatalogBrowser(
            initialType: tab == 0 ? ModelType.asr : ModelType.tts,
          ),
        );
      },
    ),
    GoRoute(
      path: '/sessions',
      name: 'sessions',
      pageBuilder: (context, state) =>
          const MaterialPage(child: SessionsPage()),
    ),
    GoRoute(
      path: '/invoke',
      name: 'invoke',
      pageBuilder: (context, state) => MaterialPage(
        key: ValueKey(state.uri.queryParameters['t']),
        child: const InvocationPage(),
      ),
    ),
  ],
);
