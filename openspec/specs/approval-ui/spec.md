# approval-ui Specification

## Purpose

Defines how `SystemAction` messages from the engine are rendered as approval cards in the agentic chat page, including card content, grant/skip actions, and resolved states.
## Requirements
### Requirement: System Action Rendering

The chat history SHALL render `SystemAction` messages from the engine, displaying notifications as system notes and approvals as actionable cards.

#### Scenario: Notification displayed as system note

- **GIVEN** a `SystemAction` message with a `notification` field and no approvals
- **WHEN** the message is rendered in the chat history
- **THEN** the notification text SHALL be displayed as a visually distinct system note (not a chat bubble)

#### Scenario: Approvals displayed as card group

- **GIVEN** a `SystemAction` message with one or more approvals
- **WHEN** the message is rendered in the chat history
- **THEN** each approval SHALL be displayed as an individual actionable card

#### Scenario: SystemAction with both notification and approvals

- **GIVEN** a `SystemAction` message with both a `notification` and approvals
- **WHEN** the message is rendered
- **THEN** the notification SHALL be displayed above the approval cards

### Requirement: Approval Card Content

Each approval card SHALL display the approval details and provide per-card decision actions.

#### Scenario: Approval card displays request details

- **WHEN** an approval card is rendered in the pending actionable state
- **THEN** the card header SHALL show a large question mark icon, the approval `type` and `component` in monospace, and the `purpose` text in italic below
- **AND** the card SHALL show a "Current Sensitivity" row with the approval's sensitivity level in its semantic color
- **AND** if `allowedParameters` is non-empty the card SHALL show a parameter table with columns: Parameter, Value, Any value
- **AND** the card SHALL show a scope selector (This session / Any session)
- **AND** the card SHALL show an expiry selector with options: Never, 2d, 1d, 2h, 1h, 15min
- **AND** the card SHALL show "Continue without" and "Approve" action buttons at the bottom

#### Scenario: Parameter wildcard toggle

- **GIVEN** an approval has one or more `allowedParameters`
- **WHEN** the user toggles "Any value" for a parameter row
- **THEN** that parameter SHALL be sent as `wildcard_parameter` in the grant request (excluded from `allowed_parameters`)
- **AND** only one parameter MAY be wildcarded at a time
- **AND** the original parameter value SHALL remain visible but dimmed when wildcarded

#### Scenario: Sensitivity mismatch banner

- **GIVEN** an approval's sensitivity level is higher than the session's current sensitivity level
- **WHEN** the approval card is rendered
- **THEN** a prominent banner SHALL be displayed above the action buttons
- **AND** the banner SHALL include a button to change the session sensitivity to the approval's level

#### Scenario: No mismatch banner when levels match

- **GIVEN** an approval's sensitivity level is equal to or lower than the session's current sensitivity level
- **WHEN** the approval card is rendered
- **THEN** no sensitivity mismatch banner SHALL be displayed

### Requirement: Approval Grant Action

The user SHALL be able to grant an approval with scope and optional expiry. Granting SHALL be a single click that records the per-approval decision via the new per-approval endpoint.

#### Scenario: Scope selection

- **WHEN** an approval card is in the actionable state
- **THEN** a segmented button SHALL allow selecting "This session" or "Any session" scope
- **AND** "This session" SHALL be selected by default

#### Scenario: Expiry selection

- **WHEN** an approval card is in the actionable state
- **THEN** choice chips SHALL allow selecting an expiry duration
- **AND** no expiry ("Never") SHALL be selected by default

#### Scenario: Confirm grant with session scope

- **GIVEN** the user has selected "This session" scope and an optional expiry
- **WHEN** the user taps "Approve"
- **THEN** the app SHALL call `POST /sessions/{id}/approvals/{approval_id}/grant` with the grant parameters
- **AND** the approval card SHALL transition to a resolved "granted" state
- **AND** if every approval in the trailing in-flight `SystemAction` is now decided (granted or declined), the app SHALL follow up with `POST /sessions/{id}/continue`

#### Scenario: Confirm grant with global scope

- **GIVEN** the user has selected "Any session" scope and an optional expiry
- **WHEN** the user taps "Approve"
- **THEN** the app SHALL call `POST /grants` with the grant parameters (global grants endpoint unchanged)
- **AND** the app SHALL also call `POST /sessions/{id}/approvals/{approval_id}/grant` to record the per-approval decision in the in-flight `SystemAction`
- **AND** the approval card SHALL transition to a resolved "granted" state
- **AND** if every approval in the trailing in-flight `SystemAction` is now decided, the app SHALL follow up with `POST /sessions/{id}/continue`

#### Scenario: Grant API call fails

- **GIVEN** the user taps "Approve"
- **WHEN** the per-approval grant API call fails
- **THEN** an error message SHALL be shown
- **AND** the card SHALL remain in its actionable state
- **AND** the app SHALL NOT call `/continue`

### Requirement: Automatic Session Continuation

Once every approval in the trailing in-flight `SystemAction` is decided (each either granted or declined), the app SHALL automatically call `POST /sessions/{id}/continue` to drive the agent's next iteration. The engine SHALL NOT auto-continue on its own.

#### Scenario: Auto-continue when last approval is decided

- **GIVEN** the trailing in-flight `SystemAction` has N approvals where N−1 are already decided
- **WHEN** the user decides the last remaining approval (via Approve or Continue without)
- **THEN** the app SHALL automatically call `POST /sessions/{id}/continue`
- **AND** the chat SHALL show the pending state
- **AND** the response SHALL be appended to the chat history

#### Scenario: No continue button shown

- **GIVEN** an in-flight approval group with undecided approvals
- **THEN** no explicit "Continue" button SHALL be shown — continuation is triggered automatically once the last decision lands

#### Scenario: Engine does not auto-continue

- **WHEN** all per-approval decisions are recorded via `/grant` and `/decline`
- **THEN** the engine SHALL NOT invoke the agent on its own
- **AND** the next agent iteration SHALL only run after the client calls `/continue`

### Requirement: Stale Approval Continuation

When approvals are invalidated by a sensitivity change, the user SHALL explicitly re-run the session at the new sensitivity level.

#### Scenario: Continue after sensitivity adjustment invalidates approvals

- **GIVEN** approvals have been invalidated by a sensitivity change
- **WHEN** the invalidation is applied
- **THEN** a "Continue at new sensitivity" button SHALL be available
- **AND** tapping it SHALL call `POST /session/{id}/continue`

### Requirement: Approval Card Resolved State

Resolved approval cards SHALL collapse and be expandable to reveal their details.

#### Scenario: Resolved card collapsed by default

- **GIVEN** an approval has been granted or skipped
- **WHEN** the card is rendered
- **THEN** it SHALL display in a collapsed state showing only the header line and resolution indicator
- **AND** a chevron icon SHALL indicate the card is expandable

#### Scenario: Expand resolved card

- **WHEN** the user taps a resolved approval card header
- **THEN** the card SHALL expand to show the sensitivity, parameter table (if any), and the scope/expiry that were selected at grant time
- **AND** no action buttons SHALL be shown (read-only)

#### Scenario: Stale card

- **GIVEN** an approval was invalidated by a sensitivity change
- **WHEN** the card is rendered
- **THEN** it SHALL display as collapsed with an "Invalidated" label
- **AND** it SHALL not be expandable

### Requirement: Sensitivity Adjustment from Approval Context

The user SHALL be able to adjust the session sensitivity while resolving approvals, invalidating stale approval state.

#### Scenario: Adjust sensitivity via mismatch banner

- **GIVEN** an approval card shows a sensitivity mismatch banner
- **WHEN** the user taps the "Change to [level]" button on the banner
- **THEN** the session sensitivity SHALL be updated via `PUT /session/{id}/sensitivity`
- **AND** the sensitivity indicator SHALL update
- **AND** all pending approval cards in the group SHALL be marked as stale/invalidated

#### Scenario: Adjust sensitivity via indicator during approval resolution

- **GIVEN** unresolved approval cards are visible
- **WHEN** the user changes sensitivity via the app bar indicator picker
- **THEN** all pending approval cards SHALL be marked as stale/invalidated
- **AND** stale cards SHALL be visually disabled with a note

### Requirement: Historical Approval Rendering

Approval cards loaded from history SHALL render in a non-interactive resolved state when their containing `SystemAction` has `final=true`. Cards in an in-flight `SystemAction` (i.e., `final=false`) MAY be actionable.

#### Scenario: Granted approval from settled history

- **GIVEN** a `SystemAction` with `final=true` loaded from message history
- **AND** an approval in it has `granted: true`
- **WHEN** the card is rendered
- **THEN** it SHALL display in a collapsed resolved "granted" state
- **AND** it SHALL be expandable to reveal details

#### Scenario: Declined approval from settled history

- **GIVEN** a `SystemAction` with `final=true` loaded from message history
- **AND** an approval has `granted: false`
- **WHEN** the card is rendered
- **THEN** it SHALL display in a collapsed resolved "declined" state

#### Scenario: Pending approval from in-flight SystemAction

- **GIVEN** a `SystemAction` with `final=false` (the trailing message in the session)
- **AND** an approval has `granted: null` (undecided)
- **WHEN** the card is rendered
- **THEN** it SHALL display as actionable (Continue without / Approve available)

### Requirement: Approval Decline Action

The user SHALL be able to decline an individual approval, recording the decision per-approval via the new decline endpoint. Declining SHALL be a single click that does not trigger the agent.

#### Scenario: Continue without click

- **WHEN** the user taps "Continue without" on an approval card
- **THEN** the app SHALL call `POST /sessions/{id}/approvals/{approval_id}/decline`
- **AND** the card SHALL transition to a resolved "declined" state
- **AND** if every approval in the trailing in-flight `SystemAction` is now decided, the app SHALL follow up with `POST /sessions/{id}/continue`
- **AND** the engine SHALL NOT invoke the agent until `/continue` is called

#### Scenario: Decline API call fails

- **GIVEN** the user taps "Continue without"
- **WHEN** the decline API call fails
- **THEN** an error message SHALL be shown
- **AND** the card SHALL remain in its actionable state
- **AND** the app SHALL NOT call `/continue`

### Requirement: Cycle-Level Stop Bar

The approval group for an in-flight `SystemAction` SHALL include a cycle-level Stop control, separate from the per-card decision buttons. The Stop control SHALL settle the cycle without invoking the agent (see `cycle-stop-action`).

#### Scenario: Stop bar visible only for in-flight approval group

- **GIVEN** the trailing message is a `SystemAction` with `final=false`
- **WHEN** the approval group is rendered
- **THEN** a Stop bar SHALL appear at the bottom of the group, distinct from the per-card buttons

#### Scenario: Stop bar absent for settled approval groups

- **GIVEN** a `SystemAction` with `final=true` (loaded from history)
- **WHEN** the approval group is rendered
- **THEN** no Stop bar SHALL be displayed

