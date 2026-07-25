import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/providers/mic_preference_provider.dart';
import '/voice/voice_service.dart';

/// Overlays a small badge identifying the input device category (Bluetooth,
/// wired, USB) on [child]. Built-in and unknown categories render [child]
/// unchanged, so callers need no conditional of their own.
class MicDeviceBadge extends StatelessWidget {
  final MicDeviceCategory? category;
  final Color? color;
  final double size;
  final Widget child;

  const MicDeviceBadge({
    super.key,
    required this.category,
    required this.size,
    required this.child,
    this.color,
  });

  static IconData? badgeFor(MicDeviceCategory? category) => switch (category) {
    MicDeviceCategory.bluetooth => Icons.bluetooth,
    MicDeviceCategory.wired => Icons.headset_mic,
    MicDeviceCategory.usb => Icons.usb,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final badge = badgeFor(category);
    if (badge == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -size * 0.1,
          bottom: -size * 0.05,
          child: Icon(badge, color: color, size: size * 0.5),
        ),
      ],
    );
  }
}

/// Microphone icon carrying the active input device's badge.
class MicSymbol extends StatelessWidget {
  final MicDeviceCategory? category;
  final bool filled;
  final Color? color;
  final double size;

  const MicSymbol({
    super.key,
    this.category,
    this.filled = false,
    this.color,
    this.size = 32,
  });

  static IconData? badgeFor(MicDeviceCategory? category) =>
      MicDeviceBadge.badgeFor(category);

  @override
  Widget build(BuildContext context) {
    return MicDeviceBadge(
      category: category,
      color: color,
      size: size,
      child: Icon(filled ? Icons.mic : Icons.mic_none, color: color, size: size),
    );
  }
}

/// Opens the microphone picker (long-press on the recording button).
void showMicPickerSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => const MicPickerSheet(),
  );
}

/// Lists "Automatic" plus the enumerated input devices; selecting an entry
/// pins it as the microphone preference.
class MicPickerSheet extends ConsumerWidget {
  const MicPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preference = ref.watch(micPreferenceProvider);
    final devices = ref.watch(micDevicesProvider).value ?? const <MicDevice>[];

    Future<void> select(MicPreference newPreference) async {
      await ref.read(micPreferenceProvider.notifier).set(newPreference);
      if (context.mounted) Navigator.of(context).pop();
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Microphone', style: theme.textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.mic_external_on),
            title: const Text('Automatic'),
            subtitle: const Text('Prefer Bluetooth headset when connected'),
            trailing: preference.isAuto ? const Icon(Icons.check) : null,
            onTap: () => select(const MicPreference.auto()),
          ),
          for (final device in devices)
            ListTile(
              leading: MicSymbol(category: device.category, size: 24),
              title: Text(device.name.isEmpty ? device.category.name : device.name),
              trailing: !preference.isAuto && preference.matches(device)
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => select(
                MicPreference.pinned(
                  category: device.category,
                  address: device.address,
                  name: device.name,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
