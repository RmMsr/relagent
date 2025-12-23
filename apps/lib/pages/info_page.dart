import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '/models/app_info.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appInfo = AppInfo.data;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Info'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildInfoCard(
            context,
            icon: Icons.info_outline,
            title: 'App Name',
            value: appInfo.name,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            context,
            icon: Icons.tag,
            title: 'Version',
            value: appInfo.versionInfo,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(
            context,
            icon: appInfo.isDebug ? Icons.bug_report : Icons.rocket_launch,
            title: 'Build Type',
            value: appInfo.isDebug ? 'Debug' : 'Release',
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.description, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Text(
                        'Full Info',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(appInfo.toString(), style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
