import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/providers/mic_preference_provider.dart';
import '/providers/model_download_provider.dart';
import '/providers/recording_provider.dart';
import '/providers/settings_provider.dart';
import '/providers/voice_service_provider.dart';
import '/voice/model_resolver.dart';
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
      child: Icon(
        filled ? Icons.mic : Icons.mic_none,
        color: color,
        size: size,
      ),
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

/// Lists "Automatic" plus the enumerated input devices (when there's more
/// than the trivial "Automatic" choice), and — independently — the ASR
/// models enabled for quick-pick via `apps/lib/widgets/model_management_section.dart`
/// (when there are at least two to pick between). Picking a model sets a
/// session-only override (`activeAsrModelOverrideProvider`) — it does not
/// persist and reverts to the device default on the next app launch (design
/// D17). Each section is shown only when it actually offers a choice.
class MicPickerSheet extends ConsumerWidget {
  const MicPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preference = ref.watch(micPreferenceProvider);
    final inputSelectionAvailable = ref
        .watch(voiceCapabilitiesProvider)
        .isInputSelectionAvailable;
    final devices = inputSelectionAvailable
        ? (ref.watch(micDevicesProvider).value ?? const <MicDevice>[])
        : const <MicDevice>[];
    final settings = ref.watch(settingsProvider);
    final downloadState = ref.watch(modelDownloadProvider);
    final quickPickEntries = quickPickAsrEntries(settings, downloadState);
    final activeOverride = ref.watch(activeAsrModelOverrideProvider);

    Future<void> selectDevice(MicPreference newPreference) async {
      await ref.read(micPreferenceProvider.notifier).set(newPreference);
      if (context.mounted) Navigator.of(context).pop();
    }

    void selectAsrModel(String modelId) {
      final notifier = ref.read(activeAsrModelOverrideProvider.notifier);
      notifier.set(activeOverride == modelId ? null : modelId);
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          if (devices.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Microphone', style: theme.textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.mic_external_on),
              title: const Text('Automatic'),
              subtitle: const Text('Prefer Bluetooth headset when connected'),
              trailing: preference.isAuto ? const Icon(Icons.check) : null,
              onTap: () => selectDevice(const MicPreference.auto()),
            ),
            for (final device in devices)
              ListTile(
                leading: MicSymbol(category: device.category, size: 24),
                title: Text(
                  device.name.isEmpty ? device.category.name : device.name,
                ),
                trailing: !preference.isAuto && preference.matches(device)
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => selectDevice(
                  MicPreference.pinned(
                    category: device.category,
                    address: device.address,
                    name: device.name,
                  ),
                ),
              ),
          ],
          if (quickPickEntries.length >= 2) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Recognition Model',
                style: theme.textTheme.titleMedium,
              ),
            ),
            for (final entry in quickPickEntries)
              ListTile(
                leading: const Icon(Icons.translate),
                title: Text(entry.displayName),
                subtitle: Text(languageCoverageLabel(entry.languages)),
                trailing: activeOverride == entry.id
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => selectAsrModel(entry.id),
              ),
          ],
        ],
      ),
    );
  }
}
