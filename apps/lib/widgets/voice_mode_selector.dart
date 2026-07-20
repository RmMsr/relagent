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
        _VoiceToggleButton(
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
        _VoiceToggleButton(
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

class _VoiceToggleButton extends StatelessWidget {
  final bool isOn;
  final IconData iconOn;
  final IconData iconOff;
  final String tooltipOn;
  final String tooltipOff;
  final VoidCallback onToggle;

  const _VoiceToggleButton({
    required this.isOn,
    required this.iconOn,
    required this.iconOff,
    required this.tooltipOn,
    required this.tooltipOff,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        isOn ? iconOn : iconOff,
        color: isOn ? colorScheme.primary : colorScheme.onSurfaceVariant,
      ),
      style: isOn
          ? IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer,
              shape: const StadiumBorder(),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            )
          : IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              shape: const StadiumBorder(),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
      tooltip: isOn ? tooltipOn : tooltipOff,
      onPressed: onToggle,
    );
  }
}
