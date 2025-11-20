import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/pages/chat_page.dart';
import '/pages/settings_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'simple chat',
      pageBuilder: (context, state) => const MaterialPage(child: ChatPage()),
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      pageBuilder: (context, state) =>
          const MaterialPage(child: SettingsPage()),
    ),
  ],
);
