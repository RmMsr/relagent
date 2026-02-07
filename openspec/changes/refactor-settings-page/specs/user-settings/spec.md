## MODIFIED Requirements

### Requirement: Settings Page UI
The settings page SHALL display configuration options as a scrollable list of tappable rows.

Each setting row MUST:
- Display the setting label prominently
- Show the current value as a subtitle or secondary text
- Provide a tap target of at least 48dp height for touch accessibility
- Open an edit modal (bottom sheet on mobile, dialog on desktop) when tapped

Settings MUST be organized into logical sections:
- Backend Selection (always visible at top)
- Backend-specific Configuration (shown based on selection)
- Voice Settings (always visible)

Changes to settings MUST be saved immediately upon confirmation in the edit modal.

#### Scenario: User views settings
- **GIVEN** the user opens the settings page
- **WHEN** the page loads
- **THEN** all settings are displayed as list rows showing current values
- **AND** the selected backend's configuration section is visible

#### Scenario: User edits a text setting on mobile
- **GIVEN** the user is on a mobile device
- **WHEN** the user taps a text setting row
- **THEN** a bottom sheet appears with an input field pre-filled with the current value
- **AND** the user can confirm or cancel the edit

#### Scenario: User edits a text setting on desktop
- **GIVEN** the user is on a desktop device (screen width > 600dp)
- **WHEN** the user taps a text setting row
- **THEN** a dialog appears with an input field pre-filled with the current value
- **AND** the user can confirm with Enter or cancel with Escape

#### Scenario: User changes a setting
- **GIVEN** the user is editing a setting in a modal
- **WHEN** the user confirms the change
- **THEN** the setting is saved immediately
- **AND** the modal closes
- **AND** the list row updates to show the new value

### Requirement: Keyboard Navigation
The settings page MUST support keyboard navigation for desktop users.

- Tab key navigates between setting rows
- Enter key opens the edit modal for the focused row
- Escape key cancels an open modal
- Arrow keys navigate within selection dialogs

#### Scenario: Desktop keyboard navigation
- **GIVEN** the user is on desktop with keyboard focus on a setting row
- **WHEN** the user presses Enter
- **THEN** the edit modal opens for that setting
- **AND** focus moves to the input field
