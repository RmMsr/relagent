# App Styling Design

**Date:** 2026-05-08
**Scope:** Uniform visual theme for the Flutter app (apps/)

## Goals

- Clear and functional; no eye-catching decoration
- Information types distinguishable by position, shape, or color — no label-reading required
- Comfortable reading appearance; high contrast is secondary
- Glance-legible for distracted use (walking, driving)
- Light mode with dark mode support at low implementation cost

## Color Palette

```dart
// Primary
primaryIndigo     = Color(0xFF283593)  // send button, user bubble text, toggle-on icons
indigoMid         = Color(0xFF5C6BC0)  // approval border, Allow button fill
indigoTint        = Color(0xFFE8EAF6)  // toggle-on chip bg, approval anchor bg
indigoBorder      = Color(0xFFC5CAE9)  // user bubble outline, Deny button border

// Surfaces
backgroundGrey    = Color(0xFFF8F9FA)  // app background, assistant messages
surfaceWhite      = Colors.white       // cards where needed
divider           = Color(0xFFE8EAED)  // app bar bottom border, input top border

// Text
primaryText       = Color(0xFF1A1A1A)
secondaryText     = Color(0xFF5F6368)
toggleOffMuted    = Color(0xFFB0BEC5)  // voice toggle icon when OFF

// Semantic anchor colors
approvalBg        = Color(0xFFE8EAF6)  // same as indigoTint
approvalBorder    = Color(0xFF5C6BC0)

errorBg           = Color(0xFFFFEBEE)
errorBorder       = Color(0xFFEF9A9A)
errorText         = Color(0xFFB71C1C)

noteBg            = Color(0xFFE8F5E9)
noteBorder        = Color(0xFFA5D6A7)
noteText          = Color(0xFF1B5E20)
```

Dark mode variants are provided via `ColorScheme.fromSeed(brightness: Brightness.dark)` for
the base palette. The semantic anchor colors (approval/error/note) need explicit dark-mode
overrides in a `RelagentSemanticColors` extension (see Component Spec below).

## Typography

Use M3 defaults from `ColorScheme.fromSeed`. No custom font family. Text sizes follow
existing usage: `bodyLarge` (16px), `bodyMedium` (14px), `labelMedium` for secondary labels.

## Component Spec

### ThemeData (`main.dart`)

```dart
ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF283593),
    brightness: brightness, // Brightness.light or Brightness.dark
  ),
)
```

A `RelagentColors` class exposes the semantic constants and their dark-mode counterparts,
accessed via an extension on `BuildContext`.

### Assistant messages

- No background, no border — bare text rendered directly on `backgroundGrey`
- Alignment: left (`crossAxisAlignment.start`)
- Text style: `bodyMedium`, `primaryText`
- The assistant is the voice of the app; its messages are visually native to the surface

### User messages

- Right-aligned (`crossAxisAlignment.end`), max width 80% of chat width
- Outline bubble only: `1.5px` border in `indigoBorder`, no fill
- Border radius: `14 14 4 14` (sharp bottom-right corner toward the input)
- Text color: `primaryIndigo`, same size as assistant
- Intentionally low visual weight — user already knows what they typed

### Anchor cards (non-chat items)

Shape rule: left border only, right corners rounded (`border-radius: 0 10px 10px 0`).
No other border. Left border width: `4px`.

| Type     | Background     | Left border    | Text color     |
|----------|---------------|----------------|----------------|
| Approval | `approvalBg`  | `approvalBorder` | `primaryText` + `primaryIndigo` title |
| Error    | `errorBg`     | `errorBorder`  | `errorText`    |
| Note/info| `noteBg`      | `noteBorder`   | `noteText`     |

Approval card additionally contains:
- Title: `10px`, uppercase, `0.6px` letter-spacing, `primaryIndigo`
- Body text: `12px`, `primaryText`
- Action buttons: Allow (filled `indigoMid`) · Deny (transparent, `indigoBorder` outline)

### App bar

- Background: `backgroundGrey` (same as page — no elevation, no color contrast)
- Bottom separator: `1px divider`
- Title: `titleMedium`, weight 500, truncated with ellipsis
- Hamburger and all non-toggle buttons: bare `IconButton`, no background

**Voice toggle buttons** (mic, speaker):
- ON state: `indigoTint` chip background, `primaryIndigo` icon
- OFF state: transparent background, `Color(0xFFB0BEC5)` (muted) icon
- Shape: `StadiumBorder` pill, `32px` height

**Sensitivity indicator** (app bar variant):
- Bare icon + label text, no chip background
- Color follows existing sensitivity level color (unchanged)

**New session button**: bare `IconButton`, `secondaryText` color

### Input bar

- Background: `backgroundGrey`
- Top separator: `1px divider`
- Padding: `6px 6px 6px 12px`
- Layout (left → right): `[TextField, flex:1]` `[RecorderButton?]` `[SendButton]`
- Send button rightmost; icon color `primaryIndigo`, transparent background
- RecorderButton: bare icon, `secondaryText` color
- TextField: `InputBorder.none`, hint text in `secondaryText`

### Navigation drawer

- Follows M3 `NavigationDrawer` defaults with the seed-color scheme
- No additional custom styling needed at this stage

### Splash screen & About page

- Use standard M3 surface/background colors from the theme
- No custom treatment needed beyond applying the `ThemeData` above

## Dark mode

`MyApp` follows the system brightness via `MediaQuery.platformBrightnessOf` and passes
`Brightness.light` / `Brightness.dark` to `ThemeData`. The `RelagentSemanticColors`
extension provides separate light/dark values for the six anchor colors (bg, border, text
for approval/error/note). M3 handles all other color roles automatically.

## Implementation scope

This spec covers `apps/` only. It does not include the settings page refactor (tracked
separately). The spec intentionally leaves assistant-message card background (white lift +
shadow) as a future option — to be validated once real content is available.
