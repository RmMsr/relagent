import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/providers/agentic_chat_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/sessions_provider.dart';

class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key});

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sessionsProvider.notifier).loadSessions();
    });
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  Future<void> _switchToSession(String sessionId) async {
    final settingsNotifier = ref.read(settingsProvider.notifier);

    await settingsNotifier.setAgenticSessionId(sessionId);

    // Reload chat for the new session
    await ref.read(agenticChatProvider.notifier).loadHistory();
    await ref.read(agenticChatProvider.notifier).loadSessionInfo();

    if (mounted) {
      context.go('/chat');
    }
  }

  Future<void> _showDeleteConfirmation(String sessionId, String? title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text(
          'Are you sure you want to delete "${title ?? 'this session'}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref
          .read(sessionsProvider.notifier)
          .deleteSession(sessionId);

      if (success) {
        // Check if the deleted session was the active session
        final settings = ref.read(settingsProvider);
        if (settings.agenticSessionId == sessionId) {
          // Clear the active session from settings
          await ref.read(settingsProvider.notifier).clearAgenticSessionId();

          // Clear the chat state to start a new empty session
          ref.read(agenticChatProvider.notifier).clearChat();

          if (mounted) {
            // Show a snackbar to inform the user
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Active session deleted. Started new session.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsState = ref.watch(sessionsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent Sessions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/chat'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionsProvider.notifier).loadSessions(),
        child: _buildBody(context, sessionsState, theme),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SessionsState state,
    ThemeData theme,
  ) {
    if (state.isLoading && state.sessions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text('Failed to load sessions', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              state.error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(sessionsProvider.notifier).loadSessions(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('No sessions yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Start a new conversation to create your first session',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/chat'),
              icon: const Icon(Icons.add),
              label: const Text('Start New Session'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: state.sessions.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, index) {
        final item = state.sessions[index];
        final session = item.sessionInfo;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: item.isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface,
          child: InkWell(
            onTap: () => _switchToSession(session.sessionId),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.title ?? 'New Session',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatRelativeTime(session.updatedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isActive)
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _showDeleteConfirmation(
                      session.sessionId,
                      session.title,
                    ),
                    tooltip: 'Delete session',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
