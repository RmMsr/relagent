import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/pages/chat_router_page.dart';
import '/pages/info_page.dart';
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
      path: '/sessions',
      name: 'sessions',
      pageBuilder: (context, state) =>
          const MaterialPage(child: SessionsPage()),
    ),
  ],
);
