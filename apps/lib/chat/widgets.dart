import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';
import '/chat/models.dart';

import '/models/app_info.dart';
import '/providers/chat_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/tts_provider.dart';
import '/providers/voice_service_provider.dart';
import '/speech_recognition/recording_target.dart';
import '/speech_recognition/widgets.dart';
import '/utils/logger.dart';
import '/widgets/version_info_widget.dart';

class ChatInput extends ConsumerStatefulWidget {
  final ValueChanged<String> onSubmitted;

  const ChatInput({super.key, required this.onSubmitted});

  @override
  ConsumerState<ChatInput> createState() {
    return ChatInputState();
  }
}

class ChatInputState extends ConsumerState<ChatInput>
    implements RecordingTarget {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _textBeforeRecording = '';
  bool _isUpdatingFromASR = false;
  // Cache notifier reference for use in dispose (ref is already disposed there)
  RecordingNotifier? _recordingNotifier;

  void _submitText() {
    final text = _controller.text;
    if (text == '') {
      return;
    }

    // Stop dictation mode when submitting text (per spec requirement)
    final recordingState = ref.read(recordingProvider);
    if (recordingState.isRecording && !recordingState.isContinuous) {
      ref.read(recordingProvider.notifier).stopDictation();
    }

    widget.onSubmitted(_controller.text);
    setState(() {
      _controller.clear();
      _textBeforeRecording = ''; // Reset baseline to prevent stale text
    });
    // Keep keyboard open by maintaining focus
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    // Keep baseline in sync with user edits between ASR utterances
    _controller.addListener(_onControllerChanged);
    // Register as recording target after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(voiceCapabilitiesProvider).isAsrAvailable) {
        _recordingNotifier = ref.read(recordingProvider.notifier);
        _recordingNotifier!.registerTarget(this);
      }
    });
  }

  void _onControllerChanged() {
    if (!_isUpdatingFromASR) {
      _textBeforeRecording = _controller.text;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    // Unregister using cached notifier (ref is already disposed here)
    _recordingNotifier?.unregisterTarget(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // RecordingTarget implementation
  @override
  void onTextRecognized(String text) {
    if (text.isEmpty) return;

    Logger.debug(
      '[ChatInput] onTextRecognized: baseline="$_textBeforeRecording", text="$text"',
    );

    // Guard against listener updating baseline while ASR is writing
    _isUpdatingFromASR = true;
    setState(() {
      _controller.text = _textBeforeRecording + text;
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
      '[ChatInput] onTextFinished: continuous=${recordingState.isContinuous}, controller="${_controller.text}", baseline="$_textBeforeRecording"',
    );

    if (recordingState.isContinuous) {
      // Continuous mode: submit and clear for next utterance
      _submitText();
    } else {
      // Dictation mode: commit this utterance to the baseline
      // so next utterance appends to it
      setState(() {
        _textBeforeRecording = _controller.text;
      });
      Logger.debug(
        '[ChatInput] onTextFinished: updated baseline to "$_textBeforeRecording"',
      );
    }
  }

  @override
  void onRecordingStarted() {
    // Save current text for appending
    _textBeforeRecording = _controller.text;
  }

  @override
  void onRecordingStopped() {
    // Don't clear _textBeforeRecording here - it will be updated on next start
  }

  @override
  void onError(String error) {
    // Show error to user via snackbar
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide())),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              autofocus: true,
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type a message...',
              ),
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _submitText,
            tooltip: 'Send message',
          ),
          if (ref.watch(voiceCapabilitiesProvider).isAsrAvailable)
            RecorderButton(),
        ],
      ),
    );
  }
}

// Helper class to represent a group of consecutive messages from the same sender
class _MessageGroup {
  final ChatRole sender;
  final List<ChatMessage> messages;
  final DateTime firstMessageTime;

  _MessageGroup({
    required this.sender,
    required this.messages,
    required this.firstMessageTime,
  });

  bool shouldBreakGroup(ChatMessage nextMessage) {
    // Break if sender changes
    if (nextMessage.role != sender) return true;

    // Break if time gap > 5 minutes
    final lastMessageTime = messages.last.timestamp;
    final timeDiff = nextMessage.timestamp.difference(lastMessageTime);
    return timeDiff.inMinutes > 5;
  }
}

// Group messages by sender with time threshold
List<_MessageGroup> _groupMessages(List<ChatMessage> messages) {
  final groups = <_MessageGroup>[];
  _MessageGroup? currentGroup;

  for (final message in messages) {
    if (currentGroup == null || currentGroup.shouldBreakGroup(message)) {
      // Start new group
      currentGroup = _MessageGroup(
        sender: message.role,
        messages: [message],
        firstMessageTime: message.timestamp,
      );
      groups.add(currentGroup);
    } else {
      // Add to existing group
      currentGroup.messages.add(message);
    }
  }

  return groups;
}

class ChatHistory extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool showAssistantPending;
  final RetryState retryState;
  final void Function(String)? onRetry;
  final void Function(String, String)? onSpeak;
  final MessagePlaybackStatus Function(String)? getMessagePlaybackStatus;
  final bool isVoiceAvailable;

  const ChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
    this.retryState = const RetryState(),
    this.onRetry,
    this.onSpeak,
    this.getMessagePlaybackStatus,
    this.isVoiceAvailable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatWidgets = <Widget>[];

    // Show empty state when there are no messages
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

    // Group messages and build widgets with appropriate spacing
    final groups = _groupMessages(messages);
    for (int i = 0; i < groups.length; i++) {
      final group = groups[i];

      // First message in group: show timestamp + role
      chatWidgets.add(
        ChatMessageBubble(
          message: group.messages.first,
          showHeader: true,
          onRetry: onRetry,
          onSpeak: onSpeak,
          getMessagePlaybackStatus: getMessagePlaybackStatus,
        ),
      );

      // Subsequent messages in group: no timestamp
      for (int j = 1; j < group.messages.length; j++) {
        chatWidgets.add(const SizedBox(height: 8)); // Within-group spacing
        chatWidgets.add(
          ChatMessageBubble(
            message: group.messages[j],
            showHeader: false,
            onRetry: onRetry,
            onSpeak: onSpeak,
            getMessagePlaybackStatus: getMessagePlaybackStatus,
          ),
        );
      }

      // Between-group spacing (if not last group)
      if (i < groups.length - 1) {
        chatWidgets.add(const SizedBox(height: 20));
      }
    }

    // Add pending assistant placeholder if waiting for response
    if (showAssistantPending) {
      final pendingState = retryState.lastError != null
          ? PendingAssistantState.delayed
          : PendingAssistantState.waiting;

      final (displayText, textColor) = switch (pendingState) {
        PendingAssistantState.waiting => (
          'Waiting for assistant response...',
          null,
        ),
        PendingAssistantState.delayed => (
          'Delayed assistance response',
          theme.colorScheme.secondary,
        ),
        PendingAssistantState.error => (
          'Error getting assistant response.',
          theme.colorScheme.error,
        ),
      };

      // Add spacing before pending state
      if (chatWidgets.isNotEmpty) {
        chatWidgets.add(const SizedBox(height: 20));
      }

      chatWidgets.add(
        Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                displayText,
                style: theme.textTheme.labelSmall?.copyWith(color: textColor),
              ),
              if (pendingState == PendingAssistantState.delayed &&
                  (retryState.lastError != null ||
                      retryState.lastErrorTechnical != null))
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 20),
                  child: ExpandableErrorDetails(
                    errorMessage: retryState.lastError,
                    technicalDetails: retryState.lastErrorTechnical,
                    color: theme.colorScheme.secondary,
                  ),
                ),
            ],
          ),
        ),
      );

      // Only show grey box for waiting and delayed states, not for final error
      if (pendingState != PendingAssistantState.error) {
        chatWidgets.add(AssistantPendingPlaceholder());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: chatWidgets,
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool showHeader;
  final void Function(String)? onRetry;
  final void Function(String, String)? onSpeak;
  final MessagePlaybackStatus Function(String)? getMessagePlaybackStatus;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.showHeader = true,
    this.onRetry,
    this.onSpeak,
    this.getMessagePlaybackStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hms().format(message.timestamp);
    final isError = message.role == ChatRole.error;
    final isUser = message.role == ChatRole.user;
    final playbackStatus =
        getMessagePlaybackStatus?.call(message.id) ??
        MessagePlaybackStatus.idle;

    return Container(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      padding: isUser
          ? const EdgeInsets.only(left: 10)
          : const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Message header (timestamp + role) - only shown for first message in group
          if (showHeader)
            Padding(
              padding: isUser
                  ? const EdgeInsets.only(left: 10, bottom: 4)
                  : const EdgeInsets.only(left: 10, right: 10, bottom: 4),
              child: Text(
                isError
                    ? 'Error getting assistant response.'
                    : '${message.role.name} • $time',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isError
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          // Message bubble
          Container(
            padding: isUser
                ? const EdgeInsets.fromLTRB(10, 10, 16, 10)
                : const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: isUser
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                      topRight: Radius.zero,
                      bottomRight: Radius.zero,
                    )
                  : const BorderRadius.all(Radius.circular(5)),
              color: switch (message.role) {
                ChatRole.user => theme.colorScheme.onInverseSurface.withValues(
                  alpha: 0.6,
                ),
                ChatRole.assistant => null,
                ChatRole.error => theme.colorScheme.errorContainer.withValues(
                  alpha: 0.3,
                ),
              },
              boxShadow: isUser
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: const Offset(-2, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Message content
                isError
                    ? ErrorMessageWithDetails(message: message, theme: theme)
                    : SelectableRegion(
                        selectionControls: MaterialTextSelectionControls(),
                        child: GptMarkdown(
                          message.text,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                // Action buttons footer
                if ((message.role == ChatRole.assistant && onSpeak != null) ||
                    (isUser && onRetry != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: message.role == ChatRole.assistant
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.end,
                      children: [
                        // TTS button for assistant messages
                        if (message.role == ChatRole.assistant &&
                            onSpeak != null)
                          _buildTtsButton(theme, playbackStatus, message.id),
                        // Retry button for user messages
                        if (isUser && onRetry != null)
                          IconButton.outlined(
                            icon: const Icon(Icons.refresh, size: 18),
                            iconSize: 18,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                            tooltip: 'Retry',
                            onPressed: () => onRetry!(message.text),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTtsButton(
    ThemeData theme,
    MessagePlaybackStatus playbackStatus,
    String messageId,
  ) {
    // Determine icon, tooltip, and color based on playback status
    final IconData ttsIcon;
    final String ttsTooltip;
    final Color? iconColor;

    switch (playbackStatus) {
      case MessagePlaybackStatus.playing:
        ttsIcon = Icons.pause;
        ttsTooltip = 'Pause';
        iconColor = theme.colorScheme.primary;
        break;
      case MessagePlaybackStatus.paused:
        ttsIcon = Icons.play_arrow;
        ttsTooltip = 'Resume';
        iconColor = theme.colorScheme.primary;
        break;
      case MessagePlaybackStatus.generating:
        ttsIcon = Icons.hourglass_empty;
        ttsTooltip = 'Generating audio...';
        iconColor = null;
        break;
      case MessagePlaybackStatus.error:
        ttsIcon = Icons.error;
        ttsTooltip = 'Error';
        iconColor = theme.colorScheme.error;
        break;
      case MessagePlaybackStatus.completed:
      case MessagePlaybackStatus.idle:
        ttsIcon = Icons.volume_up;
        ttsTooltip = 'Read aloud';
        iconColor = null;
        break;
    }

    return playbackStatus == MessagePlaybackStatus.generating
        ? _GeneratingIndicator(tooltip: ttsTooltip)
        : IconButton.outlined(
            icon: Icon(ttsIcon, size: 18, color: iconColor),
            iconSize: 18,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: ttsTooltip,
            onPressed: () => onSpeak!(message.text, messageId),
          );
  }
}

class ExpandableErrorDetails extends StatefulWidget {
  final String? errorMessage;
  final String? technicalDetails;
  final Color color;

  const ExpandableErrorDetails({
    super.key,
    required this.errorMessage,
    required this.technicalDetails,
    required this.color,
  });

  @override
  State<ExpandableErrorDetails> createState() => _ExpandableErrorDetailsState();
}

class _ExpandableErrorDetailsState extends State<ExpandableErrorDetails> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    if (widget.errorMessage == null && widget.technicalDetails == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _showDetails = !_showDetails),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _showDetails
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 14,
                color: widget.color,
              ),
              const SizedBox(width: 4),
              Text(
                'Error details',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: widget.color,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
        if (_showDetails) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: _buildErrorContent(theme),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorContent(ThemeData theme) {
    final List<Widget> children = [];

    if (widget.errorMessage != null) {
      children.add(
        SelectableText(
          'Error: ${widget.errorMessage}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: widget.color,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (widget.technicalDetails != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: 4));
      }

      children.add(
        _buildFormattedTechnicalDetails(widget.technicalDetails!, theme),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildFormattedTechnicalDetails(String details, ThemeData theme) {
    final lines = details.split('\n');
    final List<Widget> lineWidgets = [];

    for (final line in lines) {
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1 && colonIndex < line.length - 1) {
        final label = line.substring(0, colonIndex + 1); // Include the colon
        final value = line.substring(colonIndex + 1).trim();

        lineWidgets.add(
          RichText(
            text: TextSpan(
              children: [
                TextSpan(text: label, style: theme.textTheme.bodySmall),
                TextSpan(
                  text: value,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        lineWidgets.add(SelectableText(line, style: theme.textTheme.bodySmall));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lineWidgets,
    );
  }
}

class _GeneratingIndicator extends StatefulWidget {
  final String tooltip;

  const _GeneratingIndicator({required this.tooltip});

  @override
  State<_GeneratingIndicator> createState() => _GeneratingIndicatorState();
}

class _GeneratingIndicatorState extends State<_GeneratingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
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
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Opacity(
            opacity: _animation.value,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              child: const Icon(Icons.hourglass_empty, size: 18),
            ),
          );
        },
      ),
    );
  }
}

class ErrorMessageWithDetails extends StatefulWidget {
  final ChatMessage message;
  final ThemeData theme;

  const ErrorMessageWithDetails({
    super.key,
    required this.message,
    required this.theme,
  });

  @override
  State<ErrorMessageWithDetails> createState() =>
      _ErrorMessageWithDetailsState();
}

class _ErrorMessageWithDetailsState extends State<ErrorMessageWithDetails> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.message.text,
          style: widget.theme.textTheme.bodyMedium?.copyWith(
            color: widget.theme.colorScheme.error,
            fontStyle: FontStyle.italic,
          ),
        ),
        if (widget.message.technicalDetails != null)
          ExpandableErrorDetails(
            errorMessage: widget.message.text,
            technicalDetails: widget.message.technicalDetails,
            color: widget.theme.colorScheme.primary,
          ),
      ],
    );
  }
}

class AssistantPendingPlaceholder extends StatefulWidget {
  const AssistantPendingPlaceholder({super.key});

  @override
  State<AssistantPendingPlaceholder> createState() =>
      _AssistantPendingPlaceholderState();
}

class _AssistantPendingPlaceholderState
    extends State<AssistantPendingPlaceholder>
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
    var theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _opacityAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: SizedBox(
            width: double.infinity,
            child: Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(left: 10, right: 10, bottom: 20),
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: const BorderRadius.all(Radius.circular(5)),
                color: theme.splashColor,
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
