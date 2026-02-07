import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/pages/agentic_chat_page.dart';
import '/pages/chat_page.dart';
import '/pages/info_page.dart';
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
      path: '/agentic',
      name: 'agentic chat',
      pageBuilder: (context, state) =>
          const MaterialPage(child: AgenticChatPage()),
    ),
    GoRoute(
      path: '/simple',
      name: 'simple chat',
      pageBuilder: (context, state) => const MaterialPage(child: ChatPage()),
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
  ],
);
