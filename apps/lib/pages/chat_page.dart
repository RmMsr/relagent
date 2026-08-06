import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/chat/widgets.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/chat_provider.dart';
import '/providers/health_check_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/services/api_health_check.dart';
import '/theme/app_colors.dart';

import '/widgets/voice_mode_selector.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _healthCheckBannerDismissed = false;
  final GlobalKey _chatInputKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final capabilities = ref.read(voiceCapabilitiesProvider);
      if (capabilities.isAsrAvailable) {
        ref.read(recordingProvider.notifier).checkAutoStart();
      }
      if (capabilities.isTtsAvailable) {
        ref.read(ttsProvider.notifier).initialize();
      }
      final chatInputState = _chatInputKey.currentState as ChatInputState?;
      if (chatInputState != null) {
        chatInputState.requestFocus();
      }
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
      final renderBox =
          _chatInputKey.currentContext?.findRenderObject() as RenderBox?;
      final inputHeight = renderBox?.size.height ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: inputHeight + 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final ttsState = ref.watch(ttsProvider);
    final healthCheckState = ref.watch(healthCheckProvider);
    final voiceCapabilities = ref.watch(voiceCapabilitiesProvider);

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

    // Health check recovery: dismiss banner on fail→success transition
    ref.listen<HealthCheckState>(healthCheckProvider, (previous, next) {
      final wasFailing =
          previous?.lastResult != null && !previous!.lastResult!.isSuccess;
      final nowSucceeding =
          next.lastResult != null && next.lastResult!.isSuccess;
      if (wasFailing && nowSucceeding) {
        setState(() {
          _healthCheckBannerDismissed = true;
        });
      }
    });

    return Scaffold(
      drawer: NavigationDrawer(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          Navigator.pop(context);
          switch (index) {
            case 0:
              break;
            case 1:
              _navigateToSettings();
            case 2:
              context.push('/info');
          }
        },
        children: const [
          SizedBox(height: 16),
          NavigationDrawerDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: Text('Chat'),
          ),
          Divider(indent: 28, endIndent: 28),
          NavigationDrawerDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: Text('Settings'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.info_outline),
            selectedIcon: Icon(Icons.info),
            label: Text('About'),
          ),
        ],
      ),
      appBar: AppBar(
        actions: [
          if (voiceCapabilities.isAsrAvailable &&
              ref.watch(settingsProvider).continuousVoiceEnabled) ...[
            const VoiceModeSelector(),
            const SizedBox(width: 8),
          ],
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
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: AppTheme.chatContentMaxWidth,
                    ),
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          ChatHistory(
                            messages: chatState.messages,
                            showAssistantPending: chatState.showAssistantPending,
                            retryState: chatState.retryState,
                            isVoiceAvailable: voiceCapabilities.isAsrAvailable,
                            onRetry: (text) {
                              ref.read(chatProvider.notifier).sendMessage(text);
                            },
                            onSpeak: !voiceCapabilities.isTtsAvailable
                                ? null
                                : (text, messageId) {
                                    final status = ttsState
                                        .getMessageState(messageId)
                                        .status;
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
                            getMessageTtsState: (messageId) =>
                                ttsState.getMessageState(messageId),
                            onSkipPrevious: !voiceCapabilities.isTtsAvailable
                                ? null
                                : (messageId) => ref
                                    .read(ttsProvider.notifier)
                                    .skipPreviousChunk(messageId),
                            onSkipNext: !voiceCapabilities.isTtsAvailable
                                ? null
                                : (messageId) => ref
                                    .read(ttsProvider.notifier)
                                    .skipNextChunk(messageId),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ChatInput(
              key: _chatInputKey,
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
    final bool isAuthIssue =
        result.requiresAuth || result.status == HealthCheckStatus.authFailed;

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
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.errorBg,
        border: Border(
          left: BorderSide(color: context.errorBorder, width: 4),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(10),
          bottomRight: Radius.circular(10),
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
                color: context.errorText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: context.errorText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: context.errorText,
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
              color: context.errorText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(healthCheckProvider.notifier)
                      .performImmediateHealthCheck();
                  setState(() {
                    _healthCheckBannerDismissed = false;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.errorText,
                  side: BorderSide(color: context.errorText),
                ),
              ),
              const SizedBox(width: 8),
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
