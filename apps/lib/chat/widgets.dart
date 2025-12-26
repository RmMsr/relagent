import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';
import 'package:relagent/chat/models.dart';

import '/models/app_info.dart';
import '/providers/chat_provider.dart';
import '/providers/tts_provider.dart';
import '/speech_recognition/widgets.dart';
import '/widgets/version_info_widget.dart';

class ChatInput extends StatefulWidget {
  final ValueChanged<String> onSubmitted;

  const ChatInput({super.key, required this.onSubmitted});

  @override
  State<StatefulWidget> createState() {
    return ChatInputState();
  }
}

class ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();

  void _setText(String text) {
    setState(() {
      _controller.text = text;
    });
  }

  void _submitText() {
    final text = _controller.text;
    if (text == '') {
      return;
    }

    widget.onSubmitted(_controller.text);
    setState(() {
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide())),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: _inputNewlineOrSubmit,
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Type a message...',
                ),
                minLines: 1,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),
          RecorderButton(
            onTextRecognized: _setText,
            onTextFinished: _submitText,
          ),
        ],
      ),
    );
  }

  // Enable submitting with Enter while allowing newline with Shift+Enter
  KeyEventResult _inputNewlineOrSubmit(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _submitText();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

class ChatHistory extends StatelessWidget {
  final List<ChatMessage> messages;
  final bool showAssistantPending;
  final RetryState retryState;
  final void Function(String)? onRetry;
  final void Function(String, String)? onSpeak;
  final MessagePlaybackStatus Function(String)? getMessagePlaybackStatus;

  const ChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
    this.retryState = const RetryState(),
    this.onRetry,
    this.onSpeak,
    this.getMessagePlaybackStatus,
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
                'Start a conversation by typing a message or using voice input',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    for (final message in messages) {
      chatWidgets.add(
        ChatMessageBubble(
          message: message,
          onRetry: onRetry,
          onSpeak: onSpeak,
          getMessagePlaybackStatus: getMessagePlaybackStatus,
        ),
      );
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
      spacing: 10,
      children: chatWidgets,
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final void Function(String)? onRetry;
  final void Function(String, String)? onSpeak;
  final MessagePlaybackStatus Function(String)? getMessagePlaybackStatus;

  const ChatMessageBubble({
    super.key,
    required this.message,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Message header
        Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            isError
                ? 'Error getting assistant response.'
                : '${message.role.name} @ $time',
            style: theme.textTheme.labelSmall?.copyWith(
              color: isError ? theme.colorScheme.error : null,
            ),
          ),
        ),
        // Message bubble with action buttons
        SizedBox(
          width: double.infinity,
          child: SizedBox(
            width: double.infinity,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // TTS button for assistant messages (on the left)
                if (message.role == ChatRole.assistant && onSpeak != null)
                  _buildTtsButton(theme, playbackStatus, message.id),
                // Message content
                Expanded(child: _buildMessageContent(theme, isError)),
                // Retry button for user messages (on the right)
                if (isUser && onRetry != null)
                  Container(
                    margin: const EdgeInsets.only(right: 10, top: 5),
                    child: IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      iconSize: 20,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      tooltip: 'Retry',
                      onPressed: () => onRetry!(message.text),
                    ),
                  ),
              ],
            ),
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

    return Container(
      margin: const EdgeInsets.only(left: 10, top: 5),
      child: playbackStatus == MessagePlaybackStatus.generating
          ? _GeneratingIndicator(tooltip: ttsTooltip)
          : IconButton(
              icon: Icon(ttsIcon, size: 20, color: iconColor),
              iconSize: 20,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              tooltip: ttsTooltip,
              onPressed: () => onSpeak!(message.text, messageId),
            ),
    );
  }

  Widget _buildMessageContent(ThemeData theme, bool isError) {
    return Container(
      alignment: message.role == ChatRole.user
          ? Alignment.centerRight
          : Alignment.centerLeft,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(left: 10, right: 10, bottom: 20),
      decoration: BoxDecoration(
        shape: BoxShape.rectangle,
        borderRadius: const BorderRadius.all(Radius.circular(5)),
        color: switch (message.role) {
          ChatRole.user => theme.colorScheme.onInverseSurface.withValues(
            alpha: 0.6,
          ),
          ChatRole.assistant => null,
          ChatRole.error => theme.colorScheme.errorContainer.withValues(
            alpha: 0.3,
          ),
        },
      ),
      child: isError
          ? ErrorMessageWithDetails(message: message, theme: theme)
          : SelectableRegion(
              selectionControls: MaterialTextSelectionControls(),
              child: GptMarkdown(
                message.text,
                style: theme.textTheme.bodyMedium,
              ),
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
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.hourglass_empty, size: 20),
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
