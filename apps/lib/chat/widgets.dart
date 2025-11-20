import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:intl/intl.dart';
import 'package:relagent/chat/models.dart';

import '/speech_recognition/widgets.dart';

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
      padding: EdgeInsets.symmetric(vertical: 0, horizontal: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide())),
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
  final Function(String)? onRetry;

  const ChatHistory({
    super.key,
    required this.messages,
    this.showAssistantPending = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    var chatWidgets = <Widget>[];

    for (var m in messages) {
      final time = DateFormat.Hms().format(m.timestamp);
      final isError = m.role == ChatRole.error;
      final isUser = m.role == ChatRole.user;

      chatWidgets.add(
        Container(
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '- $time: ${m.role.name} -',
            style: theme.textTheme.labelSmall,
          ),
        ),
      );

      // Message bubble with optional retry button for user messages
      chatWidgets.add(
        SizedBox(
          width: double.infinity,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.all(10),
                  margin: EdgeInsets.only(left: 10, right: 10, bottom: 20),
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    borderRadius: BorderRadius.all(Radius.circular(5)),
                    color: isError
                        ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
                        : theme.splashColor,
                  ),
                  child: isError
                      ? Text(
                          m.text,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : GptMarkdown(m.text, style: theme.textTheme.bodyMedium),
                ),
              ),
              // Add retry button for user messages
              if (isUser && onRetry != null)
                Container(
                  margin: EdgeInsets.only(right: 10, top: 5),
                  child: IconButton(
                    icon: Icon(Icons.refresh, size: 20),
                    iconSize: 20,
                    padding: EdgeInsets.all(4),
                    constraints: BoxConstraints(),
                    tooltip: 'Retry',
                    onPressed: () => onRetry!(m.text),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Add pending assistant placeholder if waiting for response
    if (showAssistantPending) {
      chatWidgets.add(
        Container(
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '- assistant -',
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

    _opacityAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
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
              padding: EdgeInsets.all(10),
              margin: EdgeInsets.only(left: 10, right: 10, bottom: 20),
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.all(Radius.circular(5)),
                color: theme.splashColor,
              ),
              child: Text(
                '...',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        );
      },
    );
  }
}
