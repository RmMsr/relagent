import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/models/settings.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/chat_provider.dart';
import '/providers/invocation_provider.dart';
import '/providers/settings_provider.dart';

const _defaultInstruction = 'Please explain this';

class InvocationPage extends ConsumerStatefulWidget {
  const InvocationPage({super.key});

  @override
  ConsumerState<InvocationPage> createState() => _InvocationPageState();
}

class _InvocationPageState extends ConsumerState<InvocationPage> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  late final String _receivedText;

  @override
  void initState() {
    super.initState();

    // Read only — mutating state in initState triggers Riverpod's build-phase guard
    _receivedText = ref.read(invocationProvider) ?? '';

    _controller = TextEditingController(text: _defaultInstruction)
      ..selection = const TextSelection(
        baseOffset: 0,
        extentOffset: _defaultInstruction.length,
      );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Clear the holder and raise keyboard after the frame is complete
      ref.read(invocationProvider.notifier).consume();
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final instruction = _controller.text.trim();
    final blockquote = _receivedText
        .split('\n')
        .map((line) => '> $line')
        .join('\n');
    final message =
        instruction.isEmpty ? blockquote : '$instruction\n\n$blockquote';

    final backend = ref.read(settingsProvider).selectedBackend;
    if (backend == ChatBackendType.relagentEngine) {
      await ref.read(agenticChatProvider.notifier).clearChat();
      // ignore: discarded_futures
      ref.read(agenticChatProvider.notifier).sendMessage(message);
    } else {
      ref.read(chatProvider.notifier).clearChat();
      // ignore: discarded_futures
      ref.read(chatProvider.notifier).sendMessage(message);
    }
    if (mounted) context.go('/chat');
  }

  void _cancel() => context.go('/chat');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask Relagent'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _cancel,
        ),
        actions: [
          TextButton(
            onPressed: _send,
            child: const Text('Send'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Add your instruction…',
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (_receivedText.isNotEmpty)
            _TextAttachment(text: _receivedText),
        ],
      ),
    );
  }
}

class _TextAttachment extends StatelessWidget {
  const _TextAttachment({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.format_quote,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected text',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
