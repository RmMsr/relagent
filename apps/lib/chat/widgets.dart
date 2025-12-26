import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';
import 'package:relagent/chat/models.dart';

import '/models/app_info.dart';
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
  final void Function(String)? onRetry;
  final void Function(String, String)? onSpeak;
  final MessagePlaybackStatus Function(String)? getMessagePlaybackStatus;

  const ChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
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
      chatWidgets.add(
        Container(
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            ChatRole.assistant.name,
            style: theme.textTheme.labelSmall,
          ),
        ),
      );
      chatWidgets.add(const AssistantPendingPlaceholder());
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
            '${message.role.name} @ $time',
            style: theme.textTheme.labelSmall,
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
          ? Text(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontStyle: FontStyle.italic,
              ),
            )
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
              child: Text('...', style: theme.textTheme.bodyMedium),
            ),
          ),
        );
      },
    );
  }
}
