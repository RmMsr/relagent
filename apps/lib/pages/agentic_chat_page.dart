import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/agentic/health_check.dart';
import '/agentic/widgets.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/engine_health_check_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/sse_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/widgets/voice_mode_selector.dart';

class AgenticChatPage extends ConsumerStatefulWidget {
  const AgenticChatPage({super.key});

  @override
  ConsumerState<AgenticChatPage> createState() => _AgenticChatPageState();
}

class _AgenticChatPageState extends ConsumerState<AgenticChatPage> {
  final ScrollController _scrollController = ScrollController();
  bool _healthCheckBannerDismissed = false;
  final GlobalKey _chatInputKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(agenticChatProvider);
    final ttsState = ref.watch(ttsProvider);
    final healthCheckState = ref.watch(engineHealthCheckProvider);

    ref.listen<AgenticChatState>(agenticChatProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length ||
          previous?.showAssistantPending != next.showAssistantPending) {
        _scrollToBottom();
      }
    });

    ref.listen<AudioCoordinatorState>(audioCoordinatorProvider, (
      previous,
      next,
    ) {
      if (previous?.audioFocusState.status != AudioFocusStatus.permanentLoss &&
          next.audioFocusState.status == AudioFocusStatus.permanentLoss) {
        _showSnackBar('Voice mode changed because another app needs audio');
      }
    });

    ref.listen<SseState>(sseProvider, (previous, next) {
      if (next.activeSessionDeleted != null) {
        _showSnackBar('Session was deleted - started new session');
        ref.read(sseProvider.notifier).clearActiveSessionDeleted();
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: PopupMenuButton<String>(
          icon: const Icon(Icons.menu),
          tooltip: 'Navigation',
          onSelected: (route) {
            if (route == '/simple') {
              context.go('/simple');
            } else if (route == '/info') {
              context.push('/info');
            } else if (route == '/sessions') {
              context.push('/sessions');
            } else if (route == '/settings') {
              context.push('/settings');
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: '/agentic',
              enabled: false,
              child: Row(
                children: [
                  Icon(Icons.smart_toy),
                  SizedBox(width: 12),
                  Text('Agentic Chat'),
                  Spacer(),
                  Icon(Icons.check, size: 18),
                ],
              ),
            ),
            const PopupMenuItem(
              value: '/simple',
              child: Row(
                children: [
                  Icon(Icons.chat_bubble_outline),
                  SizedBox(width: 12),
                  Text('Simple Chat'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: '/sessions',
              child: Row(
                children: [
                  Icon(Icons.list),
                  SizedBox(width: 12),
                  Text('Recent Sessions'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: '/settings',
              child: Row(
                children: [
                  Icon(Icons.settings),
                  SizedBox(width: 12),
                  Text('Settings'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: '/info',
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Text('About'),
                ],
              ),
            ),
          ],
        ),
        title: chatState.sessionTitle != null
            ? Text(
                chatState.sessionTitle!,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        actions: [
          if (ref.watch(voiceCapabilitiesProvider).isAsrAvailable) ...[
            const VoiceModeSelector(),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.restore_page),
            tooltip: 'New Session',
            onPressed: () {
              ref.read(agenticChatProvider.notifier).clearChat();
              _showSnackBar('New session started');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_healthCheckBannerDismissed &&
                healthCheckState.lastResult != null &&
                !healthCheckState.lastResult!.isSuccess)
              _buildHealthCheckBanner(context, healthCheckState.lastResult!),
            if (chatState.isLoadingHistory) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  AgenticChatHistory(
                    messages: chatState.messages,
                    showAssistantPending: chatState.showAssistantPending,
                    engineHealthResult: healthCheckState.lastResult,
                    isVoiceAvailable: ref.watch(voiceCapabilitiesProvider).isAsrAvailable,
                    onRetry: () {
                      ref
                          .read(agenticChatProvider.notifier)
                          .retryFailedMessages();
                    },
                    onSpeak: !ref.watch(voiceCapabilitiesProvider).isTtsAvailable
                        ? null
                        : (text, messageId) {
                      final status = ttsState.getMessageState(messageId).status;
                      final ttsNotifier = ref.read(ttsProvider.notifier);

                      switch (status) {
                        case MessagePlaybackStatus.playing:
                          ttsNotifier.pause();
                        case MessagePlaybackStatus.paused:
                          ttsNotifier.resume();
                        case MessagePlaybackStatus.idle:
                        case MessagePlaybackStatus.completed:
                        case MessagePlaybackStatus.error:
                          ttsNotifier.playNow(text, messageId);
                        case MessagePlaybackStatus.generating:
                          break;
                      }
                    },
                    getMessagePlaybackStatus: (messageId) =>
                        ttsState.getMessageState(messageId).status,
                  ),
                ],
              ),
            ),
            AgenticChatInput(
              key: _chatInputKey,
              onSubmitted: (text) {
                ref.read(agenticChatProvider.notifier).sendMessage(text);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(engineHealthCheckProvider.notifier).triggerHealthCheck();
      ref.read(agenticChatProvider.notifier).loadHistory();
      ref.read(agenticChatProvider.notifier).loadSessionInfo();
      final capabilities = ref.read(voiceCapabilitiesProvider);
      if (capabilities.isAsrAvailable) {
        ref.read(recordingProvider.notifier).checkAutoStart();
      }
      if (capabilities.isTtsAvailable) {
        ref.read(ttsProvider.notifier).initialize();
      }
      ref.read(sseProvider.notifier).connect();
    });
  }

  Widget _buildHealthCheckBanner(
    BuildContext context,
    EngineHealthResult result,
  ) {
    final theme = Theme.of(context);
    final isAuthIssue =
        result.requiresAuth || result.status == EngineHealthStatus.authFailed;

    String title;
    String message;
    String actionText;

    if (result.requiresAuth) {
      title = 'Authentication Required';
      message =
          'The engine requires authentication. '
          'Configure credentials in settings.';
      actionText = 'Configure Auth';
    } else if (result.status == EngineHealthStatus.authFailed) {
      title = 'Authentication Failed';
      message = 'Check your engine username and password.';
      actionText = 'Check Credentials';
    } else {
      title = 'Engine Connection Issue';
      message = result.message;
      actionText = 'Check Settings';
    }

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error, width: 1),
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

  Future<void> _navigateToSettings() async {
    final previousResult = ref.read(engineHealthCheckProvider).lastResult;

    final result = await context.push<String>('/settings');

    if (!mounted) return;

    // Check engine health after settings change
    ref.read(engineHealthCheckProvider.notifier).triggerHealthCheck();
    ref.read(agenticChatProvider.notifier).loadHistory();
    ref.read(sseProvider.notifier).connect();

    // Reset banner if health status changed
    final newResult = ref.read(engineHealthCheckProvider).lastResult;
    if (previousResult?.status != newResult?.status) {
      setState(() {
        _healthCheckBannerDismissed = false;
      });
    }

    if (result != null && mounted) {
      _showSnackBar(result);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
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

  void _showSnackBar(String message) {
    final renderBox =
        _chatInputKey.currentContext?.findRenderObject() as RenderBox?;
    final inputHeight = renderBox?.size.height ?? 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(bottom: inputHeight + 8),
        showCloseIcon: true,
      ),
    );
  }
}
