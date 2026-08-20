import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '/utils/logger.dart';

/// Copies [text] (the raw, unrendered message source) to the system
/// clipboard. Always copies the stored text directly rather than anything
/// derived from how the message happens to be split into widgets for
/// on-screen rendering, so paragraph breaks are preserved verbatim.
Future<void> copyMessageText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Copied to clipboard'),
      duration: Duration(seconds: 2),
    ),
  );
}

/// Builds an `onLinkTap` callback for [GptMarkdown] that confirms the
/// destination with the user before leaving the app. Link text can come
/// from LLM-generated assistant messages and may not match the actual URL,
/// so every link (regardless of message role) is confirmed the same way.
void Function(String url, String title) linkTapHandler(BuildContext context) {
  return (String url, String title) => _confirmAndLaunch(context, url);
}

Future<void> _confirmAndLaunch(BuildContext context, String url) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Open link?'),
      content: Text(url),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Open'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;
  if (!context.mounted) return;

  final uri = Uri.tryParse(url);
  var launched = false;
  if (uri != null && await canLaunchUrl(uri)) {
    launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  if (!launched) {
    Logger.warning('Could not open link: $url');
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Couldn't open link")));
  }
}

/// A compact, borderless icon button for copying a message's raw text,
/// styled to match the app's other unbordered action buttons (e.g. the
/// stats toggle in the agentic message actions row).
class MessageCopyButton extends StatelessWidget {
  final String text;

  const MessageCopyButton({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      icon: const Icon(Icons.copy, size: 18),
      tooltip: 'Copy',
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        foregroundColor: theme.colorScheme.onSurfaceVariant,
      ),
      onPressed: () => copyMessageText(context, text),
    );
  }
}
