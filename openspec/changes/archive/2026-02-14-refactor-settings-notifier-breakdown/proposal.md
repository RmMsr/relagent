# Change: Refactor SettingsNotifier Class Breakdown

## Why

The SettingsNotifier class in `apps/lib/providers/settings_provider.dart` has grown very big and handles multiple responsibilities: settings persistence, history management, and credential storage. This violates the project's guideline of "smaller, focused classes with distinct purpose" and makes the code harder to maintain and test.

Include a review of the Architecture specialist as quality control.

Also there is a problem with the auth verification. It steals the focus from the url input field. The verification should not interferre with input elements.

## What Changes

- **BREAKING**: Split SettingsNotifier into three focused classes:
  - `SettingsPersistenceManager` for SharedPreferences operations
  - `SettingsHistoryManager` for URL/model history tracking
  - `CredentialsManager` for secure credential operations
- Update SettingsNotifier to use composition instead of handling everything directly
- Maintain the same public API to minimize impact on existing code

## Impact

- Affected specs: user-settings
- Affected code: `apps/lib/providers/settings_provider.dart`
- Breaking changes to public API are ok if it improves architecture or
  simplicity
