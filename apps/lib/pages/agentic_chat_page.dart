import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/agentic/health_check.dart';
import '/agentic/models.dart';
import '/agentic/widgets.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/audio_coordinator_provider.dart';
import '/providers/displayed_session_provider.dart';
import '/providers/engine_health_check_provider.dart';
import '/providers/new_chat_draft_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/sse_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/theme/app_colors.dart';

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

  // Tracks the fields that should trigger an auto-scroll, across whichever
  // of the two possible source providers (draft or a session's own
  // instance) is currently backing `chatState` below.
  int? _lastMessageCount;
  bool? _lastShowAssistantPending;
  String? _lastQueuedMessage;

  @override
  Widget build(BuildContext context) {
    final displayedSessionId = ref.watch(displayedSessionProvider);

    final AgenticChatState chatState;
    if (displayedSessionId == null) {
      final draft = ref.watch(newChatDraftProvider);
      chatState = AgenticChatState(
        messages: [
          if (draft.pendingUserMessage != null) draft.pendingUserMessage!,
          if (draft.error != null) AgenticMessage.error(draft.error!),
        ],
        isLoading: draft.isLoading,
        showAssistantPending: draft.isLoading,
        sensitivityLevel: draft.sensitivityLevel,
      );
    } else {
      chatState = ref.watch(agenticChatProvider(displayedSessionId));
    }

    final ttsState = ref.watch(ttsProvider);
    final healthCheckState = ref.watch(engineHealthCheckProvider);

    if (_lastMessageCount != chatState.messages.length ||
        _lastShowAssistantPending != chatState.showAssistantPending ||
        _lastQueuedMessage != chatState.queuedMessage) {
      _lastMessageCount = chatState.messages.length;
      _lastShowAssistantPending = chatState.showAssistantPending;
      _lastQueuedMessage = chatState.queuedMessage;
      _scrollToBottom();
    }

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
        final sessionId = ref.read(displayedSessionProvider);
        if (sessionId != null) {
          ref.read(agenticChatProvider(sessionId).notifier).refreshFromServer();
        }
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
          if (displayedSessionId != null)
            IconButton(
              icon: const Icon(Icons.local_fire_department_outlined),
              tooltip: 'Purge session',
              onPressed: () => _showPurgeConfirmation(),
            ),
          IconButton(
            icon: const Icon(Icons.restore_page_outlined),
            tooltip: 'New Session',
            onPressed: () {
              ref.read(displayedSessionProvider.notifier).show(null);
              ref.read(ttsProvider.notifier).onChatCleared();
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
                            onRetry: displayedSessionId == null
                                ? null
                                : () {
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .retryFailedMessages();
                                  },
                            onCancel: displayedSessionId == null
                                ? null
                                : () {
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .cancelFailedMessages();
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
                            getMessageTtsState: (messageId) =>
                                ttsState.getMessageState(messageId),
                            onSkipPrevious:
                                !ref.watch(voiceCapabilitiesProvider).isTtsAvailable
                                ? null
                                : (messageId) => ref
                                    .read(ttsProvider.notifier)
                                    .skipPreviousChunk(messageId),
                            onSkipNext:
                                !ref.watch(voiceCapabilitiesProvider).isTtsAvailable
                                ? null
                                : (messageId) => ref
                                    .read(ttsProvider.notifier)
                                    .skipNextChunk(messageId),
                            onChangeSensitivity: (level) {
                              if (displayedSessionId == null) {
                                ref
                                    .read(newChatDraftProvider.notifier)
                                    .changeSensitivity(level);
                              } else {
                                ref
                                    .read(
                                      agenticChatProvider(
                                        displayedSessionId,
                                      ).notifier,
                                    )
                                    .changeSensitivity(level);
                              }
                            },
                            onGrantApproval: displayedSessionId == null
                                ? null
                                : (approval, grant, isGlobal) {
                                    // ignore: discarded_futures
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .grantApproval(
                                          approvalId: approval.id,
                                          grant: grant,
                                          isGlobal: isGlobal,
                                        );
                                  },
                            onDeclineApproval: displayedSessionId == null
                                ? null
                                : (approvalId) {
                                    // ignore: discarded_futures
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .declineApproval(approvalId);
                                  },
                            onDeclineAllApprovals: displayedSessionId == null
                                ? null
                                : (approvalIds) {
                                    // ignore: discarded_futures
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .declineAllAndContinue(approvalIds);
                                  },
                            onContinue: displayedSessionId == null
                                ? null
                                : () {
                                    ref
                                        .read(
                                          agenticChatProvider(
                                            displayedSessionId,
                                          ).notifier,
                                        )
                                        .triggerContinuation();
                                  },
                            onStop: displayedSessionId == null
                                ? null
                                : _onStop,
                            queuedMessage: chatState.queuedMessage,
                            onEditQueued: displayedSessionId == null
                                ? null
                                : _pullQueuedToInput,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AgenticChatInput(
              key: _chatInputKey,
              enabled: chatState.inputEnabled,
              onSubmitted: (text) {
                final sessionId = ref.read(displayedSessionProvider);
                if (sessionId == null) {
                  ref.read(newChatDraftProvider.notifier).sendMessage(text);
                } else {
                  ref
                      .read(agenticChatProvider(sessionId).notifier)
                      .sendMessage(text);
                }
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
      final sessionId = ref.read(displayedSessionProvider);
      if (sessionId != null) {
        final notifier = ref.read(agenticChatProvider(sessionId).notifier);
        notifier.refreshFromServer();
        notifier.loadSessionInfo();
      }
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
      // SSE reconnect trusts `lastEventId` replay, which can miss events
      // across a gap. Reconcile the displayed session directly rather than
      // relying on that alone (see design Decision 5).
      final sessionId = ref.read(displayedSessionProvider);
      if (sessionId != null) {
        ref.read(agenticChatProvider(sessionId).notifier).refreshFromServer();
      }
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
                      .read(engineHealthCheckProvider.notifier)
                      .triggerHealthCheck();
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

  Future<void> _navigateToSettings() async {
    final previousResult = ref.read(engineHealthCheckProvider).lastResult;

    final result = await context.push<String>('/settings');

    if (!mounted) return;

    // Check engine health after settings change
    ref.read(engineHealthCheckProvider.notifier).triggerHealthCheck();
    final sessionId = ref.read(displayedSessionProvider);
    if (sessionId != null) {
      ref.read(agenticChatProvider(sessionId).notifier).refreshFromServer();
    }
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
    final sessionId = ref.read(displayedSessionProvider);
    if (sessionId == null) return;
    final text = ref.read(agenticChatProvider(sessionId).notifier).editQueued();
    if (text == null) return;
    final inputState = _chatInputKey.currentState as AgenticChatInputState?;
    inputState?.setText(text);
  }

  // Stop with queued: pull queued text back into input first, then stop.
  // Per §11.8 the queued message is preserved as input rather than discarded.
  void _onStop() {
    final sessionId = ref.read(displayedSessionProvider);
    if (sessionId == null) return;
    _pullQueuedToInput();
    // ignore: discarded_futures
    ref.read(agenticChatProvider(sessionId).notifier).stopCycle();
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
    final sessionId = ref.read(displayedSessionProvider);
    if (sessionId == null) return;

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
      await ref.read(agenticChatProvider(sessionId).notifier).purgeSession();
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
