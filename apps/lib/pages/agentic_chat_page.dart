import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/agentic/health_check.dart';
import '/agentic/widgets.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/engine_health_check_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/sse_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/widgets/voice_mode_selector.dart';

class AgenticChatPage extends ConsumerStatefulWidget {
  const AgenticChatPage({super.key});

  @override
  ConsumerState<AgenticChatPage> createState() => _AgenticChatPageState();
}

class _AgenticChatPageState extends ConsumerState<AgenticChatPage>
    with WidgetsBindingObserver {
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
          previous?.showAssistantPending != next.showAssistantPending ||
          previous?.queuedMessage != next.queuedMessage) {
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

    // Health check recovery: dismiss banner + reload data on fail→success
    ref.listen<EngineHealthCheckState>(engineHealthCheckProvider, (
      previous,
      next,
    ) {
      final wasFailing =
          previous?.lastResult != null && !previous!.lastResult!.isSuccess;
      final nowSucceeding =
          next.lastResult != null && next.lastResult!.isSuccess;
      if (wasFailing && nowSucceeding) {
        setState(() {
          _healthCheckBannerDismissed = true;
        });
        ref.read(agenticChatProvider.notifier).loadHistory();
        ref.read(sseProvider.notifier).reconnect();
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
              context.push('/sessions');
            case 2:
              _navigateToSettings();
            case 3:
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
          NavigationDrawerDestination(
            icon: Icon(Icons.list_outlined),
            selectedIcon: Icon(Icons.list),
            label: Text('Sessions'),
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
        title: chatState.sessionTitle != null
            ? Text(
                chatState.sessionTitle!,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        actions: [
          if (ref.watch(voiceCapabilitiesProvider).isAsrAvailable &&
              ref.watch(settingsProvider).continuousVoiceEnabled) ...[
            const VoiceModeSelector(),
            const SizedBox(width: 8),
          ],
          const SensitivityIndicator(inAppBar: true),
          if (ref.watch(settingsProvider).agenticSessionId != null)
            IconButton(
              icon: const Icon(Icons.local_fire_department_outlined),
              tooltip: 'Purge session',
              onPressed: () => _showPurgeConfirmation(),
            ),
          IconButton(
            icon: const Icon(Icons.restore_page_outlined),
            tooltip: 'New Session',
            onPressed: () {
              ref.read(agenticChatProvider.notifier).clearChat();
              _showSnackBar('New session started');
            },
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
                padding: const EdgeInsets.only(bottom: 8, top: 4),
                children: [
                  AgenticChatHistory(
                        messages: chatState.messages,
                        showAssistantPending: chatState.showAssistantPending,
                        engineHealthResult: healthCheckState.lastResult,
                        sensitivityLevel: chatState.sensitivityLevel,
                        isVoiceAvailable: ref
                            .watch(voiceCapabilitiesProvider)
                            .isAsrAvailable,
                        onRetry: () {
                          ref
                              .read(agenticChatProvider.notifier)
                              .retryFailedMessages();
                        },
                        onSpeak:
                            !ref.watch(voiceCapabilitiesProvider).isTtsAvailable
                            ? null
                            : (text, messageId) {
                                final status = ttsState
                                    .getMessageState(messageId)
                                    .status;
                                final ttsNotifier = ref.read(
                                  ttsProvider.notifier,
                                );

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
                        onChangeSensitivity: (level) {
                          ref
                              .read(agenticChatProvider.notifier)
                              .changeSensitivity(level);
                        },
                        onGrantApproval: (approval, grant, isGlobal) {
                          // ignore: discarded_futures
                          ref
                              .read(agenticChatProvider.notifier)
                              .grantApproval(
                                approvalId: approval.id,
                                grant: grant,
                                isGlobal: isGlobal,
                              );
                        },
                        onDeclineApproval: (approvalId) {
                          // ignore: discarded_futures
                          ref
                              .read(agenticChatProvider.notifier)
                              .declineApproval(approvalId);
                        },
                        onContinue: () {
                          ref
                              .read(agenticChatProvider.notifier)
                              .triggerContinuation();
                        },
                        onStop: _onStop,
                        queuedMessage: chatState.queuedMessage,
                        onEditQueued: _pullQueuedToInput,
                      ),
                    ],
                  ),
            ),
            AgenticChatInput(
              key: _chatInputKey,
              enabled: chatState.inputEnabled,
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
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      final chatInputState =
          _chatInputKey.currentState as AgenticChatInputState?;
      if (chatInputState != null) {
        chatInputState.requestFocus();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(sseProvider.notifier).connect();
    }
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
              OutlinedButton.icon(
                onPressed: () {
                  ref
                      .read(engineHealthCheckProvider.notifier)
                      .triggerHealthCheck();
                  setState(() {
                    _healthCheckBannerDismissed = false;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onErrorContainer,
                  side: BorderSide(color: theme.colorScheme.onErrorContainer),
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

  Future<void> _navigateToSettings() async {
    final previousResult = ref.read(engineHealthCheckProvider).lastResult;

    final result = await context.push<String>('/settings');

    if (!mounted) return;

    // Check engine health after settings change
    ref.read(engineHealthCheckProvider.notifier).triggerHealthCheck();
    ref.read(agenticChatProvider.notifier).loadHistory();
    ref.read(sseProvider.notifier).reconnect();

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

  void _pullQueuedToInput() {
    final text = ref.read(agenticChatProvider.notifier).editQueued();
    if (text == null) return;
    final inputState = _chatInputKey.currentState as AgenticChatInputState?;
    inputState?.setText(text);
  }

  // Stop with queued: pull queued text back into input first, then stop.
  // Per §11.8 the queued message is preserved as input rather than discarded.
  void _onStop() {
    _pullQueuedToInput();
    // ignore: discarded_futures
    ref.read(agenticChatProvider.notifier).stopCycle();
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

  Future<void> _showPurgeConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge Session'),
        content: const Text(
          'Delete this session permanently and start a new one? '
          'This cannot be undone.',
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
            child: const Text('Purge'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(agenticChatProvider.notifier).purgeSession();
      if (!mounted) return;
      _showSnackBar('Session purged');
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
