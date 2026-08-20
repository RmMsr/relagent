import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agentic_client/agentic_client.dart';
import '/agentic/sensitivity_color.dart';
import '/providers/agentic_chat_provider.dart';
import '/providers/displayed_session_provider.dart';
import '/providers/new_chat_draft_provider.dart';

// -- Sensitivity Indicator & Picker --

class SensitivityIndicator extends ConsumerWidget {
  /// When true, renders as an AppBar action button (no border/background).
  /// When false (default), renders as a standalone chip overlay.
  final bool inAppBar;

  const SensitivityIndicator({super.key, this.inAppBar = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayedSessionId = ref.watch(displayedSessionProvider);
    final level = displayedSessionId == null
        ? ref.watch(newChatDraftProvider.select((s) => s.sensitivityLevel))
        : ref.watch(
            agenticChatProvider(
              displayedSessionId,
            ).select((s) => s.sensitivityLevel),
          );
    final isNarrow = MediaQuery.of(context).size.width < 500;

    if (inAppBar) {
      return IconButton(
        tooltip: 'Sensitivity level: ${level.label}',
        onPressed: () =>
            _showSensitivityPicker(context, ref, displayedSessionId, level),
        style: isNarrow
            ? IconButton.styleFrom(
                backgroundColor: level.color,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )
            : null,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 16,
              color: isNarrow ? Colors.white : level.color,
            ),
            const SizedBox(width: 4),
            Text(
              isNarrow ? level.shortLabel : level.label,
              style: TextStyle(
                fontSize: isNarrow ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: isNarrow ? Colors.white : level.color,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () =>
          _showSensitivityPicker(context, ref, displayedSessionId, level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isNarrow ? level.color : level.color.withAlpha(30),
          borderRadius: BorderRadius.circular(16),
          border: isNarrow ? null : Border.all(color: level.color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shield_outlined,
              size: 14,
              color: isNarrow ? Colors.white : level.color,
            ),
            const SizedBox(width: 4),
            Text(
              isNarrow ? level.shortLabel : level.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isNarrow ? Colors.white : level.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSensitivityPicker(
    BuildContext context,
    WidgetRef ref,
    String? displayedSessionId,
    SensitivityLevel currentLevel,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SensitivityPicker(
        currentLevel: currentLevel,
        onSelected: (level) {
          Navigator.pop(context);
          if (level != currentLevel) {
            if (displayedSessionId == null) {
              ref.read(newChatDraftProvider.notifier).changeSensitivity(level);
            } else {
              ref
                  .read(agenticChatProvider(displayedSessionId).notifier)
                  .changeSensitivity(level);
            }
          }
        },
      ),
    );
  }
}

class SensitivityPicker extends StatelessWidget {
  final SensitivityLevel currentLevel;
  final ValueChanged<SensitivityLevel> onSelected;

  const SensitivityPicker({
    super.key,
    required this.currentLevel,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Sensitivity Level',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            for (final level in SensitivityLevel.values)
              ListTile(
                leading: Icon(Icons.circle, color: level.color, size: 16),
                title: Text(level.label),
                subtitle: Text(
                  level.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: level == currentLevel
                    ? Icon(Icons.check, color: theme.colorScheme.primary)
                    : null,
                onTap: () => onSelected(level),
              ),
          ],
        ),
      ),
    );
  }
}
