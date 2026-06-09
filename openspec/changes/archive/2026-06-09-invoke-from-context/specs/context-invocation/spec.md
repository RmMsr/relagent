## ADDED Requirements

### Requirement: Intent Reception — Share Sheet

The app SHALL register as a target for `android.intent.action.SEND` with MIME type `text/plain` via `receive_sharing_intent`, receiving both the cold-start (initial) intent and any warm intents delivered while the app is running.

#### Scenario: Cold start via share sheet

- **WHEN** the app is launched by an `ACTION_SEND` intent with `text/plain` content from another app
- **THEN** the app SHALL capture the shared text as a pending invocation during initialization
- **AND** after the splash screen completes, the app SHALL route to the invocation screen instead of the chat page

#### Scenario: Warm intent via share sheet

- **WHEN** an `ACTION_SEND` intent with `text/plain` content is delivered while the app is already running
- **THEN** the app SHALL capture the shared text as a pending invocation
- **AND** the app SHALL navigate to the invocation screen immediately, regardless of which page is currently shown

#### Scenario: No shared text

- **WHEN** an `ACTION_SEND` intent arrives with empty or null text content
- **THEN** the app SHALL ignore the intent and continue normal operation

---

### Requirement: Intent Reception — Process Text

The app SHALL register as a target for `android.intent.action.PROCESS_TEXT` to appear in the Android text-selection context menu. Reception is implemented via a platform channel in `MainActivity` that reads `Intent.EXTRA_PROCESS_TEXT` and forwards the text to Dart.

#### Scenario: Cold start via text selection

- **WHEN** the app is launched by an `ACTION_PROCESS_TEXT` intent from the text-selection context menu
- **THEN** the app SHALL capture the selected text as a pending invocation during initialization
- **AND** after the splash screen completes, the app SHALL route to the invocation screen instead of the chat page

#### Scenario: Warm PROCESS_TEXT intent

- **WHEN** an `ACTION_PROCESS_TEXT` intent is delivered to the running app via `onNewIntent`
- **THEN** the app SHALL capture the selected text as a pending invocation
- **AND** the app SHALL navigate to the invocation screen immediately

#### Scenario: Read-only flag

- **WHEN** the `ACTION_PROCESS_TEXT` intent carries `EXTRA_PROCESS_TEXT_READONLY = true`
- **THEN** the app SHALL still accept and display the text (read-only flag does not affect Relagent's behavior since it does not return modified text)

---

### Requirement: Pending Invocation Holder

The app SHALL maintain a single pending invocation holder (Riverpod provider) that stores at most one piece of incoming text at a time. Both the share-sheet path and the PROCESS_TEXT path write to this holder; the invocation screen reads and clears it.

#### Scenario: Single pending invocation

- **WHEN** an incoming text is received from either entry point
- **THEN** the holder SHALL store the text
- **AND** any previously stored pending text SHALL be replaced

#### Scenario: Invocation consumed

- **WHEN** the invocation screen is shown and has read the pending text
- **THEN** the holder SHALL be cleared
- **AND** subsequent navigation to the invocation screen without a new intent SHALL NOT pre-fill any text

---

### Requirement: Invocation Screen

The app SHALL provide an invocation screen (route `/invoke`) that presents the received text and lets the user add an instruction before sending.

#### Scenario: Screen layout

- **WHEN** the invocation screen is displayed
- **THEN** it SHALL show a single editable text field containing the instruction default followed by the received text formatted as a blockquote
- **AND** the screen SHALL show a Send button and a Cancel/Dismiss action

#### Scenario: Default instruction text

- **WHEN** the invocation screen is first shown with received text
- **THEN** the text field SHALL be pre-filled with the text `please explain` at the top, followed by a blank line, followed by the received text formatted as a blockquote
- **AND** the default instruction text (`please explain`) SHALL be selected so that the first keystroke replaces it

#### Scenario: Blockquote formatting

- **WHEN** the received text is inserted into the field
- **THEN** each line of the received text SHALL be prefixed with `> ` to form a plain-text blockquote
- **AND** the blockquote SHALL be separated from the instruction area by a blank line
- **AND** the text field renders plain text; `> ` characters appear literally (no Markdown rendering in the field itself)

#### Scenario: Cursor placement

- **WHEN** the invocation screen is shown
- **THEN** the cursor SHALL be placed at offset 0 (start of the instruction text)
- **AND** the keyboard SHALL be raised automatically

#### Scenario: User edits instruction

- **WHEN** the user types while the default instruction is selected
- **THEN** the typed text SHALL replace the selection
- **AND** the blockquote portion SHALL remain unchanged below

#### Scenario: Empty instruction allowed

- **WHEN** the user clears the instruction text and taps Send
- **THEN** the Send action SHALL proceed with only the blockquote content as the message

#### Scenario: Cancel

- **WHEN** the user dismisses the invocation screen without sending
- **THEN** the app SHALL navigate to the chat page
- **AND** no new session SHALL be started

---

### Requirement: New Session Dispatch

Sending from the invocation screen SHALL always start a new chat session.

#### Scenario: Send dispatches new session

- **WHEN** the user taps Send on the invocation screen
- **THEN** the app SHALL clear the current chat state (equivalent to `clearChat()`)
- **AND** the app SHALL send the full text field content as the first message of a new session
- **AND** the app SHALL navigate to the chat page
- **AND** the chat page SHALL display the sent message and the assistant response as it arrives

#### Scenario: Warm send discards active session

- **WHEN** the user taps Send while an active chat session exists
- **THEN** the existing session SHALL be discarded and a new session SHALL be started
- **AND** the behavior SHALL be identical to a cold-start invocation

#### Scenario: Engine not configured

- **WHEN** the user taps Send but no engine URL is configured
- **THEN** the app SHALL navigate to the chat page
- **AND** the chat page SHALL display the same error it would show for any unconfigured send attempt

---

### Requirement: Splash Routing

The splash page SHALL check for a pending invocation after initialization and route accordingly.

#### Scenario: Pending invocation on cold start

- **GIVEN** a pending invocation is set before the splash delay completes
- **WHEN** the splash delay finishes
- **THEN** the app SHALL route to `/invoke` instead of `/chat`

#### Scenario: No pending invocation on cold start

- **GIVEN** no pending invocation exists when the splash delay completes
- **WHEN** the splash delay finishes
- **THEN** the app SHALL route to `/chat` as today

---

### Requirement: Android Manifest Registration

The Android manifest SHALL declare intent filters so the app appears in the share sheet and text-selection context menu.

#### Scenario: Share sheet registration

- **WHEN** a user opens the Android share sheet from any app with text content
- **THEN** Relagent SHALL appear as a share target
- **AND** tapping it SHALL deliver an `ACTION_SEND` / `text/plain` intent to `MainActivity`

#### Scenario: Text-selection context menu registration

- **WHEN** a user selects text in any app and opens the context menu
- **THEN** Relagent SHALL appear as a PROCESS_TEXT target (labeled, e.g., "Ask Relagent")
- **AND** tapping it SHALL deliver an `ACTION_PROCESS_TEXT` intent to `MainActivity`
