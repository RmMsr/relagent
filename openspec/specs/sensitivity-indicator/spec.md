# sensitivity-indicator Specification

## Purpose

Defines how the current session sensitivity level is displayed and changed by the user in the agentic chat page.

## Requirements

### Requirement: Sensitivity Level Display

The chat page SHALL display the current session sensitivity level as a color-coded indicator in the app bar.

#### Scenario: Indicator visible on chat page

- **WHEN** the agentic chat page is displayed
- **AND** a session is active
- **THEN** a sensitivity indicator SHALL be visible in the app bar actions area
- **AND** the indicator SHALL show a shield icon and the current sensitivity level
- **AND** on narrow screens (< 400dp) the indicator SHALL show the shield and the level's single-character abbreviation (O/S/P/C/I)
- **AND** on wider screens the indicator SHALL show the shield and the full level name

#### Scenario: Indicator color mapping

- **WHEN** the sensitivity level is displayed
- **THEN** the color SHALL follow this mapping:
  - OpenInformation (1): Green
  - Specific (2): Teal
  - Personal (3): Orange
  - Confidential (4): Deep orange
  - Internal (5): Red
- **AND** the level name SHALL be displayed as text alongside the color (not color alone)

#### Scenario: Sensitivity updated from chat response

- **WHEN** the app receives a `ChatResponse` from the engine (via message send or session continue)
- **THEN** the indicator SHALL update to reflect the `sensitivity_level` returned in the response

#### Scenario: No session active

- **WHEN** no session is active (e.g., first launch before any message)
- **THEN** the sensitivity indicator SHALL NOT be displayed

### Requirement: Sensitivity Level Picker

The user SHALL be able to change the session sensitivity level via a picker opened from the indicator.

#### Scenario: Open sensitivity picker

- **WHEN** the user taps the sensitivity indicator
- **THEN** a bottom sheet SHALL open showing all five sensitivity levels with their names, colors, and a short descriptive sentence per level

#### Scenario: Select a new sensitivity level

- **GIVEN** the sensitivity picker is open
- **WHEN** the user selects a different level
- **THEN** the app SHALL call `PUT /session/{id}/sensitivity` with the new level
- **AND** the indicator SHALL update optimistically to show the new level
- **AND** the picker SHALL close

#### Scenario: Sensitivity change fails

- **GIVEN** the user selects a new sensitivity level
- **WHEN** the `PUT /session/{id}/sensitivity` call fails
- **THEN** the indicator SHALL revert to the previous level
- **AND** an error message SHALL be shown to the user

#### Scenario: Select current level (no-op)

- **GIVEN** the sensitivity picker is open
- **WHEN** the user selects the already-active level
- **THEN** no API call SHALL be made
- **AND** the picker SHALL close
