import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';

import '/agentic/approval_card.dart';
import '/agentic/health_check.dart';
import '/agentic/models.dart';
import '/models/app_info.dart';
import '/providers/recording_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/speech_recognition/recording_target.dart';
import '/speech_recognition/widgets.dart';
import '/tts/text_chunker.dart';
import '/utils/logger.dart';
import '/theme/app_colors.dart';
import '/widgets/message_markdown_actions.dart';
import '/widgets/tts_chunk_controls.dart';
import '/widgets/version_info_widget.dart';

export '/agentic/approval_card.dart';
export '/agentic/sensitivity_widgets.dart';

class AgenticChatInput extends ConsumerStatefulWidget {
  final ValueChanged<String> onSubmitted;
  final bool enabled;

  const AgenticChatInput({
    super.key,
    required this.onSubmitted,
    this.enabled = true,
  });

  @override
  ConsumerState<AgenticChatInput> createState() => AgenticChatInputState();
}

class AgenticChatInputState extends ConsumerState<AgenticChatInput>
    implements RecordingTarget {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _textBeforeRecording = '';
  bool _isUpdatingFromASR = false;
  // The field text last written by ASR. Controller notifications carrying this
  // value are ASR echoes (incl. async IME echoes) and must NOT move the
  // baseline; only genuine user edits do. Timing guards alone are not enough
  // because a focused field re-notifies after the synchronous write.
  String _lastAsrText = '';
  RecordingNotifier? _recordingNotifier;

  void requestFocus() {
    _focusNode.requestFocus();
  }

  // Used by the edit-queued flow. Per OQ1 input is overwritten unconditionally.
  void setText(String text) {
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      _textBeforeRecording = text;
    });
    _focusNode.requestFocus();
  }

  void _submitText() {
    final text = _controller.text;
    if (text == '') return;

    final recordingState = ref.read(recordingProvider);
    if (recordingState.isRecording && !recordingState.isContinuous) {
      ref.read(recordingProvider.notifier).stopDictation();
    }

    widget.onSubmitted(_controller.text);
    setState(() {
      _controller.clear();
      _textBeforeRecording = '';
      _lastAsrText = '';
    });
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    // Keep baseline in sync with user edits between ASR utterances
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(voiceCapabilitiesProvider).isAsrAvailable) {
        _recordingNotifier = ref.read(recordingProvider.notifier);
        _recordingNotifier!.registerTarget(this);
      }
    });
  }

  void _onControllerChanged() {
    if (_isUpdatingFromASR || _controller.text == _lastAsrText) return;
    _textBeforeRecording = _controller.text;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _recordingNotifier?.unregisterTarget(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void onTextRecognized(String text) {
    if (text.isEmpty) return;

    Logger.debug(
      '[AgenticChatInput] onTextRecognized: baseline="$_textBeforeRecording", text="$text"',
    );

    _isUpdatingFromASR = true;
    setState(() {
      _controller.text = _textBeforeRecording + text;
      _lastAsrText = _controller.text;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    _isUpdatingFromASR = false;
  }

  @override
  void onTextFinished() {
    final recordingState = ref.read(recordingProvider);
    Logger.debug(
      '[AgenticChatInput] onTextFinished: continuous=${recordingState.isContinuous}',
    );

    if (recordingState.isContinuous) {
      _submitText();
    } else {
      setState(() {
        _textBeforeRecording = _controller.text;
      });
    }
  }

  @override
  void onRecordingStarted() {
    _textBeforeRecording = _controller.text;
  }

  @override
  void onRecordingStopped() {}

  @override
  void onError(String error) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: TextField(
                autofocus: true,
                controller: _controller,
                focusNode: _focusNode,
                enabled: enabled,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: enabled
                      ? 'Type a message...'
                      : 'Wait for response or edit queued message',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submitText(),
              ),
            ),
          ),
          if (ref.watch(voiceCapabilitiesProvider).isAsrAvailable)
            RecorderButton(),
          IconButton(
            icon: Icon(Icons.send, color: Theme.of(context).colorScheme.primary),
            onPressed: enabled ? _submitText : null,
            tooltip: 'Send message',
          ),
        ],
      ),
    );
  }
}

class _MessageGroup {
  final AgenticRole sender;
  final List<AgenticMessage> messages;
  final DateTime firstMessageTime;

  _MessageGroup({
    required this.sender,
    required this.messages,
    required this.firstMessageTime,
  });

  bool shouldBreakGroup(AgenticMessage nextMessage) {
    // System messages always stand alone
    if (nextMessage.role == AgenticRole.system ||
        sender == AgenticRole.system) {
      return true;
    }
    if (nextMessage.role != sender) return true;
    final lastMessageTime = messages.last.timestamp;
    final timeDiff = nextMessage.timestamp.difference(lastMessageTime);
    return timeDiff.inMinutes > 5;
  }
}

List<_MessageGroup> _groupMessages(List<AgenticMessage> messages) {
  final groups = <_MessageGroup>[];
  _MessageGroup? currentGroup;

  for (final message in messages) {
    if (currentGroup == null || currentGroup.shouldBreakGroup(message)) {
      currentGroup = _MessageGroup(
        sender: message.role,
        messages: [message],
        firstMessageTime: message.timestamp,
      );
      groups.add(currentGroup);
    } else {
      currentGroup.messages.add(message);
    }
  }

  return groups;
}

class AgenticChatHistory extends StatelessWidget {
  final List<AgenticMessage> messages;
  final bool showAssistantPending;
  final void Function(String, String)? onSpeak;
  final MessageTtsState Function(String)? getMessageTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;
  final EngineHealthResult? engineHealthResult;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final bool isVoiceAvailable;
  final SensitivityLevel sensitivityLevel;
  final ValueChanged<SensitivityLevel>? onChangeSensitivity;
  final void Function(ApprovalData, GrantRequest, bool isGlobal)?
      onGrantApproval;
  final ValueChanged<String>? onDeclineApproval;
  final void Function(List<String> approvalIds)? onDeclineAllApprovals;
  final VoidCallback? onContinue;
  final VoidCallback? onStop;
  final String? queuedMessage;
  final VoidCallback? onEditQueued;

  const AgenticChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
    this.onSpeak,
    this.getMessageTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
    this.engineHealthResult,
    this.onRetry,
    this.onCancel,
    this.isVoiceAvailable = false,
    this.sensitivityLevel = SensitivityLevel.personal,
    this.onChangeSensitivity,
    this.onGrantApproval,
    this.onDeclineApproval,
    this.onDeclineAllApprovals,
    this.onContinue,
    this.onStop,
    this.queuedMessage,
    this.onEditQueued,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatWidgets = <Widget>[];

    if (messages.isEmpty && !showAssistantPending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 80,
                color: theme.colorScheme.primary.withAlpha((255 * 0.3).round()),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to ${AppInfo.data.name}',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const VersionInfoWidget(),
              if (engineHealthResult != null &&
                  engineHealthResult!.isSuccess) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Connected to ${engineHealthResult!.engineName ?? 'Engine'} v${engineHealthResult!.engineVersion ?? '?'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              Text(
                isVoiceAvailable
                    ? 'Start a conversation by typing a message or using voice input'
                    : 'Start a conversation by typing a message',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final groups = _groupMessages(messages);

    for (int groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final group = groups[groupIndex];
      final isLastGroup = groupIndex == groups.length - 1;

      // System messages get special rendering
      if (group.sender == AgenticRole.system) {
        for (final message in group.messages) {
          final hasApprovals =
              message.approvals != null && message.approvals!.isNotEmpty;
          final isLastMessage = groupIndex == groups.length - 1;

          if (hasApprovals) {
            // Approval group with actionable cards
            // Historical approvals (not the latest) render as resolved
            final formattedTime =
                DateFormat('HH:mm:ss').format(message.timestamp.toLocal());
            chatWidgets.add(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                      bottom: 4,
                      left: 12,
                    ),
                    child: Builder(
                      builder: (context) {
                        final theme = Theme.of(context);
                        return Text(
                          'system • $formattedTime',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  ApprovalGroup(
                    message: message,
                    sessionSensitivity: sensitivityLevel,
                    isActionable: isLastMessage,
                    isAgentRunInFlight: showAssistantPending,
                    onChangeSensitivity: onChangeSensitivity,
                    onGrant: onGrantApproval,
                    onDecline: onDeclineApproval,
                    onDeclineAll: isLastMessage ? onDeclineAllApprovals : null,
                    onContinue: isLastMessage ? onContinue : null,
                    onStop: isLastMessage ? onStop : null,
                  ),
                ],
              ),
            );
          } else if (message.notification != null) {
            chatWidgets.add(
              SystemNoteBubble(text: message.notification!),
            );
          }
        }
      } else {
        for (int msgIndex = 0;
            msgIndex < group.messages.length;
            msgIndex++) {
          final message = group.messages[msgIndex];
          final isFirstInGroup = msgIndex == 0;
          final isLastInGroup =
              msgIndex == group.messages.length - 1;

          chatWidgets.add(
            _AgenticMessageBubble(
              message: message,
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onSpeak: onSpeak,
              getMessageTtsState: getMessageTtsState,
              onSkipPrevious: onSkipPrevious,
              onSkipNext: onSkipNext,
              onRetry: onRetry,
              onCancel: onCancel,
            ),
          );
        }
      }

      if (!isLastGroup) {
        chatWidgets.add(const SizedBox(height: 16));
      }
    }

    if (showAssistantPending) {
      chatWidgets.add(const _AssistantPendingPlaceholder());
    }

    if (queuedMessage != null) {
      chatWidgets.add(
        QueuedMessageBubble(
          text: queuedMessage!,
          onEdit: onEditQueued,
        ),
      );
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: chatWidgets,
      ),
    );
  }
}

class _AgenticMessageBubble extends StatelessWidget {
  final AgenticMessage message;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final void Function(String, String)? onSpeak;
  final MessageTtsState Function(String)? getMessageTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const _AgenticMessageBubble({
    required this.message,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    this.onSpeak,
    this.getMessageTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
    this.onRetry,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == AgenticRole.user;
    final isError = message.role == AgenticRole.error;

    final timeFormat = DateFormat('HH:mm:ss');
    final formattedTime = timeFormat.format(message.timestamp.toLocal());

    return Container(
      margin: EdgeInsets.only(
        left: isUser ? 40 : 8,
        right: 8,
        top: isFirstInGroup ? 8 : 2,
        bottom: isLastInGroup ? 8 : 2,
      ),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (isFirstInGroup)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Text(
                '${isUser ? 'user' : 'assistant'} • $formattedTime',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (isError)
            _ErrorMessageBubble(message: message)
          else if (isUser)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1.5),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.text,
                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: _buildMessageBody(
                context,
                theme,
                getMessageTtsState?.call(message.localId) ??
                    const MessageTtsState(),
              ),
            ),
          if (isUser && !isError)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: MessageCopyButton(text: message.text),
            ),
          if (!isUser && !isError)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: _MessageActionsRow(
                messageId: message.localId,
                messageText: message.text,
                stats: message.stats,
                onSpeak: onSpeak,
                getMessageTtsState: getMessageTtsState,
                onSkipPrevious: onSkipPrevious,
                onSkipNext: onSkipNext,
              ),
            ),
          if (isError && (onRetry != null || onCancel != null))
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (onCancel != null)
                    TextButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Renders the message as one [GptMarkdown] widget per paragraph so the
  /// currently-speaking one can be highlighted while playback has focus.
  Widget _buildMessageBody(
    BuildContext context,
    ThemeData theme,
    MessageTtsState ttsMessageState,
  ) {
    final paragraphs = splitRawParagraphs(message.text);
    if (paragraphs.isEmpty) {
      return GptMarkdown(message.text, onLinkTap: linkTapHandler(context));
    }

    final activeIndex = ttsMessageState.hasPlaybackFocus
        ? ttsMessageState.currentSourceParagraphIndex
        : -1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Container(
            margin: EdgeInsets.only(bottom: i == paragraphs.length - 1 ? 0 : 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: i == activeIndex
                ? BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: GptMarkdown(paragraphs[i], onLinkTap: linkTapHandler(context)),
          ),
      ],
    );
  }
}

class _ErrorMessageBubble extends StatefulWidget {
  final AgenticMessage message;

  const _ErrorMessageBubble({required this.message});

  @override
  State<_ErrorMessageBubble> createState() => _ErrorMessageBubbleState();
}

class _ErrorMessageBubbleState extends State<_ErrorMessageBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetails = widget.message.technicalDetails != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: context.errorText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: context.errorText,
                  ),
                ),
              ),
              if (hasDetails)
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: context.errorText,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                    });
                  },
                  tooltip: _expanded ? 'Hide details' : 'Show details',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (_expanded && hasDetails) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.message.technicalDetails!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.errorText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageActionsRow extends StatefulWidget {
  final String messageId;
  final String messageText;
  final AgentStats? stats;
  final void Function(String, String)? onSpeak;
  final MessageTtsState Function(String)? getMessageTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;

  const _MessageActionsRow({
    required this.messageId,
    required this.messageText,
    this.stats,
    this.onSpeak,
    this.getMessageTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
  });

  @override
  State<_MessageActionsRow> createState() => _MessageActionsRowState();
}

class _MessageActionsRowState extends State<_MessageActionsRow> {
  bool _statsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasStats = widget.stats != null && widget.stats!.hasData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onSpeak != null) ...[
              _SpeakerButton(
                messageId: widget.messageId,
                text: widget.messageText,
                onSpeak: widget.onSpeak!,
                getTtsState: widget.getMessageTtsState,
                onSkipPrevious: widget.onSkipPrevious,
                onSkipNext: widget.onSkipNext,
              ),
              const SizedBox(width: 8),
            ],
            MessageCopyButton(text: widget.messageText),
            if (hasStats) const SizedBox(width: 8),
            if (hasStats)
              IconButton(
                icon: Icon(
                  _statsExpanded ? Icons.insights_outlined : Icons.insights,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _statsExpanded = !_statsExpanded),
                tooltip: _statsExpanded ? 'Hide stats' : 'Show stats',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(32, 32),
                  foregroundColor: _statsExpanded
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (_statsExpanded && hasStats)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: _StatsContent(stats: widget.stats!),
          ),
      ],
    );
  }
}

class _StatsContent extends StatelessWidget {
  final AgentStats stats;
  static final _numberFormat = NumberFormat('#,###');

  const _StatsContent({required this.stats});

  String _formatNumber(int number) => _numberFormat.format(number);

  String _formatDuration(double seconds) {
    if (seconds < 1) {
      return '${(seconds * 1000).round()}ms';
    } else if (seconds < 60) {
      return '${seconds.toStringAsFixed(1)}s';
    } else {
      final mins = (seconds / 60).floor();
      final secs = (seconds % 60).round();
      return '${mins}m ${secs}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final iconColor = theme.colorScheme.onSurfaceVariant;
    const iconSize = 14.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.agentName != null || stats.answeringModelName != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (stats.agentName != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: iconSize,
                        color: iconColor,
                      ),
                      const SizedBox(width: 4),
                      Text('Agent: ${stats.agentName!}', style: textStyle),
                    ],
                  ),
                if (stats.answeringModelName != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.memory, size: iconSize, color: iconColor),
                      const SizedBox(width: 4),
                      Text(
                        'Model: ${stats.answeringModelName!}',
                        style: textStyle,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (stats.inputTokens != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_downward, size: iconSize, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatNumber(stats.inputTokens!)} tokens in',
                    style: textStyle,
                  ),
                ],
              ),
            if (stats.outputTokens != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward, size: iconSize, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatNumber(stats.outputTokens!)} tokens out',
                    style: textStyle,
                  ),
                ],
              ),
            if (stats.toolCallsCount != null && stats.toolCallsCount! > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_outlined, size: iconSize, color: iconColor),
                  const SizedBox(width: 4),
                  Text('${stats.toolCallsCount} tool calls', style: textStyle),
                ],
              ),
            if (stats.requestsCount != null && stats.requestsCount! > 1)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: iconSize, color: iconColor),
                  const SizedBox(width: 4),
                  Text('${stats.requestsCount} requests', style: textStyle),
                ],
              ),
            if (stats.durationSeconds != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timer_outlined, size: iconSize, color: iconColor),
                  const SizedBox(width: 4),
                  Text(
                    _formatDuration(stats.durationSeconds!),
                    style: textStyle,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _SpeakerButton extends StatelessWidget {
  final String messageId;
  final String text;
  final void Function(String, String) onSpeak;
  final MessageTtsState Function(String)? getTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;

  const _SpeakerButton({
    required this.messageId,
    required this.text,
    required this.onSpeak,
    this.getTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    final ttsState = getTtsState?.call(messageId) ?? const MessageTtsState();
    final status = ttsState.status;

    IconData icon;
    String tooltip;

    switch (status) {
      case MessagePlaybackStatus.playing:
        icon = Icons.pause;
        tooltip = 'Pause';
      case MessagePlaybackStatus.paused:
        icon = Icons.play_arrow;
        tooltip = 'Resume';
      case MessagePlaybackStatus.generating:
        icon = Icons.hourglass_empty;
        tooltip = 'Generating audio...';
      default:
        icon = Icons.volume_up_outlined;
        tooltip = 'Read aloud';
    }

    final singleButton = IconButton(
      icon: Icon(icon, size: 18),
      onPressed: status == MessagePlaybackStatus.generating
          ? null
          : () => onSpeak(text, messageId),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
      ),
    );

    final hasPlaybackFocus =
        status == MessagePlaybackStatus.playing ||
        status == MessagePlaybackStatus.paused;

    return AnimatedTtsControls(
      showChunkControls:
          hasPlaybackFocus && onSkipPrevious != null && onSkipNext != null,
      singleButton: singleButton,
      chunkControls: TtsChunkControls(
        isPlaying: status == MessagePlaybackStatus.playing,
        onPlayPause: () => onSpeak(text, messageId),
        onSkipPrevious: () => onSkipPrevious?.call(messageId),
        onSkipNext: () => onSkipNext?.call(messageId),
      ),
    );
  }
}

class _AssistantPendingPlaceholder extends StatefulWidget {
  const _AssistantPendingPlaceholder();

  @override
  State<_AssistantPendingPlaceholder> createState() =>
      _AssistantPendingPlaceholderState();
}

class _AssistantPendingPlaceholderState
    extends State<_AssistantPendingPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(left: 8, right: 8, top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              'assistant',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _opacityAnimation,
            builder: (context, child) {
              return Opacity(
                opacity: _opacityAnimation.value,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Thinking...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// Client-side queued user message rendered inline at the chat-list end.
// Label + edit-pencil sit on the header line so the text is not displaced.
class QueuedMessageBubble extends StatelessWidget {
  final String text;
  final VoidCallback? onEdit;

  const QueuedMessageBubble({
    super.key,
    required this.text,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(left: 40, right: 8, top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Next user message',
                  key: const Key('queued-message-label'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: 4),
                  TextButton.icon(
                    key: const Key('queued-message-edit'),
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 0),
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      textStyle: theme.textTheme.labelSmall,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ),
          CustomPaint(
            painter: _DashedRRectPainter(
              color: theme.colorScheme.primary.withAlpha(160),
              radius: 12,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(110),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(text),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  static const _dashLength = 5.0;
  static const _gapLength = 4.0;
  static const _strokeWidth = 1.2;

  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = _strokeWidth
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + _dashLength).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(dist, next), Offset.zero);
        dist += _dashLength + _gapLength;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

