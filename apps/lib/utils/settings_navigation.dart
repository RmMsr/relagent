import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '/models/settings.dart';
import '/providers/pending_settings_provider.dart';
import '/providers/settings_provider.dart';

/// Pure comparison used by [hasPendingSettingsChanges] — kept separate so it
/// can be unit-tested without a [WidgetRef].
bool isSettingsDirty({
  required Settings draft,
  required Settings settings,
  required bool Function()? hasExtraPendingChanges,
}) {
  return draft != settings || (hasExtraPendingChanges?.call() ?? false);
}

/// Whether there's anything pending anywhere in the Settings flow: the
/// shared [pendingSettingsProvider] draft, plus whatever screen-local state
/// [hasExtraPendingChanges] reports (e.g. an unsaved credential field).
bool hasPendingSettingsChanges(
  WidgetRef ref, {
  bool Function()? hasExtraPendingChanges,
}) {
  return isSettingsDirty(
    draft: ref.read(pendingSettingsProvider),
    settings: ref.read(settingsProvider),
    hasExtraPendingChanges: hasExtraPendingChanges,
  );
}

/// Commits the staged [pendingSettingsProvider] draft to [settingsProvider]:
/// the engine base URL first (so [SettingsNotifier.updateEngineBaseUrl]'s
/// side effects — resetting engine auth state, clearing session/health
/// state — land before anything else reads the new URL), then the
/// remaining staged free-text fields (chat base URL, chat model, prime
/// message).
///
/// Callable from *any* screen in the Settings flow — it only touches fields
/// that live in the shared draft, never screen-local state like credential
/// text fields (those remain the Settings page's own responsibility).
Future<bool> commitPendingSettings(WidgetRef ref) async {
  final notifier = ref.read(settingsProvider.notifier);
  final settings = ref.read(settingsProvider);
  final pending = ref.read(pendingSettingsProvider);

  if (pending.engineBaseUrl != settings.engineBaseUrl) {
    await notifier.updateEngineBaseUrl(pending.engineBaseUrl);
  }

  return await notifier.updateSettings(
    simpleChatBaseUrl: pending.simpleChatBaseUrl,
    simpleChatModel: pending.simpleChatModel,
    primeMessage: pending.primeMessage,
  );
}

/// Shown by [smartBack] when leaving would discard staged text/credential
/// changes. Returns true if the user chose to leave anyway (discarding).
Future<bool> _confirmDiscard(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unsaved changes'),
      content: const Text('Leave without saving?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Leave Anyway'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Pops one level back. If anything is pending (staged draft text, or
/// whatever [hasExtraPendingChanges] reports, e.g. unsaved credential
/// fields), confirms first — leaving discards the pending draft.
Future<void> smartBack(
  BuildContext context,
  WidgetRef ref, {
  bool Function()? hasExtraPendingChanges,
}) async {
  if (!hasPendingSettingsChanges(
    ref,
    hasExtraPendingChanges: hasExtraPendingChanges,
  )) {
    if (context.mounted) context.pop();
    return;
  }
  final leave = await _confirmDiscard(context);
  if (!leave) return;
  ref.read(pendingSettingsProvider.notifier).discardPending();
  if (context.mounted) context.pop();
}

/// Shown when Apply is pressed somewhere other than Settings while
/// connection settings haven't been verified since they last changed (see
/// `credentialsPassProvider`). Returns true if the user chose to close
/// anyway (accepting the risk), false if they chose to go back to Settings
/// and resolve it there.
Future<bool> showUnverifiedCredentialsDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Unverified Connection'),
      content: const Text(
        "Your connection settings have changed and haven't been tested. "
        'Go to Settings to verify them, or close anyway?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Review Settings'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Close Anyway'),
        ),
      ],
    ),
  );
  return result ?? false;
}
