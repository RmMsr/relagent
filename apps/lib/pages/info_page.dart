import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '/models/app_info.dart';
import '/models/self_test_result.dart';
import '/models/settings.dart';
import '/providers/engine_health_check_provider.dart';
import '/providers/self_test_provider.dart';
import '/providers/settings_provider.dart';

class InfoPage extends ConsumerWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final appInfo = AppInfo.data;
    final settings = ref.watch(settingsProvider);
    final engineHealthState = ref.watch(engineHealthCheckProvider);

    final selfTestState = ref.watch(selfTestProvider);

    final isEngine = settings.selectedBackend == ChatBackendType.relagentEngine;
    final backendLabel = isEngine ? 'Relagent Engine' : 'OpenAI-compatible';
    final activeBaseUrl = isEngine
        ? settings.engineBaseUrl
        : settings.simpleChatBaseUrl;
    final backendVersion =
        isEngine && engineHealthState.lastResult?.isSuccess == true
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
                    'assets/icon/app-icon.png',
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
          _buildSectionHeader(context, 'Self-Test'),
          const SizedBox(height: 12),
          _buildSelfTestSection(context, ref, selfTestState),
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

  void _copyResults(BuildContext context, List<SelfTestResult> results) {
    final lines = StringBuffer('Relagent Self-Test\n');
    for (final r in results) {
      final label = switch (r.status) {
        SelfTestStatus.ok => 'OK  ',
        SelfTestStatus.warning => 'WARN',
        SelfTestStatus.error => 'FAIL',
        SelfTestStatus.running => 'RUN ',
        SelfTestStatus.pending => '... ',
      };
      final detail = r.detail != null ? ' (${r.detail})' : '';
      lines.writeln('$label  ${r.label}$detail');
    }
    Clipboard.setData(ClipboardData(text: lines.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Results copied to clipboard')),
    );
  }

  Widget _buildSelfTestSection(
    BuildContext context,
    WidgetRef ref,
    SelfTestState selfTestState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selfTestState.results.isNotEmpty)
          Card(
            child: Column(
              children: selfTestState.results
                  .map((r) => _buildTestResultTile(context, r))
                  .toList(),
            ),
          ),
        if (selfTestState.results.isNotEmpty) const SizedBox(height: 12),
        Row(
          children: [
            if (selfTestState.results.isNotEmpty &&
                !selfTestState.isRunning) ...[
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(selfTestProvider.notifier).clearResults(),
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Clear'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _copyResults(context, selfTestState.results),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.tonal(
                onPressed: selfTestState.isRunning
                    ? null
                    : () => ref.read(selfTestProvider.notifier).runSelfTests(),
                child: Text(
                  selfTestState.isRunning ? 'Checking…' : 'Check engine setup',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestResultTile(BuildContext context, SelfTestResult result) {
    final theme = Theme.of(context);
    final (icon, color) = switch (result.status) {
      SelfTestStatus.pending => (
        Icons.radio_button_unchecked,
        theme.colorScheme.onSurfaceVariant,
      ),
      SelfTestStatus.running => (Icons.sync, theme.colorScheme.primary),
      SelfTestStatus.ok => (Icons.check_circle, Colors.green),
      SelfTestStatus.warning => (Icons.warning_amber, Colors.orange),
      SelfTestStatus.error => (Icons.cancel, theme.colorScheme.error),
    };

    return ListTile(
      dense: true,
      leading: result.status == SelfTestStatus.running
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          : Icon(icon, color: color, size: 20),
      title: Text(result.label),
      subtitle: result.detail != null ? Text(result.detail!) : null,
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
