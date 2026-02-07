# Design: Settings Page Refactoring

## Context

The settings page needs to support touch-first mobile devices while remaining usable on desktop with keyboard navigation. The current form-based approach requires too much scrolling and doesn't show current values at a glance.

## Goals / Non-Goals

**Goals:**
- Touch-friendly list UI with large tap targets (48dp+)
- Show current values inline, edit on tap
- Reduce settings_page.dart from 1036 to ~200 lines
- Reusable widget patterns for future settings
- Keyboard navigable on desktop

**Non-Goals:**
- Complete redesign of settings data model
- Real-time validation (validate on save is sufficient)
- Undo/redo functionality

## Decisions

### 1. List-Based UI Pattern
**Decision:** Use ListTile-style rows with subtitle showing current value, trailing chevron indicating tap-to-edit.

**Why:** 
- Matches platform conventions (iOS Settings, Android Settings)
- Shows all values at a glance without scrolling into each field
- Large touch targets by default
- Familiar pattern reduces learning curve

### 2. Edit via Bottom Sheet (Mobile) / Dialog (Desktop)
**Decision:** Use `showModalBottomSheet` on mobile, `showDialog` on desktop for editing.

**Why:**
- Bottom sheets are thumb-reachable on mobile
- Dialogs are standard on desktop
- Both can share the same content widget

**Implementation:**
```dart
Future<T?> showEditModal<T>({
  required BuildContext context,
  required Widget child,
}) {
  final isDesktop = MediaQuery.of(context).size.width > 600;
  if (isDesktop) {
    return showDialog<T>(context: context, builder: (_) => Dialog(child: child));
  }
  return showModalBottomSheet<T>(context: context, builder: (_) => child);
}
```

### 3. Direct Provider Updates (No Local Form State)
**Decision:** Each edit dialog saves directly to provider on confirm. No "Save" button at page level.

**Why:**
- Simpler mental model - what you change is what you get
- No risk of losing unsaved changes
- Eliminates need for 9 TextEditingControllers in page state
- Health check can trigger immediately on relevant changes

**Trade-off:** Can't cancel all changes at once. Mitigated by Reset to Defaults.

### 4. Reusable SettingsTile Widget
**Decision:** Create a single `SettingsTile` widget that handles the common pattern.

```dart
class SettingsTile extends StatelessWidget {
  final String title;
  final String? subtitle;      // Current value display
  final IconData? leadingIcon;
  final VoidCallback? onTap;
  final Widget? trailing;      // Defaults to chevron
  final bool enabled;
  
  // For inline toggles (no dialog needed)
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
}
```

### 5. Section Organization

```
Backend Selection (SegmentedButton - always visible)
│
├── [If Engine selected]
│   Engine Configuration
│   ├── Engine URL
│   └── Authentication (expandable)
│
├── [If OpenAI selected]  
│   Chat API Configuration
│   ├── API Base URL
│   ├── Model
│   ├── Prime Message
│   └── Authentication (expandable)
│
Voice Settings (always visible)
├── TTS Speaker ID
├── TTS Speed
└── Background Listening Duration
│
Actions
├── Reset to Defaults
└── [Connection status indicator]
```

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| More taps to edit a value | Offset by better scanability and fewer errors |
| Bottom sheets feel different per platform | Use adaptive approach based on screen width |
| No bulk cancel | Reset to Defaults provides escape hatch |

## File Structure

```
lib/
├── pages/
│   └── settings_page.dart          # ~200 lines, composition only
└── widgets/
    └── settings/
        ├── settings_tile.dart       # Base tile widget
        ├── settings_section.dart    # Section header + children
        ├── backend_selection.dart   # SegmentedButton section
        ├── openai_section.dart      # OpenAI-specific settings
        ├── engine_section.dart      # Engine-specific settings
        ├── voice_section.dart       # TTS + background listening
        ├── auth_section.dart        # Reusable authentication UI
        └── dialogs/
            ├── edit_modal.dart      # Adaptive dialog/bottom sheet
            ├── text_edit.dart       # Single text field
            ├── url_edit.dart        # URL with validation
            ├── multiline_edit.dart  # For prime message
            ├── slider_edit.dart     # Numeric with slider
            └── select_edit.dart     # Dropdown/enum selection
```

## Resolved Questions

1. **Password reveal behavior:** Show reveal toggle only for newly typed text, not for loaded passwords. When opening the password edit modal, the field starts empty (placeholder shows "unchanged" or dots). User types new password and can reveal to verify before saving. This helps catch typos flagged by health check without exposing stored credentials.

2. **Health check timing:** Run health check automatically after URL or auth field changes + focus loss (blur). Use 500ms debounce to avoid rapid-fire checks while typing. Show inline status indicator (success/error icon) next to the URL tile.
