import 'package:flutter_riverpod/flutter_riverpod.dart';

import '/models/settings.dart';
import 'settings_provider.dart';

/// The full [Settings] draft as currently staged across the Settings flow
/// (main Settings page + Voice Models screen), before the user presses Save.
class PendingSettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() => ref.watch(settingsProvider);

  /// Applies a partial change to the draft, e.g.
  /// `updateDraft((s) => s.copyWith(simpleChatModel: newValue))`.
  void updateDraft(Settings Function(Settings current) update) {
    state = update(state);
  }

  /// Discards any pending edits, re-seeding from the current
  /// [settingsProvider] value by re-running [build].
  void discardPending() => ref.invalidateSelf();
}

final pendingSettingsProvider =
    NotifierProvider.autoDispose<PendingSettingsNotifier, Settings>(
      PendingSettingsNotifier.new,
    );
