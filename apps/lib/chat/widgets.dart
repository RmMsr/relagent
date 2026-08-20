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
import '/tts/text_chunker.dart';
import '/utils/logger.dart';
import '/theme/app_colors.dart';
import '/widgets/message_markdown_actions.dart';
import '/widgets/tts_chunk_controls.dart';
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
  // The field text last written by ASR. Controller notifications carrying this
  // value are ASR echoes (incl. async IME echoes) and must NOT move the
  // baseline; only genuine user edits do. Timing guards alone are not enough
  // because a focused field re-notifies after the synchronous write.
  String _lastAsrText = '';
  RecordingNotifier? _recordingNotifier;

  void requestFocus() {
    _focusNode.requestFocus();
  }

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
      _lastAsrText = '';
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
    if (_isUpdatingFromASR || _controller.text == _lastAsrText) return;
    _textBeforeRecording = _controller.text;
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
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type a message...',
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
            onPressed: _submitText,
            tooltip: 'Send message',
          ),
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
  final MessageTtsState Function(String)? getMessageTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;
  final bool isVoiceAvailable;

  const ChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
    this.retryState = const RetryState(),
    this.onRetry,
    this.onSpeak,
    this.getMessageTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
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
          getMessageTtsState: getMessageTtsState,
          onSkipPrevious: onSkipPrevious,
          onSkipNext: onSkipNext,
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
            getMessageTtsState: getMessageTtsState,
            onSkipPrevious: onSkipPrevious,
            onSkipNext: onSkipNext,
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
  final MessageTtsState Function(String)? getMessageTtsState;
  final void Function(String messageId)? onSkipPrevious;
  final void Function(String messageId)? onSkipNext;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.showHeader = true,
    this.onRetry,
    this.onSpeak,
    this.getMessageTtsState,
    this.onSkipPrevious,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hms().format(message.timestamp.toLocal());
    final isError = message.role == ChatRole.error;
    final isUser = message.role == ChatRole.user;
    final ttsMessageState =
        getMessageTtsState?.call(message.id) ?? const MessageTtsState();
    final playbackStatus = ttsMessageState.status;

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
          switch (message.role) {
            ChatRole.user => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 1.5,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableRegion(
                      selectionControls: MaterialTextSelectionControls(),
                      child: GptMarkdown(
                        message.text,
                        // Flutter's Table RenderObject caches its row
                        // decoration painters and doesn't always repaint
                        // them on a live theme/brightness change, leaving
                        // markdown table headers stuck on stale colors.
                        // Keying on brightness forces a full remount when
                        // it changes, avoiding that stale-paint cache.
                        key: ValueKey(theme.brightness),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                        onLinkTap: linkTapHandler(context),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (onRetry != null)
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
                  ),
                ],
              ),
            ),
            ),
            ChatRole.assistant => Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableRegion(
                    selectionControls: MaterialTextSelectionControls(),
                    child: _buildMessageBody(context, theme, ttsMessageState),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onSpeak != null) ...[
                          _buildTtsButton(theme, playbackStatus, message.id),
                          const SizedBox(width: 8),
                        ],
                        MessageCopyButton(text: message.text),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ChatRole.error => Container(
              padding: const EdgeInsets.all(12),
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
              child: ErrorMessageWithDetails(message: message, theme: theme),
            ),
          },
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
      return GptMarkdown(
        message.text,
        // See the brightness key note in the ChatRole.user branch above —
        // works around a Flutter Table repaint-cache bug.
        key: ValueKey(theme.brightness),
        style: theme.textTheme.bodyMedium,
        onLinkTap: linkTapHandler(context),
      );
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
            child: GptMarkdown(
              paragraphs[i],
              // See the brightness key note above. Combined with the
              // paragraph index so siblings in this loop don't collide.
              key: ValueKey((i, theme.brightness)),
              style: theme.textTheme.bodyMedium,
              onLinkTap: linkTapHandler(context),
            ),
          ),
      ],
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

    final singleButton = playbackStatus == MessagePlaybackStatus.generating
        ? _GeneratingIndicator(tooltip: ttsTooltip)
        : IconButton.outlined(
            icon: Icon(ttsIcon, size: 18, color: iconColor),
            iconSize: 18,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: ttsTooltip,
            onPressed: () => onSpeak!(message.text, messageId),
          );

    final hasPlaybackFocus =
        playbackStatus == MessagePlaybackStatus.playing ||
        playbackStatus == MessagePlaybackStatus.paused;

    return AnimatedTtsControls(
      showChunkControls:
          hasPlaybackFocus && onSkipPrevious != null && onSkipNext != null,
      singleButton: singleButton,
      chunkControls: TtsChunkControls(
        outlined: true,
        isPlaying: playbackStatus == MessagePlaybackStatus.playing,
        onPlayPause: () => onSpeak!(message.text, messageId),
        onSkipPrevious: () => onSkipPrevious?.call(messageId),
        onSkipNext: () => onSkipNext?.call(messageId),
      ),
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
