## ADDED Requirements

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

Each approval card SHALL display the approval details and provide grant/skip actions.

#### Scenario: Approval card displays request details

- **WHEN** an approval card is rendered in the pending actionable state
- **THEN** the card header SHALL show a large question mark icon, the approval `type` and `component` in monospace, and the `purpose` text in italic below
- **AND** the card SHALL show a "Current Sensitivity" row with the approval's sensitivity level in its semantic color
- **AND** if `allowedParameters` is non-empty the card SHALL show a parameter table with columns: Parameter, Value, Any value
- **AND** the card SHALL show a scope selector (This session / Any session)
- **AND** the card SHALL show an expiry selector with options: Never, 2d, 1d, 2h, 1h, 15min
- **AND** the card SHALL show Skip and Approve action buttons at the bottom

#### Scenario: Parameter wildcard toggle

- **GIVEN** an approval has one or more `allowedParameters`
- **WHEN** the user toggles "Any value" for a parameter row
- **THEN** that parameter SHALL be sent as `*` (wildcard) in the grant request
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

The user SHALL be able to grant an approval with scope and optional expiry.

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
- **THEN** the app SHALL call `POST /session/{id}/grants` with the grant parameters
- **AND** the approval card SHALL transition to a resolved "granted" state
- **AND** if all approvals in the group are now resolved the session SHALL continue automatically

#### Scenario: Confirm grant with global scope

- **GIVEN** the user has selected "Any session" scope and an optional expiry
- **WHEN** the user taps "Approve"
- **THEN** the app SHALL call `POST /grants` with the grant parameters
- **AND** the approval card SHALL transition to a resolved "granted" state
- **AND** if all approvals in the group are now resolved the session SHALL continue automatically

#### Scenario: Grant API call fails

- **GIVEN** the user taps "Approve"
- **WHEN** the API call fails
- **THEN** an error message SHALL be shown
- **AND** the card SHALL remain in its actionable state

### Requirement: Approval Skip Action

The user SHALL be able to skip an approval without making an API call.

#### Scenario: Skip an approval

- **WHEN** the user taps "Skip" on an approval card
- **THEN** the app SHALL call `POST /sessions/{id}/reject_approvals` with the approval ID
- **AND** the card SHALL transition to a resolved "skipped" state
- **AND** if all approvals in the group are now resolved the session SHALL continue automatically

### Requirement: Automatic Session Continuation

Once all approvals in a group are resolved (each either granted or skipped), the session SHALL continue automatically without requiring explicit user action.

#### Scenario: Auto-continue when last approval is resolved

- **GIVEN** a group of N approvals where N−1 are already resolved
- **WHEN** the user resolves the last remaining approval
- **THEN** the app SHALL automatically call `POST /session/{id}/continue`
- **AND** the chat SHALL show the pending state
- **AND** the response SHALL be appended to the chat history

#### Scenario: No continue button shown

- **GIVEN** a pending approval group
- **THEN** no explicit "Continue" button SHALL be shown — continuation is triggered automatically

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

Approval cards loaded from history SHALL render in a non-interactive resolved state.

#### Scenario: Granted approval from history

- **GIVEN** a `SystemAction` loaded from message history
- **AND** an approval in it has `granted: true`
- **WHEN** the card is rendered
- **THEN** it SHALL display in a collapsed resolved "granted" state
- **AND** it SHALL be expandable to reveal details

#### Scenario: Ungranted approval from history (not latest message)

- **GIVEN** a `SystemAction` loaded from message history
- **AND** an approval has `granted: false`
- **AND** the `SystemAction` is NOT the most recent message
- **WHEN** the card is rendered
- **THEN** it SHALL display in a collapsed resolved "skipped" state

#### Scenario: Pending approval from history (latest message)

- **GIVEN** a `SystemAction` loaded from message history
- **AND** it is the most recent message
- **AND** approvals have `granted: false`
- **WHEN** the card is rendered
- **THEN** it SHALL display as actionable (grant/skip available)
