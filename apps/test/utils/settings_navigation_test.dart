import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/models/settings.dart';
import 'package:relagent/utils/settings_navigation.dart';

void main() {
  final saved = Settings.defaults();

  test('not dirty when draft equals settings and no extra pending', () {
    expect(isSettingsDirty(draft: saved, settings: saved, hasExtraPendingChanges: null), isFalse);
  });

  test('dirty when draft differs from settings', () {
    final draft = saved.copyWith(simpleChatModel: 'changed');
    expect(isSettingsDirty(draft: draft, settings: saved, hasExtraPendingChanges: null), isTrue);
  });

  test('dirty when draft matches settings but extra check reports pending', () {
    expect(
      isSettingsDirty(draft: saved, settings: saved, hasExtraPendingChanges: () => true),
      isTrue,
    );
  });

  test('not dirty when draft matches settings and extra check reports nothing pending', () {
    expect(
      isSettingsDirty(draft: saved, settings: saved, hasExtraPendingChanges: () => false),
      isFalse,
    );
  });
}
