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

Dark mode variants of the base palette come from
`ColorScheme.fromSeed(brightness: Brightness.dark)`. Semantic anchor colors need explicit
dark-mode overrides:

```dart
approvalBgDark     = Color(0xFF1A237E)
approvalBorderDark = Color(0xFF7986CB)
errorBgDark        = Color(0xFF311919)
errorBorderDark    = Color(0xFFEF5350)
errorTextDark      = Color(0xFFEF9A9A)
noteBgDark         = Color(0xFF1B3A1F)
noteBorderDark     = Color(0xFF81C784)
noteTextDark       = Color(0xFFA5D6A7)
```

These live in `RelagentColors` alongside the light values, accessed via a
`RelagentThemeExtension` on `BuildContext` that switches on `Brightness.dark`.

## Typography

Use M3 defaults from `ColorScheme.fromSeed`. No custom font family. Text sizes follow
existing usage: `bodyLarge` (16px), `bodyMedium` (14px), `labelMedium` for secondary labels.

## Component Spec

### ThemeData (`main.dart`)

```dart
MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.system,
)
```

**Architecture:**
- `RelagentColors` (abstract final class) — all color constants (light + dark)
- `AppTheme` (abstract final class) — `light()` and `dark()` factory methods
- `RelagentThemeExtension` on `BuildContext` — semantic colors that switch by brightness:

```dart
extension RelagentThemeExtension on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  Color get approvalBg     => _isDark ? RelagentColors.approvalBgDark     : RelagentColors.approvalBg;
  Color get approvalBorder => _isDark ? RelagentColors.approvalBorderDark  : RelagentColors.approvalBorder;
  Color get errorBg        => _isDark ? RelagentColors.errorBgDark         : RelagentColors.errorBg;
  Color get errorBorder    => _isDark ? RelagentColors.errorBorderDark     : RelagentColors.errorBorder;
  Color get errorText      => _isDark ? RelagentColors.errorTextDark       : RelagentColors.errorText;
  Color get noteBg         => _isDark ? RelagentColors.noteBgDark          : RelagentColors.noteBg;
  Color get noteBorder     => _isDark ? RelagentColors.noteBorderDark      : RelagentColors.noteBorder;
  Color get noteText       => _isDark ? RelagentColors.noteTextDark        : RelagentColors.noteText;
}
```

### Assistant messages

- No background, no border — bare text rendered directly on `backgroundGrey`
- Alignment: left (`crossAxisAlignment.start`)
- Text style: `bodyMedium`, `primaryText`
- The assistant is the voice of the app; its messages are visually native to the surface

### User messages

- Right-aligned (`crossAxisAlignment.end`), max width 80% of chat width
- Outline bubble only: `1.5px` border in `indigoBorder`, no fill
- Border radius: `14 14 4 14` (sharp bottom-right corner toward the input)
- Text color: `primaryIndigo`, same `bodyMedium` size as assistant
- Intentionally low visual weight — user already knows what they typed

### Anchor cards (non-chat items)

Shape rule: left border only (`4px`), right corners rounded (`border-radius: 0 10px 10px 0`).
No other borders. The card sits flush to the left edge of its container.

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
- Bottom separator: `1px` `divider`
- Title: `titleMedium`, weight 500, truncated with ellipsis
- Hamburger and all non-toggle buttons: bare `IconButton`, no background

**Voice toggle buttons** (mic, speaker):
- ON state: `indigoTint` chip background, `primaryIndigo` icon, `StadiumBorder` pill
- OFF state: transparent background, `toggleOffMuted` icon
- No label text, only icon

**Sensitivity indicator** (app bar variant):
- Bare icon + label text, no chip background
- Color follows existing sensitivity level color (unchanged)

**New session button**: bare `IconButton`, `secondaryText` color

### Input bar

- Background: `backgroundGrey`
- Top separator: `1px` `divider`
- Padding: `12px 6px 6px 12px` (left, top, right, bottom)
- Layout (left → right): `[TextField, flex:1]` `[RecorderButton?]` `[SendButton]`
- Send button rightmost; `primaryIndigo` icon, transparent background
- RecorderButton: bare `IconButton`, `secondaryText` icon color
- TextField: `InputBorder.none`, hint text in `secondaryText`, multiline with `TextInputAction.send`

### Navigation drawer

- Follows M3 `NavigationDrawer` defaults with the seed-color scheme
- No additional custom styling needed at this stage

### Splash screen & About page

- Use standard M3 surface/background colors from the theme
- No custom treatment needed beyond applying the `ThemeData` above

## Dark mode

`MyApp` passes `ThemeMode.system` to `MaterialApp` with `AppTheme.light()` as `theme`
and `AppTheme.dark()` as `darkTheme`. The `RelagentThemeExtension` on `BuildContext`
provides separate light/dark values for the six anchor colors (bg, border, text for
approval/error/note). M3 handles all other color roles automatically.

## Implementation scope

This spec covers `apps/` only. It does not include the settings page refactor (tracked
separately). The spec intentionally leaves assistant-message card background (white lift +
shadow) as a future option — to be validated once real content is available.
