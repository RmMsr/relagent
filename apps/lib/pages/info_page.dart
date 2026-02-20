import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '/models/app_info.dart';
import '/models/settings.dart';
import '/providers/engine_health_check_provider.dart';
import '/providers/settings_provider.dart';

class InfoPage extends ConsumerWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appInfo = AppInfo.data;
    final settings = ref.watch(settingsProvider);
    final engineHealthState = ref.watch(engineHealthCheckProvider);

    final isEngine = settings.selectedBackend == ChatBackendType.relagentEngine;
    final backendLabel = isEngine ? 'Relagent Engine' : 'OpenAI-compatible';
    final activeBaseUrl = isEngine
        ? settings.engineBaseUrl
        : settings.simpleChatBaseUrl;
    final backendVersion = isEngine &&
            engineHealthState.lastResult?.isSuccess == true
        ? engineHealthState.lastResult!.engineVersion
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 80,
                    height: 80,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  appInfo.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  appInfo.versionInfo,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (appInfo.isDebug) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Debug Build',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildSectionHeader(context, 'Chat Backend'),
          const SizedBox(height: 12),
          _buildBackendInfo(
            context,
            backendLabel: backendLabel,
            baseUrl: activeBaseUrl.isEmpty ? '(same origin)' : activeBaseUrl,
            version: backendVersion,
          ),
          const SizedBox(height: 32),
          _buildSectionHeader(context, 'About'),
          const SizedBox(height: 12),
          Text(
            'Relagent is a privacy-focused AI assistant. All processing happens locally or on servers you control.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _buildLinkTile(
            context,
            icon: Icons.code,
            title: 'Source Code',
            subtitle: 'https://gitlab.com/RmMsr/relagent',
            url: Uri.parse('https://gitlab.com/RmMsr/relagent'),
          ),
          const SizedBox(height: 8),
          _buildLinkTile(
            context,
            icon: Icons.article_outlined,
            title: 'Blog',
            subtitle: 'venkado.org',
            url: Uri.parse('https://venkado.org'),
          ),
          const SizedBox(height: 8),
          _buildLinkTile(
            context,
            icon: Icons.email_outlined,
            title: 'Contact',
            subtitle: 'hello@venkado.org',
            url: Uri.parse('mailto:hello@venkado.org'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildBackendInfo(
    BuildContext context, {
    required String backendLabel,
    required String baseUrl,
    String? version,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    backendLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (version != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      version,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              baseUrl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Uri url,
  }) {
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          Icons.open_in_new,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        onTap: () => launchUrl(url),
      ),
    );
  }
}
