import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/chat/widgets.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/chat_provider.dart';
import '/providers/health_check_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/tts_provider.dart';
import '/services/api_health_check.dart';
import '/widgets/voice_mode_selector.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _healthCheckBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // Trigger auto-recording check once the page is ready
    // This ensures we don't start recording during app initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(recordingProvider.notifier).checkAutoStart();
      // Pre-initialize TTS in background to minimize wait time on first use
      ref.read(ttsProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      // Schedule scroll after the current frame to ensure the UI has been built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _navigateToSettings() async {
    // Store the current health check result to detect changes
    final previousResult = ref.read(healthCheckProvider).lastResult;

    final result = await context.push<String>('/settings');

    if (!mounted) return;

    // Trigger health check after returning from settings
    ref.read(healthCheckProvider.notifier).triggerHealthCheck();

    // If health check result changed, reset banner dismissal to show new state
    final newResult = ref.read(healthCheckProvider).lastResult;
    if (previousResult?.status != newResult?.status ||
        previousResult?.isSuccess != newResult?.isSuccess) {
      setState(() {
        _healthCheckBannerDismissed = false;
      });
    }

    // Show snackbar if settings returned a message
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final ttsState = ref.watch(ttsProvider);
    final healthCheckState = ref.watch(healthCheckProvider);

    // Scroll to bottom whenever messages or pending state changes
    ref.listen<ChatState>(chatProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.showAssistantPending != next.showAssistantPending) {
        _scrollToBottom();
      }
    });

    // Show SnackBar when permanent audio focus loss occurs
    ref.listen<AudioCoordinatorState>(audioCoordinatorProvider, (
      previous,
      next,
    ) {
      if (previous?.audioFocusState.status != AudioFocusStatus.permanentLoss &&
          next.audioFocusState.status == AudioFocusStatus.permanentLoss) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice mode changed because another app needs audio'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    });

    // Show status for retry state changes
    ref.listen<ChatState>(chatProvider, (previous, next) {
      if (previous?.retryState.status != next.retryState.status) {
        if (next.retryState.isRetrying && next.retryState.retryCount == 1) {
          // Only show snackbar on first retry to avoid spam
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection issue detected. Retrying...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        // No snackbar for final failure - error will be shown in chat
      }
    });

    return Scaffold(
      appBar: AppBar(
        actions: [
          const VoiceModeSelector(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
          if (chatState.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                ref.read(chatProvider.notifier).clearChat();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Show health check error banner if there's an issue
            if (!_healthCheckBannerDismissed &&
                healthCheckState.lastResult != null &&
                !healthCheckState.lastResult!.isSuccess)
              _buildHealthCheckBanner(context, healthCheckState.lastResult!),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  ChatHistory(
                    messages: chatState.messages,
                    showAssistantPending: chatState.showAssistantPending,
                    retryState: chatState.retryState,
                    onRetry: (text) {
                      ref.read(chatProvider.notifier).sendMessage(text);
                    },
                    onSpeak: (text, messageId) {
                      final status = ttsState.getMessageState(messageId).status;
                      final ttsNotifier = ref.read(ttsProvider.notifier);

                      switch (status) {
                        case MessagePlaybackStatus.playing:
                          // Pause if currently playing
                          ttsNotifier.pause();
                        case MessagePlaybackStatus.paused:
                          // Resume if paused
                          ttsNotifier.resume();
                        case MessagePlaybackStatus.idle:
                        case MessagePlaybackStatus.completed:
                        case MessagePlaybackStatus.error:
                          // Play from beginning
                          ttsNotifier.playNow(text, messageId);
                        case MessagePlaybackStatus.generating:
                          // Do nothing while generating
                          break;
                      }
                    },
                    getMessagePlaybackStatus: (messageId) =>
                        ttsState.getMessageState(messageId).status,
                  ),
                ],
              ),
            ),
            ChatInput(
              onSubmitted: (text) {
                ref.read(chatProvider.notifier).sendMessage(text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthCheckBanner(
    BuildContext context,
    HealthCheckResult result,
  ) {
    final theme = Theme.of(context);
    final bool isAuthIssue = result.requiresAuth ||
        result.status == HealthCheckStatus.authFailed;

    String title;
    String message;
    String actionText;

    if (result.requiresAuth) {
      title = 'Authentication Required';
      message =
          'The API requires authentication. Please configure your credentials in settings.';
      actionText = 'Configure Auth';
    } else if (result.status == HealthCheckStatus.authFailed) {
      title = 'Authentication Failed';
      message =
          'The API rejected your credentials. Please check your username and password in settings.';
      actionText = 'Check Credentials';
    } else {
      title = 'Connection Issue';
      message = result.message;
      actionText = 'Check Settings';
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isAuthIssue ? Icons.lock : Icons.warning,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: theme.colorScheme.onErrorContainer,
                ),
                onPressed: () {
                  setState(() {
                    _healthCheckBannerDismissed = true;
                  });
                },
                tooltip: 'Dismiss',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _navigateToSettings,
                icon: const Icon(Icons.settings),
                label: Text(actionText),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
