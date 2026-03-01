# Change: Refactor Settings Page to List-Based UI

## Why

The current settings page is 1036 lines with deeply nested form widgets, duplicated patterns, and a paper-form aesthetic that doesn't fit touch-first interfaces. Users on mobile need large tap targets showing current values at a glance, with edit functionality revealed on tap.

## What Changes

### UI/UX Redesign
- **Replace form fields with ListTile-style rows** showing label + current value
- **Tap to edit**: Tapping a row opens a dialog/bottom sheet for editing
- **Grouped sections** with clear headers (Backend, Voice Settings)
- **Large touch targets** suitable for mobile-first usage
- **Keyboard support**: Focus navigation and Enter to confirm on desktop

### Code Refactoring
- **Extract section widgets** into separate files under `lib/widgets/settings/`
- **Create reusable `SettingsTile` widget** for consistent tap-to-edit pattern
- **Extract `AuthenticationSection` widget** reusable for both backends
- **Move health check orchestration** to settings provider or dedicated service
- **Reduce main page to ~200 lines** of composition

### New Widget Structure
```
lib/widgets/settings/
├── settings_tile.dart           # Base tap-to-edit tile
├── backend_selection_section.dart
├── openai_settings_section.dart
├── engine_settings_section.dart
├── voice_settings_section.dart
├── authentication_section.dart  # Reusable for both backends
└── dialogs/
    ├── text_edit_dialog.dart    # Single text field edit
    ├── url_edit_dialog.dart     # URL with validation
    ├── slider_edit_dialog.dart  # For TTS speed
    └── select_dialog.dart       # For dropdowns/enums
```

## Partial Implementation (out of scope)

The voice model selection tiles (Speech Recognition, Text-to-Speech) were added to `settings_page.dart` as inline `ListTile` widgets navigating to `/voice-models`. This is directionally aligned with the list-based pattern but is **not** part of this change — the full refactor (extracted widgets, tap-to-edit dialogs, page size reduction) remains pending.

## Impact

- Affected specs: `user-settings` (UI behavior changes)
- Affected code:
  - `lib/pages/settings_page.dart` - Simplify to ~200 lines
  - `lib/widgets/settings/` - New directory with extracted widgets
  - `lib/providers/settings_provider.dart` - May add health check coordination

## Visual Comparison

**Before (Form-style):**
```
┌─────────────────────────────────┐
│ API Base URL                    │
│ ┌─────────────────────────────┐ │
│ │ http://localhost:1234/v1    │ │
│ └─────────────────────────────┘ │
│ OpenAI-compatible API endpoint  │
│                                 │
│ Model                           │
│ ┌─────────────────────────────┐ │
│ │ gpt-4                       │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

**After (List-style):**
```
┌─────────────────────────────────┐
│ Engine Configuration            │
├─────────────────────────────────┤
│ Engine URL                    > │
│ http://localhost:8000           │
├─────────────────────────────────┤
│ Authentication                > │
│ None                            │
├─────────────────────────────────┤
│ Voice Settings                  │
├─────────────────────────────────┤
│ TTS Speaker                   > │
│ Voice 0                         │
├─────────────────────────────────┤
│ TTS Speed                     > │
│ 1.0x                            │
├─────────────────────────────────┤
│ Background Listening          > │
│ 1 hour                          │
└─────────────────────────────────┘
```
