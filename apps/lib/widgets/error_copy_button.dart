import 'package:flutter/material.dart';

import 'message_markdown_actions.dart' show copyMessageText;

/// A small, unobtrusive copy-to-clipboard button meant to sit in the
/// bottom-right corner of an error message box (connection failures, health
/// check panels, etc). Copies [text] verbatim as plain text.
class ErrorCopyButton extends StatelessWidget {
  final String text;

  const ErrorCopyButton({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy, size: 14),
      tooltip: 'Copy error',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(24, 24),
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () => copyMessageText(context, text),
    );
  }
}
