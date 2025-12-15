import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import '/providers/settings_provider.dart';

class VoiceModeSelector extends ConsumerWidget {
  const VoiceModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Playback control (speaker)
        _ToggleControl(
          label: 'Playback',
          isOn: settings.isAutoPlayback,
          iconOn: Icons.volume_up,
          iconOff: Icons.volume_off,
          tooltipOn: 'Playback on',
          tooltipOff: 'Playback off',
          onToggle: () {
            final newMode = settings.isAutoPlayback
                ? (settings.isContinuousRecording
                      ? VoiceMode.listening
                      : VoiceMode.silent)
                : (settings.isContinuousRecording
                      ? VoiceMode.conversation
                      : VoiceMode.reading);
            ref.read(settingsProvider.notifier).updateVoiceMode(newMode);
          },
        ),
        const SizedBox(width: 8),
        // Listening control (microphone)
        _ToggleControl(
          label: 'Listening',
          isOn: settings.isContinuousRecording,
          iconOn: Icons.mic,
          iconOff: Icons.mic_off,
          tooltipOn: 'Continuous recording on',
          tooltipOff: 'Continuous recording off',
          onToggle: () {
            final newMode = settings.isContinuousRecording
                ? (settings.isAutoPlayback
                      ? VoiceMode.reading
                      : VoiceMode.silent)
                : (settings.isAutoPlayback
                      ? VoiceMode.conversation
                      : VoiceMode.listening);
            ref.read(settingsProvider.notifier).updateVoiceMode(newMode);
          },
        ),
      ],
    );
  }
}

class _ToggleControl extends StatelessWidget {
  final String label;
  final bool isOn;
  final IconData iconOn;
  final IconData iconOff;
  final String tooltipOn;
  final String tooltipOff;
  final VoidCallback onToggle;

  const _ToggleControl({
    required this.label,
    required this.isOn,
    required this.iconOn,
    required this.iconOff,
    required this.tooltipOn,
    required this.tooltipOff,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: iconOff,
            tooltip: tooltipOff,
            isSelected: !isOn,
            isLeft: true,
            onTap: isOn ? onToggle : null,
          ),
          Container(
            width: 1,
            height: 28,
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
          _ToggleButton(
            icon: iconOn,
            tooltip: tooltipOn,
            isSelected: isOn,
            isRight: true,
            onTap: !isOn ? onToggle : null,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final bool isLeft;
  final bool isRight;
  final VoidCallback? onTap;

  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    this.isLeft = false,
    this.isRight = false,
    this.onTap,
  });

  BorderRadius _getBorderRadius() {
    if (isLeft) {
      return const BorderRadius.only(
        topLeft: Radius.circular(7),
        bottomLeft: Radius.circular(7),
      );
    } else if (isRight) {
      return const BorderRadius.only(
        topRight: Radius.circular(7),
        bottomRight: Radius.circular(7),
      );
    }
    return BorderRadius.zero;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = _getBorderRadius();

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          width: 36,
          height: 28,
          decoration: isSelected
              ? BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: borderRadius,
                )
              : null,
          child: Icon(
            icon,
            size: 18,
            color: isSelected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
