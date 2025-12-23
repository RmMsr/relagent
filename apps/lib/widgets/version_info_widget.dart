import 'package:flutter/material.dart';

import '../models/app_info.dart';

class VersionInfoWidget extends StatelessWidget {
  const VersionInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          AppInfo.data.versionInfo,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (AppInfo.data.isDebug) ...[
          const SizedBox(height: 8),
          Chip(
            label: const Text('Debug Build'),
            avatar: const Icon(Icons.bug_report, size: 16),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        ],
      ],
    );
  }
}
