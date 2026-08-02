import 'package:flutter/material.dart';

/// Full-width Apply button shown at the bottom of every screen in the
/// Settings flow. Always enabled — pressing it applies whatever is
/// currently staged (a no-op if nothing is) and leaves the flow.
class SettingsApplyBar extends StatelessWidget {
  const SettingsApplyBar({super.key, required this.onApply});

  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainer,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: ButtonStyle(
                side: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.focused)) {
                    return BorderSide(color: colorScheme.onPrimary, width: 2);
                  }
                  return null;
                }),
              ),
              onPressed: onApply,
              child: const Text('Apply'),
            ),
          ),
        ),
      ),
    );
  }
}
