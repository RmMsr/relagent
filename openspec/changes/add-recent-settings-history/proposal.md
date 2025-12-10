# Change: Add Recent Settings History

## Why

Users frequently switch between different AI servers and models during testing and normal use. Currently, they must manually re-enter the base URL and model name each time they want to switch servers. This creates friction and slows down the workflow, especially when experimenting with different models or switching between local and remote servers.

## What Changes

- Add persistent history of recently used server URL and model combinations
- Display recent entries as autocomplete suggestions in the settings page URL and model fields
- Automatically track the 5 most recently used unique URL/model pairs
- Store history separately from current settings in SharedPreferences

## Impact

- Affected specs: user-settings (new capability)
- Affected code:
  - `apps/lib/models/settings.dart` - Add history model
  - `apps/lib/providers/settings_provider.dart` - Add history tracking logic
  - `apps/lib/pages/settings_page.dart` - Add autocomplete UI for URL and model fields
